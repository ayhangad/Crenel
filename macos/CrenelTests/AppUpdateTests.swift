import XCTest
@testable import Crenel

@MainActor
final class AppUpdateTests: XCTestCase {
    private let version = AppUpdateVersion(shortVersion: "1.2", releaseNotesURL: nil, changeCount: 2)
    private let recording = NotchCompactStatus.RecordingStatus(startedAt: Date(), clientID: .zoom, microphoneState: .open)

    private func state(_ status: NotchCompactStatus, _ update: AppUpdatePhase,
                       notices: AppUpdateNotices = AppUpdateNotices(), justUpdated: AppUpdateVersion? = nil) -> NotchClosedState {
        NotchClosedResolver.state(NotchClosedInput(status: status, update: update, updateNotices: notices, justUpdatedTo: justUpdated))
    }

    func testDownloadingIsQuietAndNeverHidesAMeetingOrTasks() {
        XCTAssertEqual(state(.idle, .downloading(version, progress: 0.3)), .updating(progress: 0.3))
        XCTAssertEqual(state(.idle, .preparing(version)), .updating(progress: nil))
        XCTAssertEqual(state(.tasks(count: 4), .downloading(version, progress: 0.3)), .updating(progress: 0.3))
        let meeting = Meeting(title: "Sync", startDate: Date().addingTimeInterval(600), endDate: Date().addingTimeInterval(2_400))
        let agenda = NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: 600))
        XCTAssertEqual(state(.agenda(agenda), .downloading(version, progress: 0.3)), .meeting(agenda))
    }

    func testReadyShowsTheStripUntilLaterThenAQuietMark() {
        XCTAssertEqual(state(.idle, .ready(version)), .updateReady(version))
        var notices = AppUpdateNotices()
        notices.laterVersion = "1.2"
        XCTAssertEqual(state(.idle, .ready(version), notices: notices), .updatePending(version))
        XCTAssertEqual(state(.tasks(count: 2), .ready(version), notices: notices), .updatePending(version))
        // A newer version than the one put off asks again.
        let next = AppUpdateVersion(shortVersion: "1.3")
        XCTAssertEqual(state(.idle, .ready(next), notices: notices), .updateReady(next))
    }

    func testARecordingWaitsAndSaysSoOnce() {
        XCTAssertEqual(state(.recording(recording), .ready(version)), .recording(recording, prompt: .updateWaiting))
        var notices = AppUpdateNotices()
        notices.duringRecordingVersion = "1.2"
        XCTAssertEqual(state(.recording(recording), .ready(version), notices: notices), .recording(recording, prompt: nil))
        // After the call the ready strip still comes: OK was about the call, not the update.
        XCTAssertEqual(state(.idle, .ready(version), notices: notices), .updateReady(version))
    }

    func testRestartingAndUpdatedWin() {
        XCTAssertEqual(state(.tasks(count: 3), .restarting(version)), .restarting)
        XCTAssertEqual(state(.tasks(count: 3), .idle, justUpdated: version), .updated(version))
        XCTAssertTrue(NotchClosedState.updated(version).isStrip)
        XCTAssertTrue(NotchClosedState.updateReady(version).isStrip)
        XCTAssertFalse(NotchClosedState.updating(progress: 0.5).isStrip)
    }

    func testLaunchVersionReportsOnlyANewerVersionOnce() throws {
        let suite = "AppUpdateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(AppLaunchVersion.updatedVersion(current: "1.1", defaults: defaults), "first launch is not an update")
        XCTAssertEqual(AppLaunchVersion.updatedVersion(current: "1.10", defaults: defaults), "1.10")
        XCTAssertNil(AppLaunchVersion.updatedVersion(current: "1.10", defaults: defaults))
        XCTAssertNil(AppLaunchVersion.updatedVersion(current: "1.9", defaults: defaults), "a downgrade is not an update")
    }

    func testRestartIsRefusedDuringARecording() {
        let appState = AppState(initialFlow: .recording(startedAt: Date()))
        let coordinator = AppUpdateCoordinator(appState: appState)
        appState.updateUpdatePhase(.ready(version))
        coordinator.restartToUpdate()
        XCTAssertEqual(appState.updatePhase, .ready(version))
        XCTAssertFalse(coordinator.canRestart)
    }
}
