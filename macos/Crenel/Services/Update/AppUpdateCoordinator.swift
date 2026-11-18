import AppKit
import Foundation

/// Something that finds, downloads and installs app updates, and reports where it is.
/// Sparkle drives it in release builds; Debug builds can use `SimulatedAppUpdater`.
@MainActor
protocol AppUpdater: AnyObject {
    /// Called with every phase change.
    var onPhaseChange: ((AppUpdatePhase) -> Void)? { get set }
    func checkForUpdates()
    /// Quits Crenel and installs the ready update; the updater relaunches it.
    func installAndRelaunch()
}

/// Connects the updater to the notch: phases into AppState, Restart guarded against a
/// running recording, and "Updated" once after launching a new version.
@MainActor
final class AppUpdateCoordinator {
    static let updatedNoticeDuration: TimeInterval = 6
    /// Restarting shows this long before Crenel quits, so the moment is seen.
    static let restartingDelay: TimeInterval = 0.9

    private let appState: AppState
    private var updater: AppUpdater?
    private var clearUpdated: Task<Void, Never>?

    private let waitBeforeRestart: @MainActor () async -> Void

    init(appState: AppState, waitBeforeRestart: @escaping @MainActor () async -> Void = {
        try? await Task.sleep(for: .seconds(AppUpdateCoordinator.restartingDelay))
    }) {
        self.waitBeforeRestart = waitBeforeRestart
        self.appState = appState
    }

    func attach(_ updater: AppUpdater) {
        self.updater = updater
        updater.onPhaseChange = { [weak self] phase in self?.appState.updateUpdatePhase(phase) }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    /// Restart ↩: never during a recording or a dictation.
    @discardableResult
    func restartToUpdate() -> Task<Void, Never>? {
        guard case .ready(let version) = appState.updatePhase, !audioIsBusy else { return nil }
        appState.updateUpdatePhase(.restarting(version))
        return Task { [weak self, waitBeforeRestart] in
            await waitBeforeRestart()
            guard let self, appState.updatePhase == .restarting(version) else { return }
            guard !audioIsBusy else {
                appState.updateUpdatePhase(.ready(version))
                return
            }
            updater?.installAndRelaunch()
        }
    }

    var canRestart: Bool { appState.updatePhase.isReady && !audioIsBusy }

    /// A recording, or a dictation still listening or delivering its text.
    private var audioIsBusy: Bool {
        if appState.dictationState.isBusy { return true }
        switch appState.meetingFlow {
        case .preparingRecording, .recording, .finalizingAudio: return true
        default: return false
        }
    }

    /// On launch: if this is a newer version than last time, say so for a few seconds.
    func announceIfUpdated(releaseNotesURL: URL?) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version = AppLaunchVersion.updatedVersion(current: current, build: build) else { return }
        showUpdated(AppUpdateVersion(shortVersion: version, releaseNotesURL: releaseNotesURL))
    }

    func showUpdated(_ version: AppUpdateVersion) {
        appState.showJustUpdated(version)
        clearUpdated?.cancel()
        clearUpdated = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.updatedNoticeDuration))
            guard !Task.isCancelled else { return }
            self?.appState.showJustUpdated(nil)
        }
    }

    func showReleaseNotes(_ version: AppUpdateVersion) {
        appState.showJustUpdated(nil)
        if let url = version.releaseNotesURL { NSWorkspace.shared.open(url) }
    }
}

#if DEBUG
/// Debug builds only: walks the whole update flow without a feed, so the notch states
/// can be seen live. Post `gad.Crenel.debug.update` (a distributed notification) to
/// start: downloading over ~4 s, preparing, ready. Restart then shows Restarting and,
/// instead of quitting, plays the post-relaunch "Updated" strip.
///
///     swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("gad.Crenel.debug.update"), object: nil, deliverImmediately: true)'
@MainActor
final class SimulatedAppUpdater: AppUpdater {
    var onPhaseChange: ((AppUpdatePhase) -> Void)?
    var onRelaunched: ((AppUpdateVersion) -> Void)?
    private let version = AppUpdateVersion(
        shortVersion: "1.2",
        releaseNotesURL: URL(string: "https://github.com/ayhangad/Crenel/releases"),
        changeCount: 3
    )
    private var run: Task<Void, Never>?

    func checkForUpdates() {
        run?.cancel()
        run = Task { [weak self] in
            guard let self else { return }
            for step in 0...40 {
                guard !Task.isCancelled else { return }
                onPhaseChange?(.downloading(version, progress: Double(step) / 40))
                try? await Task.sleep(for: .milliseconds(100))
            }
            onPhaseChange?(.preparing(version))
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            onPhaseChange?(.ready(version))
        }
    }

    func installAndRelaunch() {
        run?.cancel()
        run = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(1.2))
            onPhaseChange?(.idle)
            onRelaunched?(version)
        }
    }
}
#endif
