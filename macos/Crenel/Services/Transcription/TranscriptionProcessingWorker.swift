import Foundation

enum TranscriptionProcessingEvent: Sendable {
    case started(ProcessingJob)
    case uploadProgress(meetingID: UUID, progress: Double)
    case transcribing(meetingID: UUID)
    case summarizing(meetingID: UUID)
    /// `actionItemCount` is nil when no notes were written.
    case completed(StoredMeeting, actionItemCount: Int?)
    case failed(ProcessingJob, TranscriptionServiceError)
}

actor TranscriptionProcessingWorker {
    typealias EventHandler = @Sendable (TranscriptionProcessingEvent) async -> Void

    private let queue: ProcessingQueue
    private let meetingRepository: any MeetingRepository
    private let settingsRepository: any AppSettingsRepository
    private let transcriptionService: any TranscriptionServicing
    private let summaryService: any MeetingSummaryGenerating
    private let retryPolicy: TranscriptionRetryPolicy
    private let onEvent: EventHandler
    private var isDraining = false

    init(
        queue: ProcessingQueue,
        meetingRepository: any MeetingRepository,
        settingsRepository: any AppSettingsRepository,
        transcriptionService: any TranscriptionServicing = ElevenLabsTranscriptionService(),
        summaryService: any MeetingSummaryGenerating = ExtractiveMeetingSummaryService(),
        retryPolicy: TranscriptionRetryPolicy = TranscriptionRetryPolicy(),
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.queue = queue
        self.meetingRepository = meetingRepository
        self.settingsRepository = settingsRepository
        self.transcriptionService = transcriptionService
        self.summaryService = summaryService
        self.retryPolicy = retryPolicy
        self.onEvent = onEvent
    }

    func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while !Task.isCancelled {
            let job: ProcessingJob
            do {
                guard let claimed = try await queue.claimNext() else { return }
                job = claimed
            } catch {
                return
            }

            await onEvent(.started(job))
            do {
                guard let meeting = try await meetingRepository.load(id: job.meetingID) else {
                    throw TranscriptionServiceError.invalidFile(.missing)
                }
                let existing = try await meetingRepository.loadTranscription(for: meeting.id)
                let result: TranscriptionResult
                if let existing {
                    result = TranscriptionResult(transcript: existing.transcript)
                } else {
                    let preferences = (try? await settingsRepository.load()) ?? .default
                    let audioURL = await meetingRepository.audioFileURL(for: meeting)
                    let request = TranscriptionRequest(audioFileURL: audioURL,
                        languageCode: preferences.transcription.languageCode,
                        requestsDiarization: true, idempotencyKey: job.idempotencyKey)
                    let eventHandler = onEvent
                    result = try await retryPolicy.execute { _ in
                        try await transcriptionService.transcribe(request) { progress in
                            Task { await eventHandler(.uploadProgress(meetingID: job.meetingID, progress: progress)) }
                        }
                    }
                    try Task.checkCancellation()
                    // Durable checkpoint before any second provider request.
                    _ = try await meetingRepository.saveTranscription(result, summary: nil, for: meeting)
                }
                await onEvent(.transcribing(meetingID: job.meetingID))
                await onEvent(.summarizing(meetingID: job.meetingID))
                var stored: StoredTranscription
                do {
                    let summary = try await summaryService.generate(from: result.transcript, meeting: meeting)
                    stored = StoredTranscription(transcript: result.transcript, summary: summary)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    stored = StoredTranscription(transcript: result.transcript, summary: existing?.summary)
                    stored.summaryFailure = (error as? MeetingAnalysisError)?.errorDescription
                        ?? "Couldn’t create the summary. The transcript was kept, so you can try the summary again."
                }
                try Task.checkCancellation()
                let updatedMeeting = try await meetingRepository.saveAnalysis(stored, for: meeting)
                try await queue.complete(meetingID: job.meetingID)
                await onEvent(.completed(updatedMeeting, actionItemCount: stored.summary?.actionItems.count))
            } catch is CancellationError {
                if let failedJob = try? await queue.markFailed(
                    meetingID: job.meetingID,
                    error: .cancelled
                ) {
                    await onEvent(.failed(failedJob, .cancelled))
                }
                return
            } catch {
                let normalized = TranscriptionErrorNormalizer.normalize(error)
                do {
                    if let failedJob = try await queue.markFailed(
                        meetingID: job.meetingID,
                        error: normalized
                    ) {
                        await onEvent(.failed(failedJob, normalized))
                    }
                } catch {
                    return
                }
            }
        }
    }
}
