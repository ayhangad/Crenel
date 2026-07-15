import XCTest
@testable import MeetingNotch

final class TranscriptionFoundationTests: XCTestCase {
    func testCapabilitiesNormalizeExtensions() {
        let capabilities = makeCapabilities(extensions: [".M4A", "mp3"])

        XCTAssertEqual(capabilities.supportedFileExtensions, ["m4a", "mp3"])
    }

    func testFileValidatorAcceptsSupportedNonEmptyFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "recording.m4a")
        try Data(repeating: 1, count: 16).write(to: file)

        let request = TranscriptionRequest(audioFileURL: file, languageCode: nil)

        XCTAssertNoThrow(
            try TranscriptionFileValidator().validate(
                request: request,
                capabilities: makeCapabilities(maximumBytes: 16)
            )
        )
    }

    func testFileValidatorRejectsOversizedAndUnsupportedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "recording.wav")
        try Data(repeating: 1, count: 17).write(to: file)
        let request = TranscriptionRequest(audioFileURL: file, languageCode: "tr")

        XCTAssertThrowsError(
            try TranscriptionFileValidator().validate(
                request: request,
                capabilities: makeCapabilities(maximumBytes: 16)
            )
        ) { error in
            XCTAssertEqual(error as? TranscriptionServiceError, .invalidFile(.tooLarge))
        }
    }

    func testFileValidatorChecksProviderFeatures() throws {
        let request = TranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/unused.m4a"),
            languageCode: "tr",
            requestsDiarization: true
        )
        let capabilities = TranscriptionProviderCapabilities(
            supportedFileExtensions: ["m4a"],
            maximumFileSizeBytes: 100,
            supportsDiarization: false,
            supportsAutomaticLanguageDetection: true
        )

        XCTAssertThrowsError(
            try TranscriptionFileValidator().validate(
                request: request,
                capabilities: capabilities
            )
        ) { error in
            XCTAssertEqual(
                error as? TranscriptionServiceError,
                .unsupportedFeature(.diarization)
            )
        }
    }

    func testHTTPAndTransportErrorsAreNormalized() {
        XCTAssertEqual(
            TranscriptionErrorNormalizer.normalizeHTTPStatus(401),
            .authentication
        )
        XCTAssertEqual(
            TranscriptionErrorNormalizer.normalizeHTTPStatus(429, retryAfter: 7),
            .rateLimited(retryAfter: 7)
        )
        XCTAssertEqual(
            TranscriptionErrorNormalizer.normalize(URLError(.timedOut)),
            .timeout
        )
        XCTAssertEqual(
            TranscriptionErrorNormalizer.normalize(URLError(.notConnectedToInternet)),
            .networkUnavailable
        )
    }

    func testRetryPolicyIsBoundedAndKeepsRequestIdempotencyKey() async throws {
        let recorder = RetryAttemptRecorder()
        let request = TranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/recording.m4a"),
            languageCode: nil
        )
        let policy = TranscriptionRetryPolicy(
            maximumAttempts: 3,
            baseDelay: 0,
            maximumDelay: 0
        )

        let value: String = try await policy.execute(sleeper: { _ in }) { attempt in
            await recorder.record(attempt: attempt, key: request.idempotencyKey)
            if attempt < 3 { throw URLError(.timedOut) }
            return "ok"
        }

        let attempts = await recorder.attempts
        let keys = await recorder.keys
        XCTAssertEqual(value, "ok")
        XCTAssertEqual(attempts, [1, 2, 3])
        XCTAssertEqual(Set(keys), [request.idempotencyKey])
    }

    func testRetryPolicyDoesNotRetryAuthenticationFailure() async {
        let recorder = RetryAttemptRecorder()
        let policy = TranscriptionRetryPolicy(maximumAttempts: 3, baseDelay: 0)

        do {
            let _: String = try await policy.execute(sleeper: { _ in }) { attempt in
                await recorder.record(attempt: attempt, key: UUID())
                throw TranscriptionServiceError.authentication
            }
            XCTFail("Authentication hatası ile işlem bitmeliydi.")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .authentication)
        }

        let attempts = await recorder.attempts
        XCTAssertEqual(attempts, [1])
    }

    func testRetryPolicyStopsWhenTaskIsCancelled() async {
        let recorder = RetryAttemptRecorder()
        let policy = TranscriptionRetryPolicy(maximumAttempts: 3, baseDelay: 10)
        let task = Task<String, Error> {
            try await policy.execute { attempt in
                await recorder.record(attempt: attempt, key: UUID())
                throw TranscriptionServiceError.timeout
            }
        }

        for _ in 0..<20 {
            let attempts = await recorder.attempts
            if !attempts.isEmpty { break }
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("İptal edilen retry işlemi sonuç üretmemeliydi.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let attempts = await recorder.attempts
        XCTAssertEqual(attempts, [1])
    }

    @MainActor
    func testProgressBridgeFeedsMeetingFlowStateMachine() async {
        let state = AppState(initialFlow: .uploading(progress: 0))
        let handler = TranscriptionProgressBridge(appState: state).uploadProgressHandler()

        handler(0.64)
        for _ in 0..<10 where state.meetingFlow != .uploading(progress: 0.64) {
            await Task.yield()
        }

        XCTAssertEqual(state.meetingFlow, .uploading(progress: 0.64))
    }

    private func makeCapabilities(
        extensions: Set<String> = ["m4a"],
        maximumBytes: Int64 = 1_000
    ) -> TranscriptionProviderCapabilities {
        TranscriptionProviderCapabilities(
            supportedFileExtensions: extensions,
            maximumFileSizeBytes: maximumBytes,
            supportsDiarization: true,
            supportsAutomaticLanguageDetection: true
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotch-TranscriptionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor RetryAttemptRecorder {
    private(set) var attempts: [Int] = []
    private(set) var keys: [UUID] = []

    func record(attempt: Int, key: UUID) {
        attempts.append(attempt)
        keys.append(key)
    }
}
