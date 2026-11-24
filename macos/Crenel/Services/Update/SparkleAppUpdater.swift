import Foundation
import Sparkle

/// Sparkle with Crenel's own UI: a `SPUUserDriver` that turns Sparkle's callbacks into
/// `AppUpdatePhase`s for the notch instead of showing Sparkle's windows.
///
/// A found update downloads at once (the notch shows the progress quietly), is verified
/// and unpacked, then waits for Restart. Sparkle only quits Crenel when Restart answers
/// its "ready to install" question, which `AppUpdateCoordinator` never does during a
/// recording. If Crenel quits on its own first, Sparkle installs the update then.
@MainActor
final class SparkleAppUpdater: NSObject, AppUpdater, SPUUserDriver {
    var onPhaseChange: ((AppUpdatePhase) -> Void)?
    /// A user-started check: checking, nothing new, or an error.
    var onCheckChange: ((AppUpdateCheck) -> Void)?
    private var userCheckRunning = false

    private var updater: SPUUpdater?
    private var version: AppUpdateVersion?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0
    /// Sparkle's question "install and relaunch now?", answered by Restart.
    private var installReply: ((SPUUserUpdateChoice) -> Void)?

    /// Starts the updater: scheduled checks follow `SUEnableAutomaticChecks` (daily).
    func start() throws {
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        try updater.start()
        self.updater = updater
    }

    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else {
            onCheckChange?(.idle)
            return
        }
        userCheckRunning = true
        onCheckChange?(.checking)
        updater.checkForUpdates()
    }

    func installAndRelaunch() {
        guard let reply = installReply else { return }
        installReply = nil
        reply(.install)
    }

    private func publish(_ phase: AppUpdatePhase) {
        onPhaseChange?(phase)
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Checking is the point of a notch app that is rarely quit; no system profile.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userCheckRunning = true
        onCheckChange?(.checking)
    }

    private func endUserCheck(_ result: AppUpdateCheck) {
        guard userCheckRunning else { return }
        userCheckRunning = false
        onCheckChange?(result)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !appcastItem.isInformationOnlyUpdate else {
            endUserCheck(.upToDate)
            reply(.dismiss)
            return
        }
        // The download progress takes over from "Checking".
        endUserCheck(.idle)
        let found = AppUpdateVersion(
            shortVersion: appcastItem.displayVersionString,
            releaseNotesURL: CrenelReleaseNotes.url(for: appcastItem.displayVersionString)
        )
        version = found
        switch state.stage {
        case .installing:
            // Already unpacked and waiting: the next "install" quits and relaunches.
            installReply = reply
            publish(.ready(found))
        case .notDownloaded, .downloaded:
            publish(.downloading(found, progress: 0))
            reply(.install)
        @unknown default:
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        endUserCheck(.upToDate)
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        AppLogger.updateFailed(error)
        endUserCheck(.failed)
        version = nil
        installReply = nil
        publish(.idle)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        guard let version, expectedLength > 0 else { return }
        publish(.downloading(version, progress: min(1, Double(receivedLength) / Double(expectedLength))))
    }

    func showDownloadDidStartExtractingUpdate() {
        if let version { publish(.preparing(version)) }
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        if let version { publish(.ready(version)) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if let version { publish(.restarting(version)) }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        // Sparkle ends the session (an error, or an update that went away). An update
        // that is still waiting for Restart keeps its reply and stays ready.
        if installReply == nil {
            version = nil
            publish(.idle)
        }
    }
}
