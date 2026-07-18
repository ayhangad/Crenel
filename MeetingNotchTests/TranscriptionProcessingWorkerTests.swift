import Foundation
import XCTest
@testable import MeetingNotch

final class TranscriptionProcessingWorkerTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotch-WorkerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MeetingNotch-WorkerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName { defaults.removePersistentDomain(forName: suiteName) }
        try? FileManager.default.removeItem(at: root)
    }

    func testWorkerClaimsTranscribesPersistsCleansRawTracksAndCompletesQueue() async throws {
        let meetingRepository = FileMeetingRepository(rootURL: root)
        let meeting = try await meetingRepository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        let job = try await queue.enqueue(meetingID: meeting.id, providerID: .elevenLabs)
        let settings = UserDefaultsAppSettingsRepository(
            defaults: defaults,
            storageKey: "preferences"
        )
        var preferences = AppPreferences.default
        preferences.provider.languageCode = "tr"
        try await settings.save(preferences)
        let provider = WorkerStubProvider(mode: .success)
        let events = WorkerEventRecorder()
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            providers: WorkerProviderResolver(provider: provider),
            retryPolicy: TranscriptionRetryPolicy(maximumAttempts: 1, baseDelay: 0),
            onEvent: { event in await events.append(event) }
        )

        await worker.drain()

        let remainingJobs = try await queue.allJobs()
        XCTAssertTrue(remainingJobs.isEmpty)
        let reloadedMeetings = try await meetingRepository.loadAll()
        let updated = try XCTUnwrap(reloadedMeetings.first)
        XCTAssertEqual(updated.processingStatus, .completed)
        let loadedTranscription = try await meetingRepository.loadTranscription(for: meeting.id)
        let stored = try XCTUnwrap(loadedTranscription)
        XCTAssertEqual(stored.providerID, .elevenLabs)
        XCTAssertEqual(stored.transcript.text, "Merhaba")
        XCTAssertEqual(stored.summary?.overview, "")
        let capturedRequest = await provider.lastRequest()
        XCTAssertEqual(capturedRequest?.languageCode, "tr")
        XCTAssertEqual(capturedRequest?.idempotencyKey, job.idempotencyKey)

        let meetingDirectory = root.appending(path: "Meetings/\(meeting.id.uuidString)")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: meetingDirectory.appending(path: meeting.audioFileName).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: meetingDirectory.appending(path: "microphone.m4a").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: meetingDirectory.appending(path: "system-audio.m4a").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: meetingDirectory.appending(path: "meeting.md").path
        ))
        let recordedEvents = await events.kinds()
        XCTAssertEqual(
            Set(recordedEvents),
            Set(["started", "progress", "transcribing", "summarizing", "completed"])
        )
    }

    func testWorkerPersistsNormalizedFailureAndLeavesAudioForRetry() async throws {
        let meetingRepository = FileMeetingRepository(rootURL: root)
        let meeting = try await meetingRepository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        _ = try await queue.enqueue(meetingID: meeting.id, providerID: .elevenLabs)
        let settings = UserDefaultsAppSettingsRepository(defaults: defaults, storageKey: "preferences")
        let provider = WorkerStubProvider(mode: .failure(.authentication))
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            providers: WorkerProviderResolver(provider: provider),
            retryPolicy: TranscriptionRetryPolicy(maximumAttempts: 1, baseDelay: 0)
        )

        await worker.drain()

        let remainingJobs = try await queue.allJobs()
        let failed = try XCTUnwrap(remainingJobs.first)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.lastFailure, .authentication)
        XCTAssertEqual(failed.attemptCount, 1)
        let transcription = try await meetingRepository.loadTranscription(for: meeting.id)
        XCTAssertNil(transcription)
        let audioURL = await meetingRepository.audioFileURL(for: meeting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testSummaryFailureStillPersistsSuccessfulTranscript() async throws {
        let meetingRepository = FileMeetingRepository(rootURL: root)
        let meeting = try await meetingRepository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        _ = try await queue.enqueue(meetingID: meeting.id, providerID: .elevenLabs)
        let settings = UserDefaultsAppSettingsRepository(defaults: defaults, storageKey: "preferences")
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            providers: WorkerProviderResolver(provider: WorkerStubProvider(mode: .success)),
            summaryService: FailingSummaryService(),
            retryPolicy: TranscriptionRetryPolicy(maximumAttempts: 1, baseDelay: 0)
        )

        await worker.drain()

        let loadedTranscription = try await meetingRepository.loadTranscription(for: meeting.id)
        let stored = try XCTUnwrap(loadedTranscription)
        XCTAssertEqual(stored.transcript.text, "Merhaba")
        XCTAssertNil(stored.summary)
        let jobs = try await queue.allJobs()
        XCTAssertTrue(jobs.isEmpty)
    }

    @MainActor
    func testAppStateMovesProcessingFlowToCompleted() async throws {
        let state = AppState()
        let meeting = StoredMeeting(
            id: UUID(),
            title: "State",
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            sourceMeeting: nil,
            audioFileName: "recording.m4a"
        )
        state.replaceStoredMeetings([meeting])
        let job = ProcessingJob(meetingID: meeting.id, providerID: .elevenLabs, state: .running)

        state.processingStarted(job)
        XCTAssertEqual(state.meetingFlow.phase, .uploading)
        state.updateTranscriptionUploadProgress(0.75)
        XCTAssertEqual(state.meetingFlow, .uploading(progress: 0.75))
        state.processingBeganTranscribing()
        XCTAssertEqual(state.meetingFlow.phase, .transcribing)
        var completed = meeting
        completed.processingStatus = .completed
        state.processingCompleted(completed)

        XCTAssertEqual(state.meetingFlow, .completed(meetingID: meeting.id))
        XCTAssertTrue(state.processingJobs.isEmpty)
        XCTAssertEqual(state.storedMeetings.first?.processingStatus, .completed)
    }

    private func makeCapture() throws -> RecordingCaptureResult {
        let id = UUID()
        let directory = root
            .appending(path: "Temporary", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let finalAudio = directory.appending(path: "recording.m4a")
        let microphone = directory.appending(path: "microphone.m4a")
        let systemAudio = directory.appending(path: "system-audio.m4a")
        try Data("final".utf8).write(to: finalAudio)
        try Data("microphone".utf8).write(to: microphone)
        try Data("system".utf8).write(to: systemAudio)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RecordingSession(
            id: id,
            meetingID: nil,
            sourceMeeting: nil,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            audioFileURL: finalAudio
        )
        return RecordingCaptureResult(
            session: session,
            tracks: [
                CapturedAudioTrack(source: .microphone, fileURL: microphone, firstSampleTime: 0),
                CapturedAudioTrack(source: .systemAudio, fileURL: systemAudio, firstSampleTime: 0)
            ]
        )
    }

}

private struct WorkerProviderResolver: TranscriptionProviderResolving {
    let provider: WorkerStubProvider
    func provider(for id: TranscriptionProviderID) -> (any TranscriptionProvider)? {
        id == .elevenLabs ? provider : nil
    }
}

private actor WorkerStubProvider: TranscriptionProvider {
    enum Mode: Sendable {
        case success
        case failure(TranscriptionServiceError)
    }

    nonisolated let id = TranscriptionProviderID.elevenLabs
    nonisolated let capabilities = TranscriptionProviderCapabilities(
        supportedFileExtensions: ["m4a"],
        maximumFileSizeBytes: 1_000_000,
        supportsDiarization: true,
        supportsAutomaticLanguageDetection: true
    )
    private let mode: Mode
    private var request: TranscriptionRequest?

    init(mode: Mode) { self.mode = mode }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) throws -> TranscriptionResult {
        self.request = request
        uploadProgress(0.5)
        switch mode {
        case .success:
            return TranscriptionResult(
                providerID: .elevenLabs,
                transcript: Transcript(
                    text: "Merhaba",
                    languageCode: "tr",
                    segments: [TranscriptSegment(
                        speakerID: "speaker_0",
                        startTime: 0,
                        endTime: 1,
                        text: "Merhaba"
                    )]
                )
            )
        case .failure(let error):
            throw error
        }
    }

    func lastRequest() -> TranscriptionRequest? { request }
}

private actor WorkerEventRecorder {
    private var recorded: [String] = []

    func append(_ event: TranscriptionProcessingEvent) {
        switch event {
        case .started:
            recorded.append("started")
        case .uploadProgress:
            recorded.append("progress")
        case .transcribing:
            recorded.append("transcribing")
        case .summarizing:
            recorded.append("summarizing")
        case .completed:
            recorded.append("completed")
        case .failed:
            recorded.append("failed")
        }
    }

    func kinds() -> [String] { recorded }
}

private struct FailingSummaryService: MeetingSummaryGenerating {
    struct Failure: Error {}
    func generate(from transcript: Transcript) async throws -> MeetingSummary {
        throw Failure()
    }
}
