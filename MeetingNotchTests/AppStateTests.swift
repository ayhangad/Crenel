import XCTest
@testable import MeetingNotch

@MainActor
final class AppStateTests: XCTestCase {
    func testAudioCapturePermissionsAreUpdatedForTheUI() {
        let state = AppState()
        let permissions = AudioCapturePermissionSnapshot(
            microphone: .authorized,
            systemAudio: .denied
        )

        state.updateAudioCapturePermissions(permissions)

        XCTAssertEqual(state.audioCapturePermissions, permissions)
    }

    func testNotchPinCanBeToggled() {
        let state = AppState()

        XCTAssertTrue(state.toggleNotchPin())
        XCTAssertTrue(state.isNotchPinned)
        XCTAssertFalse(state.toggleNotchPin())
        XCTAssertFalse(state.isNotchPinned)
    }

    func testRecordingPreparationStartsOnlyFromIdle() {
        let state = AppState()

        state.prepareForRecording()
        XCTAssertEqual(state.meetingFlow, .preparingRecording)

        state.prepareForRecording()
        XCTAssertEqual(state.meetingFlow, .preparingRecording)
    }

    func testCancellationAndResetReturnToIdle() {
        let state = AppState()
        state.prepareForRecording()

        state.cancelCurrentFlow()
        XCTAssertEqual(state.meetingFlow, .cancelled)

        state.resetFlow()
        XCTAssertEqual(state.meetingFlow, .idle)
    }

    func testFailureIsExposedForTheUI() {
        let state = AppState()
        let failure = AppFailure.network("İnternet bağlantınızı kontrol edin.")
        state.prepareForRecording()

        XCTAssertTrue(state.send(.fail(failure)))
        XCTAssertEqual(state.userFacingFailure, failure)
        XCTAssertEqual(state.meetingFlow, .failed(failure))
    }

    func testActiveFlowRequiresTerminationConfirmation() {
        let state = AppState()
        XCTAssertFalse(state.requiresTerminationConfirmation)

        state.prepareForRecording()
        XCTAssertTrue(state.requiresTerminationConfirmation)
    }

    func testMeetingReminderBecomesPrimaryFlowAndCanBeDismissed() {
        let state = AppState()
        let meeting = Meeting(
            title: "Daily",
            startDate: Date().addingTimeInterval(60),
            endDate: Date().addingTimeInterval(1_860),
            externalIdentifier: "daily"
        )
        let snapshot = MeetingReminderSnapshot(
            nextMeeting: meeting,
            level: .oneMinute,
            secondsUntilStart: 60
        )

        XCTAssertTrue(state.applyMeetingSnapshot(snapshot, shouldPresent: true))
        XCTAssertEqual(state.meetingFlow, .upcomingMeeting(meeting))

        state.dismissCurrentMeetingReminder()
        XCTAssertEqual(state.meetingFlow, .idle)
        XCTAssertFalse(state.applyMeetingSnapshot(snapshot, shouldPresent: true))
        XCTAssertEqual(state.meetingFlow, .idle)
    }

    func testCalendarWithoutReminderKeepsManualRecordingAvailable() {
        let state = AppState()
        state.updateCalendarAccessState(.denied)

        state.prepareForRecording()

        XCTAssertEqual(state.calendarAccessState, .denied)
        XCTAssertEqual(state.meetingFlow, .preparingRecording)
    }

    func testLocallySavedRecordingCompletesFlow() {
        let state = AppState()
        let session = RecordingSession(startedAt: .now)
        let result = RecordingCaptureResult(session: session, tracks: [])

        state.prepareForRecording()
        state.recordingStarted(session)
        state.stopRecording()
        state.recordingSaved(result)

        XCTAssertEqual(state.meetingFlow, .completed(meetingID: session.id))
        XCTAssertEqual(state.lastRecordingResult, result)
    }
}
