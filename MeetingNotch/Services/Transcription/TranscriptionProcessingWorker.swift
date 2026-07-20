import Foundation

protocol TranscriptionProviderResolving: Sendable {
    func provider(for id: TranscriptionProviderID) -> (any TranscriptionProvider)?
}

struct DefaultTranscriptionProviderResolver: TranscriptionProviderResolving, Sendable {
    private let elevenLabs: any TranscriptionProvider

    init(elevenLabs: any TranscriptionProvider = ElevenLabsTranscriptionProvider()) {
        self.elevenLabs = elevenLabs
    }

    func provider(for id: TranscriptionProviderID) -> (any TranscriptionProvider)? {
        switch id {
        case .elevenLabs:
            elevenLabs
        case .openAI:
            nil
        }
    }
}

enum TranscriptionProcessingEvent: Sendable {
    case started(ProcessingJob)
    case uploadProgress(meetingID: UUID, progress: Double)
    case transcribing(meetingID: UUID)
    case summarizing(meetingID: UUID)
    case completed(StoredMeeting)
    case failed(ProcessingJob, TranscriptionServiceError)
}

actor TranscriptionProcessingWorker {
    typealias EventHandler = @Sendable (TranscriptionProcessingEvent) async -> Void

    private let queue: ProcessingQueue
    private let meetingRepository: any MeetingRepository
    private let settingsRepository: any AppSettingsRepository
    private let providers: any TranscriptionProviderResolving
    private let summaryService: any MeetingSummaryGenerating
    private let retryPolicy: TranscriptionRetryPolicy
    private let onEvent: EventHandler
    private var isDraining = false

    init(
        queue: ProcessingQueue,
        meetingRepository: any MeetingRepository,
        settingsRepository: any AppSettingsRepository,
        providers: any TranscriptionProviderResolving = DefaultTranscriptionProviderResolver(),
        summaryService: any MeetingSummaryGenerating = ExtractiveMeetingSummaryService(),
        retryPolicy: TranscriptionRetryPolicy = TranscriptionRetryPolicy(),
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.queue = queue
        self.meetingRepository = meetingRepository
        self.settingsRepository = settingsRepository
        self.providers = providers
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
                guard let provider = providers.provider(for: job.providerID) else {
                    throw TranscriptionServiceError.providerUnavailable
                }
                guard let meeting = try await meetingRepository.loadAll()
                    .first(where: { $0.id == job.meetingID }) else {
                    throw TranscriptionServiceError.invalidFile(.missing)
                }
                let preferences = (try? await settingsRepository.load()) ?? .default
                let audioURL = await meetingRepository.audioFileURL(for: meeting)
                let request = TranscriptionRequest(
                    audioFileURL: audioURL,
                    languageCode: preferences.provider.languageCode,
                    requestsDiarization: true,
                    idempotencyKey: job.idempotencyKey
                )
                let eventHandler = onEvent
                let result = try await retryPolicy.execute { _ in
                    try await provider.transcribe(request) { progress in
                        Task {
                            await eventHandler(.uploadProgress(
                                meetingID: job.meetingID,
                                progress: progress
                            ))
                        }
                    }
                }
                try Task.checkCancellation()
                await onEvent(.transcribing(meetingID: job.meetingID))
                await onEvent(.summarizing(meetingID: job.meetingID))
                let summary: MeetingSummary?
                do {
                    summary = try await summaryService.generate(from: result.transcript)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Transcription is the durable primary result. Notes are optional and must
                    // never turn a successful speech-to-text operation into a failed meeting.
                    summary = nil
                }
                let updatedMeeting = try await meetingRepository.saveTranscription(
                    result,
                    summary: summary,
                    for: meeting
                )
                try await queue.complete(meetingID: job.meetingID)
                await onEvent(.completed(updatedMeeting))
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
