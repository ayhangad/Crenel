import Combine
import Foundation

/// Connects the dictation engine to preferences, the agent, tasks and AppState.
@MainActor
final class DictationCoordinator {
    let controller: DictationController
    private let appState: AppState
    private let taskCoordinator: TaskCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var isEnabled = false
    private var inputMonitoringRecheck: Task<Void, Never>?
    private let fnKeyGuard: FnKeySystemActionGuard
    /// Called when the microphone starts or stops listening for dictation.
    var onListeningChange: ((Bool) -> Void)?

    init(
        appState: AppState,
        taskCoordinator: TaskCoordinator,
        controller: DictationController? = nil,
        fnKeyGuard: FnKeySystemActionGuard? = nil
    ) {
        self.appState = appState
        self.fnKeyGuard = fnKeyGuard ?? FnKeySystemActionGuard()
        self.taskCoordinator = taskCoordinator
        self.controller = controller ?? DictationController.live()
        self.controller.onCreateTask = { [weak taskCoordinator] text in
            taskCoordinator?.add(Self.taskParseResult(from: text))
        }
        mirrorStateIntoAppState()
    }

    /// Applies dictation and agent preferences; safe to call repeatedly.
    func apply(_ preferences: CrenelPreferences, microphoneID: String?) {
        controller.language = preferences.dictationLanguage
        controller.vocabulary = preferences.dictationVocabulary
        controller.microphoneDeviceID = microphoneID
        controller.refiner = DictationRefiner(preferences: preferences.agent)
        controller.updateTriggerSettings(preferences.dictationTrigger)

        isEnabled = preferences.dictationEnabled
        appState.updateDictationKeyHint(isEnabled ? preferences.dictationTrigger.trigger.keyHint : nil)
        fnKeyGuard.update(dictationEnabled: isEnabled, trigger: preferences.dictationTrigger.trigger)
        if isEnabled {
            startTriggerMonitoring()
        } else {
            controller.stopTriggerMonitoring()
            appState.updateDictationAvailability(.disabled)
        }
    }

    func requestInputMonitoringAccess() {
        _ = DictationHotKeyMonitor.requestInputMonitoringAccess()
        // The grant arrives asynchronously via System Settings; poll briefly.
        inputMonitoringRecheck?.cancel()
        inputMonitoringRecheck = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if DictationHotKeyMonitor.hasInputMonitoringAccess() {
                    self.startTriggerMonitoring()
                    return
                }
            }
        }
    }

    func toggleHandsFree() {
        if controller.state.isListening {
            controller.stopListening()
        } else {
            controller.startListening()
        }
    }

    func cancel() {
        controller.cancel()
    }

    func copyLastDictation() {
        controller.copyLastDictation()
    }

    func prepareSpeechAssets() {
        controller.prepareSpeechAssets()
    }

    private func startTriggerMonitoring() {
        guard isEnabled else { return }
        guard DictationHotKeyMonitor.hasInputMonitoringAccess() else {
            appState.updateDictationAvailability(.needsInputMonitoring)
            return
        }
        let started = controller.startTriggerMonitoring()
        appState.updateDictationAvailability(started ? .ready : .needsInputMonitoring)
    }

    private func mirrorStateIntoAppState() {
        controller.$state
            .removeDuplicates()
            .sink { [weak self] state in self?.appState.updateDictationState(state) }
            .store(in: &cancellables)
        controller.$state
            .map(\.isListening)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] listening in self?.onListeningChange?(listening) }
            .store(in: &cancellables)
        controller.$level
            .throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] level in self?.appState.updateDictationLevel(level) }
            .store(in: &cancellables)
        controller.$partialTranscript
            .removeDuplicates()
            .sink { [weak self] text in self?.appState.updateDictationPartialTranscript(text) }
            .store(in: &cancellables)
        controller.$history
            .sink { [weak self] history in self?.appState.updateDictationHistory(history) }
            .store(in: &cancellables)
    }

    /// Parses spoken input in Turkish or English, e.g. "görev ekle yarın faturayı öde"
    /// ("add task tomorrow pay the bill") → title "faturayı öde", due tomorrow.
    nonisolated static func taskParseResult(from text: String, now: Date = Date()) -> TaskInputParseResult {
        let parser = TaskInputParser()
        let suggestions = parser.suggestions(for: text, now: now)
        return parser.apply(suggestions, to: text)
    }
}

enum DictationAvailability: Equatable, Sendable {
    case disabled
    case needsInputMonitoring
    case ready
}
