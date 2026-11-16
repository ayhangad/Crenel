@preconcurrency import AVFoundation
import Foundation

/// Orchestrates trigger → microphone → on-device transcription → refinement → insertion.
///
/// All dependencies are protocols so the flow is unit-testable with fakes. Audio and
/// transcripts stay in memory; only the last `historyLimit` results are kept, never persisted.
@MainActor
final class DictationController: ObservableObject {
    struct Configuration: Equatable, Sendable {
        /// Holds shorter than this are treated as accidental taps and cancelled silently.
        var minimumHoldDuration: TimeInterval = 0.25
        var maximumSessionDuration: TimeInterval = 5 * 60
        var historyLimit = 20
        /// How long `.inserted` / `.failed` stay visible before returning to `.idle`; nil keeps them.
        var resultDisplayDuration: TimeInterval? = 2.5

        static let `default` = Configuration()
    }

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var partialTranscript = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var history: [DictationHistoryEntry] = []
    @Published private(set) var assetPreparationLocale: String?

    var refiner: any DictationTextRefining
    var onCreateTask: ((String) -> Void)?
    var language: DictationLanguage = .automatic
    var vocabulary: [String] = []
    var microphoneDeviceID: String?

    private let capture: any DictationAudioCapturing
    private let transcriber: any DictationTranscribing
    private let assets: (any DictationSpeechAssetManaging)?
    private let inserter: any DictationTextInserting
    private let triggerMonitor: (any DictationTriggerMonitoring)?
    private let configuration: Configuration
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let preferredLanguages: () -> [String]

    private var session: Session?
    private var resetTask: Task<Void, Never>?
    private var assetTask: Task<Void, Never>?
    /// Serializes use of the shared capture/transcriber across back-to-back sessions.
    private var pipelineBarrier: Task<Void, Never>?

    init(
        capture: any DictationAudioCapturing,
        transcriber: any DictationTranscribing,
        assets: (any DictationSpeechAssetManaging)? = nil,
        inserter: any DictationTextInserting,
        refiner: any DictationTextRefining = PassthroughDictationRefiner(),
        triggerMonitor: (any DictationTriggerMonitoring)? = nil,
        configuration: Configuration = .default,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        },
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        onCreateTask: ((String) -> Void)? = nil
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.assets = assets
        self.inserter = inserter
        self.refiner = refiner
        self.triggerMonitor = triggerMonitor
        self.configuration = configuration
        self.now = now
        self.sleep = sleep
        self.preferredLanguages = preferredLanguages
        self.onCreateTask = onCreateTask

        triggerMonitor?.onEvent = { [weak self] event in
            self?.handleTrigger(event)
        }
    }

    /// Convenience factory wiring the real on-device services.
    static func live(
        refiner: any DictationTextRefining = PassthroughDictationRefiner(),
        triggerSettings: DictationTriggerSettings = .default,
        onCreateTask: ((String) -> Void)? = nil
    ) -> DictationController {
        let transcriber = LocalSpeechTranscriber()
        return DictationController(
            capture: DictationAudioCapture(),
            transcriber: transcriber,
            assets: transcriber,
            inserter: TextInsertionService(),
            refiner: refiner,
            triggerMonitor: DictationHotKeyMonitor(settings: triggerSettings),
            onCreateTask: onCreateTask
        )
    }

    var resolvedLocaleIdentifier: String {
        language.resolvedLocaleIdentifier(preferredLanguages: preferredLanguages())
    }

    // MARK: - Trigger monitoring

    @discardableResult
    func startTriggerMonitoring() -> Bool {
        triggerMonitor?.start() ?? false
    }

    func stopTriggerMonitoring() {
        triggerMonitor?.stop()
    }

    func updateTriggerSettings(_ settings: DictationTriggerSettings) {
        triggerMonitor?.settings = settings
    }

    func handleTrigger(_ event: DictationTriggerEvent) {
        switch event {
        case .began:
            startListening()
        case .ended:
            stopListening()
        case .cancelled:
            cancel()
        }
    }

    // MARK: - Public actions

    func startListening() {
        guard !state.isBusy else { return }
        resetTask?.cancel()

        let localeIdentifier = resolvedLocaleIdentifier
        let target = inserter.currentContext()
        let session = Session(startedAt: now(), localeIdentifier: localeIdentifier, target: target)
        self.session = session
        partialTranscript = ""
        level = 0
        state = .listening(startedAt: session.startedAt, level: 0)

        let barrier = pipelineBarrier
        let startup = Task { [weak self] () -> Bool in
            await barrier?.value
            return await self?.startPipeline(for: session) ?? false
        }
        session.startup = startup
        pipelineBarrier = Task { _ = await startup.value }
        session.timeout = Task { [weak self, sleep, configuration] in
            await sleep(configuration.maximumSessionDuration)
            guard !Task.isCancelled else { return }
            self?.sessionTimedOut(session)
        }
    }

    func stopListening() {
        guard let session, !session.isFinishing, case .listening = state else { return }
        let held = now().timeIntervalSince(session.startedAt)
        guard held >= configuration.minimumHoldDuration else {
            cancel()
            return
        }
        session.isFinishing = true
        session.timeout?.cancel()
        session.finish = Task { [weak self] in
            await self?.finishPipeline(for: session)
        }
    }

    /// Esc, chord or explicit cancel: abandon the session silently without inserting anything.
    func cancel() {
        guard let session else {
            if state.isBusy { state = .idle }
            return
        }
        tearDown(session)
        enqueueTranscriberCancel()
        state = .idle
        partialTranscript = ""
        level = 0
    }

    /// Copies the most recent dictation to the clipboard. Returns false when history is empty.
    @discardableResult
    func copyLastDictation() -> Bool {
        guard let last = history.first else { return false }
        inserter.copyToClipboard(last.finalText)
        return true
    }

    func clearHistory() {
        history.removeAll()
    }

    /// Downloads the on-device speech model for the current language.
    func prepareSpeechAssets() {
        startAssetPreparation(localeIdentifier: resolvedLocaleIdentifier)
    }

    /// Await the in-flight session (startup and finish); intended for tests and integration.
    func waitForCurrentSession() async {
        guard let session else { return }
        _ = await session.startup?.value
        await session.finish?.value
    }

    // MARK: - Pipeline

    private func enqueueTranscriberCancel() {
        let previous = pipelineBarrier
        let transcriber = self.transcriber
        pipelineBarrier = Task {
            await previous?.value
            await transcriber.cancel()
        }
    }

    private func startPipeline(for session: Session) async -> Bool {
        guard isCurrent(session) else { return false }
        do {
            let stream = try await capture.start(deviceID: microphoneDeviceID)
            guard isCurrent(session) else {
                capture.stop()
                return false
            }
            session.levelTask = Task { [weak self] in
                for await value in stream.levels {
                    guard let self, self.isCurrent(session) else { return }
                    self.level = value
                    if case .listening(let startedAt, _) = self.state {
                        self.state = .listening(startedAt: startedAt, level: value)
                    }
                }
            }

            let partials = try await transcriber.start(
                localeIdentifier: session.localeIdentifier,
                vocabulary: vocabulary
            )
            guard isCurrent(session) else {
                capture.stop()
                await transcriber.cancel()
                return false
            }

            let transcriber = self.transcriber
            session.pump = Task.detached {
                for await buffer in stream.buffers {
                    transcriber.feed(buffer)
                }
            }
            session.partialTask = Task { [weak self] in
                for await text in partials {
                    guard let self, self.isCurrent(session) else { return }
                    self.partialTranscript = text
                }
            }
            return true
        } catch {
            guard isCurrent(session) else { return false }
            capture.stop()
            let failure = Self.failure(from: error, fallback: .transcriptionFailed)
            if case .speechAssetsMissing(let localeIdentifier) = failure {
                startAssetPreparation(localeIdentifier: localeIdentifier)
            }
            fail(session, with: failure)
            return false
        }
    }

    private func finishPipeline(for session: Session) async {
        let started = await session.startup?.value ?? false
        guard started, isCurrent(session) else { return }

        state = .transcribing
        level = 0
        capture.stop()
        await session.pump?.value

        let transcript: String
        do {
            transcript = try await transcriber.finish()
        } catch {
            guard isCurrent(session) else { return }
            fail(session, with: Self.failure(from: error, fallback: .transcriptionFailed))
            return
        }
        guard isCurrent(session) else { return }
        session.partialTask?.cancel()
        partialTranscript = transcript

        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.containsSpeech(cleaned) else {
            fail(session, with: .noSpeechDetected)
            return
        }

        state = .refining
        let context = DictationContext(
            appBundleIdentifier: session.target.bundleIdentifier,
            appName: session.target.appName,
            selectedText: session.target.selectedText,
            localeIdentifier: session.localeIdentifier,
            vocabulary: vocabulary
        )
        let outcome = await refiner.refine(transcript: cleaned, context: context)
        guard isCurrent(session) else { return }

        switch outcome {
        case .createTask(let text):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                fail(session, with: .noSpeechDetected)
                return
            }
            onCreateTask?(text)
            record(transcript: cleaned, finalText: text, delivery: .taskCreated, session: session)
            complete(session, summary: DictationResultSummary(
                text: text,
                delivery: .taskCreated,
                appName: session.target.appName
            ))

        case .insert(let text), .replaceSelection(let text):
            let isReplacement: Bool
            if case .replaceSelection = outcome { isReplacement = true } else { isReplacement = false }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(session, with: .noSpeechDetected)
                return
            }
            state = .inserting
            let result = await inserter.insert(text)
            guard isCurrent(session) else { return }
            handleInsertion(result, text: text, transcript: cleaned, isReplacement: isReplacement, session: session)
        }
    }

    private func handleInsertion(
        _ result: TextInsertionResult,
        text: String,
        transcript: String,
        isReplacement: Bool,
        session: Session
    ) {
        switch result {
        case .insertedViaAccessibility, .insertedViaPaste:
            let delivery: DictationDelivery
            if isReplacement {
                delivery = .replacedSelection
            } else {
                delivery = result == .insertedViaAccessibility ? .insertedViaAccessibility : .insertedViaPaste
            }
            record(transcript: transcript, finalText: text, delivery: delivery, session: session)
            complete(session, summary: DictationResultSummary(
                text: text,
                delivery: delivery,
                appName: session.target.appName
            ))
        case .copiedToClipboard(let reason):
            record(transcript: transcript, finalText: text, delivery: nil, session: session)
            switch reason {
            case .noFocusedTextField:
                fail(session, with: .noFocusedTextField)
            case .accessibilityPermissionMissing:
                fail(session, with: .accessibilityPermissionMissing)
            case .pasteFailed:
                fail(session, with: .insertionFailed)
            }
        case .refusedSecureField:
            fail(session, with: .secureTextField)
        }
    }

    // MARK: - Session lifecycle

    private func sessionTimedOut(_ session: Session) {
        guard isCurrent(session), !session.isFinishing else { return }
        triggerMonitor?.sessionEndedExternally()
        session.isFinishing = true
        session.finish = Task { [weak self] in
            await self?.finishPipeline(for: session)
        }
    }

    private func complete(_ session: Session, summary: DictationResultSummary) {
        finalize(session)
        state = .inserted(summary)
        scheduleReset()
    }

    private func fail(_ session: Session, with failure: DictationFailure) {
        let wasListening = state.isListening
        finalize(session)
        if wasListening {
            triggerMonitor?.sessionEndedExternally()
            enqueueTranscriberCancel()
        }
        state = .failed(failure)
        level = 0
        scheduleReset()
    }

    private func finalize(_ session: Session) {
        session.timeout?.cancel()
        session.levelTask?.cancel()
        session.partialTask?.cancel()
        if self.session === session {
            self.session = nil
        }
    }

    private func tearDown(_ session: Session) {
        finalize(session)
        session.startup?.cancel()
        session.finish?.cancel()
        session.pump?.cancel()
        capture.stop()
    }

    private func isCurrent(_ session: Session) -> Bool {
        self.session === session
    }

    private func scheduleReset() {
        resetTask?.cancel()
        guard let duration = configuration.resultDisplayDuration else { return }
        let expected = state
        resetTask = Task { [weak self, sleep] in
            await sleep(duration)
            guard !Task.isCancelled, let self, self.state == expected else { return }
            self.state = .idle
            self.partialTranscript = ""
        }
    }

    private func record(transcript: String, finalText: String, delivery: DictationDelivery?, session: Session) {
        let entry = DictationHistoryEntry(
            id: UUID(),
            createdAt: now(),
            transcript: transcript,
            finalText: finalText,
            delivery: delivery,
            appName: session.target.appName
        )
        history.insert(entry, at: 0)
        if history.count > configuration.historyLimit {
            history.removeLast(history.count - configuration.historyLimit)
        }
    }

    private func startAssetPreparation(localeIdentifier: String) {
        guard let assets, assetTask == nil else { return }
        assetPreparationLocale = localeIdentifier
        assetTask = Task { [weak self] in
            try? await assets.prepareAssets(localeIdentifier: localeIdentifier)
            self?.assetTask = nil
            self?.assetPreparationLocale = nil
        }
    }

    // MARK: - Helpers

    static func containsSpeech(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func failure(from error: Error, fallback: DictationFailure) -> DictationFailure {
        (error as? DictationFailure) ?? fallback
    }

    @MainActor
    private final class Session {
        let startedAt: Date
        let localeIdentifier: String
        let target: DictationTargetSnapshot
        var isFinishing = false
        var startup: Task<Bool, Never>?
        var finish: Task<Void, Never>?
        var timeout: Task<Void, Never>?
        var pump: Task<Void, Never>?
        var levelTask: Task<Void, Never>?
        var partialTask: Task<Void, Never>?

        init(startedAt: Date, localeIdentifier: String, target: DictationTargetSnapshot) {
            self.startedAt = startedAt
            self.localeIdentifier = localeIdentifier
            self.target = target
        }
    }
}
