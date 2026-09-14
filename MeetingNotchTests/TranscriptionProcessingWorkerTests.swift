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
        let job = try await queue.enqueue(meetingID: meeting.id)
        let settings = UserDefaultsAppSettingsRepository(
            defaults: defaults,
            storageKey: "preferences"
        )
        var preferences = AppPreferences.default
        preferences.transcription.languageCode = "tr"
        try await settings.save(preferences)
        let service = WorkerStubTranscriptionService(mode: .success)
        let events = WorkerEventRecorder()
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            transcriptionService: service,
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
        XCTAssertEqual(stored.transcript.text, "Merhaba")
        XCTAssertEqual(stored.summary?.overview, "")
        let capturedRequest = await service.lastRequest()
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
        _ = try await queue.enqueue(meetingID: meeting.id)
        let settings = UserDefaultsAppSettingsRepository(defaults: defaults, storageKey: "preferences")
        let service = WorkerStubTranscriptionService(mode: .failure(.authentication))
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            transcriptionService: service,
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

    func testCancellingWorkerMarksRunningJobFailedAndPreservesItForRetry() async throws {
        let meetingRepository = FileMeetingRepository(rootURL: root)
        let meeting = try await meetingRepository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        _ = try await queue.enqueue(meetingID: meeting.id)
        let settings = UserDefaultsAppSettingsRepository(defaults: defaults, storageKey: "preferences")
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            transcriptionService: BlockingWorkerTranscriptionService(),
            retryPolicy: TranscriptionRetryPolicy(maximumAttempts: 1, baseDelay: 0)
        )

        let drainTask = Task { await worker.drain() }
        for _ in 0..<100 {
            if try await queue.allJobs().first?.state == .running { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let runningJobs = try await queue.allJobs()
        XCTAssertEqual(runningJobs.first?.state, .running)

        drainTask.cancel()
        await drainTask.value

        let cancelledJobs = try await queue.allJobs()
        let cancelled = try XCTUnwrap(cancelledJobs.first)
        XCTAssertEqual(cancelled.state, .failed)
        XCTAssertEqual(cancelled.lastFailure, .cancelled)
        let audioURL = await meetingRepository.audioFileURL(for: meeting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testSummaryFailureStillPersistsSuccessfulTranscript() async throws {
        let meetingRepository = FileMeetingRepository(rootURL: root)
        let meeting = try await meetingRepository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        _ = try await queue.enqueue(meetingID: meeting.id)
        let settings = UserDefaultsAppSettingsRepository(defaults: defaults, storageKey: "preferences")
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            transcriptionService: WorkerStubTranscriptionService(mode: .success),
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

    func testNetworkRecoveryRetriesDurableJobWithoutChangingIdentity() async throws {
        let meetingRepository = FileMeetingRepository(rootURL: root)
        let meeting = try await meetingRepository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        let original = try await queue.enqueue(meetingID: meeting.id)
        let settings = UserDefaultsAppSettingsRepository(
            defaults: defaults,
            storageKey: "preferences"
        )
        let service = RecoveringWorkerTranscriptionService()
        let worker = TranscriptionProcessingWorker(
            queue: queue,
            meetingRepository: meetingRepository,
            settingsRepository: settings,
            transcriptionService: service,
            retryPolicy: TranscriptionRetryPolicy(maximumAttempts: 1, baseDelay: 0)
        )

        await worker.drain()

        let offlineJobs = try await queue.allJobs()
        let offlineJob = try XCTUnwrap(offlineJobs.first)
        XCTAssertEqual(offlineJob.state, .failed)
        XCTAssertEqual(offlineJob.lastFailure, .networkUnavailable)
        XCTAssertEqual(offlineJob.idempotencyKey, original.idempotencyKey)
        let audioURL = await meetingRepository.audioFileURL(for: meeting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))

        let retried = try await queue.retry(meetingID: meeting.id)
        XCTAssertEqual(retried?.idempotencyKey, original.idempotencyKey)
        await worker.drain()

        let completedJobs = try await queue.allJobs()
        let transcription = try await meetingRepository.loadTranscription(for: meeting.id)
        let requestCount = await service.requestCount()
        XCTAssertTrue(completedJobs.isEmpty)
        XCTAssertEqual(transcription?.transcript.text, "Bağlantı geri geldi")
        XCTAssertEqual(requestCount, 2)
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
        let job = ProcessingJob(meetingID: meeting.id, state: .running)

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

    func testSummaryRetryUsesDurableTranscriptWithoutUploadingAudioAgain() async throws {
        let repository = FileMeetingRepository(rootURL: root)
        let meeting = try await repository.saveCapture(try makeCapture())
        let queue = ProcessingQueue(repository: FileProcessingJobRepository(rootURL: root))
        let settings = UserDefaultsAppSettingsRepository(defaults: defaults, storageKey: "preferences")
        let original = WorkerStubTranscriptionService(mode: .success)
        _ = try await queue.enqueue(meetingID: meeting.id)
        let first = TranscriptionProcessingWorker(queue: queue, meetingRepository: repository,
            settingsRepository: settings, transcriptionService: original, summaryService: FailingSummaryService())
        await first.drain()
        let failedSummary = try await repository.loadTranscription(for: meeting.id)
        XCTAssertNotNil(failedSummary?.summaryFailure)
        XCTAssertEqual(failedSummary?.transcript.text, "Merhaba")

        let neverUpload = WorkerStubTranscriptionService(mode: .failure(.authentication))
        _ = try await queue.enqueue(meetingID: meeting.id)
        let second = TranscriptionProcessingWorker(queue: queue, meetingRepository: repository,
            settingsRepository: settings, transcriptionService: neverUpload)
        await second.drain()
        let request = await neverUpload.lastRequest()
        XCTAssertNil(request)
        let recovered = try await repository.loadTranscription(for: meeting.id)
        XCTAssertNil(recovered?.summaryFailure)
        XCTAssertNotNil(recovered?.summary)
        XCTAssertEqual(recovered?.transcript.segments.first?.id, failedSummary?.transcript.segments.first?.id)
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

private struct BlockingWorkerTranscriptionService: TranscriptionServicing {
    let capabilities = TranscriptionServiceCapabilities(
        supportedFileExtensions: ["m4a"],
        maximumFileSizeBytes: 1_000_000,
        supportsDiarization: true,
        supportsAutomaticLanguageDetection: true
    )

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        try await Task.sleep(for: .seconds(30))
        throw TranscriptionServiceError.providerUnavailable
    }
}

private actor RecoveringWorkerTranscriptionService: TranscriptionServicing {
    nonisolated let capabilities = TranscriptionServiceCapabilities(
        supportedFileExtensions: ["m4a"],
        maximumFileSizeBytes: 1_000_000,
        supportsDiarization: true,
        supportsAutomaticLanguageDetection: true
    )
    private var count = 0

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) throws -> TranscriptionResult {
        count += 1
        guard count > 1 else {
            throw TranscriptionServiceError.networkUnavailable
        }
        uploadProgress(1)
        return TranscriptionResult(
            transcript: Transcript(
                text: "Bağlantı geri geldi",
                languageCode: "tr",
                segments: [
                    TranscriptSegment(
                        speakerID: "speaker_0",
                        startTime: 0,
                        endTime: 1,
                        text: "Bağlantı geri geldi"
                    )
                ]
            )
        )
    }

    func requestCount() -> Int { count }
}

private actor WorkerStubTranscriptionService: TranscriptionServicing {
    enum Mode: Sendable {
        case success
        case failure(TranscriptionServiceError)
    }

    nonisolated let capabilities = TranscriptionServiceCapabilities(
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
