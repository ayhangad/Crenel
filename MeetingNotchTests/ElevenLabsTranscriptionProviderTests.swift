import Foundation
import XCTest
@testable import MeetingNotch

final class ElevenLabsTranscriptionProviderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotch-ElevenLabsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUploadUsesKeychainKeyDiarizationTurkishAndScribeV2() async throws {
        let audioURL = try audioFile()
        let client = MockTranscriptionHTTPClient(uploadResponse: try response(
            statusCode: 200,
            data: fixtureData()
        ))
        let provider = ElevenLabsTranscriptionProvider(
            apiKeyRepository: StubAPIKeyRepository(apiKey: "test-eleven-key"),
            httpClient: client,
            endpoint: URL(string: "https://example.test/v1/speech-to-text")!
        )
        let idempotencyKey = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let progress = ProgressRecorder()

        let result = try await provider.transcribe(
            TranscriptionRequest(
                audioFileURL: audioURL,
                languageCode: "TR",
                requestsDiarization: true,
                idempotencyKey: idempotencyKey
            ),
            uploadProgress: { value in Task { await progress.append(value) } }
        )

        let capturedRequest = await client.lastUploadRequest()
        let capturedBody = await client.lastUploadBody()
        let uploadedBodyURL = await client.lastUploadFileURL()
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(capturedBody)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-eleven-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains(
            "MeetingNotch-\(idempotencyKey.uuidString)"
        ) == true)
        XCTAssertTrue(bodyText.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(bodyText.contains("name=\"diarize\"\r\n\r\ntrue"))
        XCTAssertTrue(bodyText.contains("name=\"language_code\"\r\n\r\ntr"))
        XCTAssertTrue(bodyText.contains("name=\"file\"; filename=\"meeting.m4a\""))
        XCTAssertEqual(result.providerID, .elevenLabs)
        XCTAssertEqual(result.transcript.languageCode, "tr")
        XCTAssertEqual(result.transcript.segments.map(\.speakerID), ["speaker_0", "speaker_1"])
        XCTAssertEqual(result.transcript.segments.map(\.text), ["Merhaba dünya.", "Selam!"])
        XCTAssertEqual(result.transcript.segments[0].startTime, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.transcript.segments[0].endTime, 1.1, accuracy: 0.001)
        XCTAssertEqual(result.transcript.segments[1].startTime, 1.2, accuracy: 0.001)
        let progressValues = await progress.values()
        XCTAssertTrue(progressValues.contains(0.5))
        XCTAssertFalse(uploadedBodyURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? true)
    }

    func testAutomaticLanguageDetectionOmitsLanguageField() async throws {
        let client = MockTranscriptionHTTPClient(uploadResponse: try response(
            statusCode: 200,
            data: fixtureData()
        ))
        let provider = ElevenLabsTranscriptionProvider(
            apiKeyRepository: StubAPIKeyRepository(apiKey: "key"),
            httpClient: client
        )

        _ = try await provider.transcribe(
            TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
            uploadProgress: { _ in }
        )

        let capturedBody = await client.lastUploadBody()
        let body = try XCTUnwrap(capturedBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("name=\"language_code\""))
    }

    func testMissingKeyIsAuthenticationFailureWithoutUploading() async throws {
        let client = MockTranscriptionHTTPClient(uploadResponse: try response(
            statusCode: 200,
            data: fixtureData()
        ))
        let provider = ElevenLabsTranscriptionProvider(
            apiKeyRepository: StubAPIKeyRepository(apiKey: nil),
            httpClient: client
        )

        do {
            _ = try await provider.transcribe(
                TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
                uploadProgress: { _ in }
            )
            XCTFail("Eksik anahtar upload başlatmamalıydı.")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .authentication)
        }
        let capturedRequest = await client.lastUploadRequest()
        XCTAssertNil(capturedRequest)
    }

    func testHTTPFailuresAreNormalizedAndRetryAfterIsRead() async throws {
        let cases: [(Int, String?, TranscriptionServiceError)] = [
            (401, nil, .authentication),
            (429, "7", .rateLimited(retryAfter: 7)),
            (500, nil, .providerUnavailable),
            (422, nil, .invalidResponse)
        ]

        for (statusCode, retryAfter, expected) in cases {
            let client = MockTranscriptionHTTPClient(uploadResponse: try response(
                statusCode: statusCode,
                data: Data("provider detail must not escape".utf8),
                headers: retryAfter.map { ["Retry-After": $0] } ?? [:]
            ))
            let provider = ElevenLabsTranscriptionProvider(
                apiKeyRepository: StubAPIKeyRepository(apiKey: "key"),
                httpClient: client
            )
            do {
                _ = try await provider.transcribe(
                    TranscriptionRequest(audioFileURL: try audioFile(), languageCode: "tr"),
                    uploadProgress: { _ in }
                )
                XCTFail("HTTP \(statusCode) başarısız olmalıydı.")
            } catch {
                XCTAssertEqual(error as? TranscriptionServiceError, expected)
            }
        }
    }

    func testTransportTimeoutAndInvalidFixtureAreNormalized() async throws {
        let timeoutClient = MockTranscriptionHTTPClient(uploadError: URLError(.timedOut))
        let timeoutProvider = ElevenLabsTranscriptionProvider(
            apiKeyRepository: StubAPIKeyRepository(apiKey: "key"),
            httpClient: timeoutClient
        )
        do {
            _ = try await timeoutProvider.transcribe(
                TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
                uploadProgress: { _ in }
            )
            XCTFail("Timeout normalize edilmeliydi.")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .timeout)
        }

        XCTAssertThrowsError(try ElevenLabsTranscriptParser().parse(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? TranscriptionServiceError, .invalidResponse)
        }
    }

    func testAPIKeyValidatorUsesOfficialModelsEndpointAndNormalizes401() async throws {
        let successClient = MockTranscriptionHTTPClient(dataResponse: try response(
            statusCode: 200,
            data: Data("[]".utf8)
        ))
        try await ElevenLabsAPIKeyValidator(httpClient: successClient).validate(" key ")
        let capturedRequest = await successClient.lastDataRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "key")

        let failureClient = MockTranscriptionHTTPClient(dataResponse: try response(
            statusCode: 401,
            data: Data()
        ))
        do {
            try await ElevenLabsAPIKeyValidator(httpClient: failureClient).validate("bad")
            XCTFail("401 kabul edilmemeliydi.")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .authentication)
        }
    }

    func testLaunchCleanupRemovesOnlyMeetingNotchMultipartArtifacts() throws {
        let stale = FileManager.default.temporaryDirectory.appending(
            path: "\(MultipartFormFileBuilder.temporaryFilePrefix)\(UUID().uuidString).multipart"
        )
        let unrelated = root.appending(path: "unrelated.multipart")
        try Data("synthetic-upload".utf8).write(to: stale)
        try Data("keep".utf8).write(to: unrelated)

        MultipartFormFileBuilder.removeStaleUploadBodies()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func audioFile() throws -> URL {
        let url = root.appending(path: "meeting.m4a")
        try Data("fake-m4a-audio".utf8).write(to: url)
        return url
    }

    private func fixtureData() -> Data {
        Data(#"""
        {
          "language_code": "tr",
          "language_probability": 0.99,
          "text": "Merhaba dünya. Selam!",
          "words": [
            {"text":"Merhaba","start":0.1,"end":0.5,"type":"word","speaker_id":"speaker_0"},
            {"text":" ","start":0.5,"end":0.5,"type":"spacing","speaker_id":"speaker_0"},
            {"text":"dünya.","start":0.5,"end":1.1,"type":"word","speaker_id":"speaker_0"},
            {"text":" ","start":1.1,"end":1.1,"type":"spacing","speaker_id":"speaker_1"},
            {"text":"Selam!","start":1.2,"end":1.7,"type":"word","speaker_id":"speaker_1"}
          ]
        }
        """#.utf8)
    }

    private func response(
        statusCode: Int,
        data: Data,
        headers: [String: String] = [:]
    ) throws -> TranscriptionHTTPResponse {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        ))
        return TranscriptionHTTPResponse(data: data, response: response)
    }
}

private actor ProgressRecorder {
    private var recorded: [Double] = []
    func append(_ value: Double) { recorded.append(value) }
    func values() -> [Double] { recorded }
}

private actor StubAPIKeyRepository: APIKeyRepository {
    private var key: String?
    init(apiKey: String?) { key = apiKey }
    func apiKey(for provider: TranscriptionProviderID) -> String? { key }
    func saveAPIKey(_ apiKey: String, for provider: TranscriptionProviderID) { key = apiKey }
    func deleteAPIKey(for provider: TranscriptionProviderID) { key = nil }
}

private actor MockTranscriptionHTTPClient: TranscriptionHTTPClient {
    private let configuredDataResponse: TranscriptionHTTPResponse?
    private let configuredUploadResponse: TranscriptionHTTPResponse?
    private let configuredUploadError: Error?
    private var dataRequest: URLRequest?
    private var uploadRequest: URLRequest?
    private var uploadBody: Data?
    private var uploadFileURL: URL?

    init(
        dataResponse: TranscriptionHTTPResponse? = nil,
        uploadResponse: TranscriptionHTTPResponse? = nil,
        uploadError: Error? = nil
    ) {
        configuredDataResponse = dataResponse
        configuredUploadResponse = uploadResponse
        configuredUploadError = uploadError
    }

    func data(for request: URLRequest) throws -> TranscriptionHTTPResponse {
        dataRequest = request
        guard let configuredDataResponse else { throw URLError(.badServerResponse) }
        return configuredDataResponse
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping TranscriptionUploadProgress
    ) throws -> TranscriptionHTTPResponse {
        uploadRequest = request
        uploadFileURL = fileURL
        uploadBody = try Data(contentsOf: fileURL)
        progress(0.5)
        if let configuredUploadError { throw configuredUploadError }
        guard let configuredUploadResponse else { throw URLError(.badServerResponse) }
        return configuredUploadResponse
    }

    func lastDataRequest() -> URLRequest? { dataRequest }
    func lastUploadRequest() -> URLRequest? { uploadRequest }
    func lastUploadBody() -> Data? { uploadBody }
    func lastUploadFileURL() -> URL? { uploadFileURL }
}
