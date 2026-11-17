import XCTest
@testable import Crenel

final class MeetingSessionMachineTests: XCTestCase {
    func testCalendarContextAloneIsOnlyScheduledContext() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        var machine = MeetingSessionMachine()

        machine.observe(
            .calendarContext(meetingID: "calendar-1", isWithinScheduledWindow: true),
            at: observedAt
        )

        XCTAssertEqual(machine.session.state, .scheduled)
        XCTAssertEqual(machine.session.confidence, .unknown)
        XCTAssertEqual(machine.session.calendarMeetingID, "calendar-1")
        XCTAssertEqual(machine.session.lastChangedAt, observedAt)
    }

    func testProcessAudioWithoutClientUIIsOnlyProbable() {
        var machine = MeetingSessionMachine()

        machine.observe(.process(processID: 42, isRunning: true))
        machine.observe(
            .audioIO(processID: 42, isRunningInput: true, isRunningOutput: true)
        )

        XCTAssertEqual(machine.session.state, .candidate)
        XCTAssertEqual(machine.session.confidence, .probable)
        XCTAssertEqual(machine.session.processID, 42)
    }

    func testProcessAndMeetingControlsConfirmReadySession() {
        var machine = MeetingSessionMachine()

        machine.observe(.process(processID: 84, isRunning: true))
        machine.observe(
            .clientUI(
                clientID: .zoom,
                meetingWindowPresent: true,
                callControlsPresent: true
            )
        )

        XCTAssertEqual(machine.session.state, .ready)
        XCTAssertEqual(machine.session.confidence, .confirmed)
        XCTAssertEqual(machine.session.clientID, .zoom)
    }

    func testSilenceAloneNeverEndsRecording() {
        var machine = confirmedZoomRecording()

        machine.observe(
            .audioIO(processID: 84, isRunningInput: false, isRunningOutput: false)
        )

        XCTAssertEqual(machine.session.state, .recording)
        XCTAssertEqual(machine.session.confidence, .confirmed)
    }

    func testMissingUIAndStoppedAudioProduceProbableEnd() {
        var machine = confirmedZoomRecording()

        machine.observe(
            .audioIO(processID: 84, isRunningInput: false, isRunningOutput: false)
        )
        machine.observe(
            .clientUI(
                clientID: .zoom,
                meetingWindowPresent: false,
                callControlsPresent: false
            )
        )

        XCTAssertEqual(machine.session.state, .endSuspected)
        XCTAssertEqual(machine.session.confidence, .probable)
    }

    func testUIAudioAndProcessStopConfirmEnd() {
        var machine = confirmedZoomRecording()

        machine.observe(
            .audioIO(processID: 84, isRunningInput: false, isRunningOutput: false)
        )
        machine.observe(
            .clientUI(
                clientID: .zoom,
                meetingWindowPresent: false,
                callControlsPresent: false
            )
        )
        machine.observe(.process(processID: 84, isRunning: false))

        XCTAssertEqual(machine.session.state, .ended)
        XCTAssertEqual(machine.session.confidence, .confirmed)
    }

    func testCalendarEndCanCorroborateUIAndAudioWithoutProcessExit() {
        var machine = confirmedZoomRecording()
        machine.observe(
            .calendarContext(meetingID: "calendar-1", isWithinScheduledWindow: true)
        )

        machine.observe(
            .audioIO(processID: 84, isRunningInput: false, isRunningOutput: false)
        )
        machine.observe(
            .clientUI(
                clientID: .zoom,
                meetingWindowPresent: false,
                callControlsPresent: false
            )
        )
        machine.observe(
            .calendarContext(meetingID: "calendar-1", isWithinScheduledWindow: false)
        )

        XCTAssertEqual(machine.session.state, .ended)
        XCTAssertEqual(machine.session.confidence, .confirmed)
    }

    func testManualRecordingAndStopAreExplicitConfirmedSignals() {
        var machine = MeetingSessionMachine()

        machine.recordingStarted()
        XCTAssertEqual(machine.session.state, .recording)
        XCTAssertEqual(machine.session.confidence, .confirmed)

        machine.recordingStopped()
        XCTAssertEqual(machine.session.state, .ended)
        XCTAssertEqual(machine.session.confidence, .confirmed)
    }

    func testEndedSessionIsTerminalAndRoundTripsThroughJSON() throws {
        var machine = confirmedZoomRecording()
        machine.recordingStopped(at: Date(timeIntervalSince1970: 2_000))
        let ended = machine.session

        machine.observe(.process(processID: 84, isRunning: true))

        XCTAssertEqual(machine.session, ended)
        let data = try JSONEncoder().encode(ended)
        XCTAssertEqual(
            try JSONDecoder().decode(MeetingSession.self, from: data),
            ended
        )
    }

    private func confirmedZoomRecording() -> MeetingSessionMachine {
        var machine = MeetingSessionMachine()
        machine.observe(.process(processID: 84, isRunning: true))
        machine.observe(
            .audioIO(processID: 84, isRunningInput: true, isRunningOutput: true)
        )
        machine.observe(
            .clientUI(
                clientID: .zoom,
                meetingWindowPresent: true,
                callControlsPresent: true
            )
        )
        machine.recordingStarted()
        return machine
    }
}
