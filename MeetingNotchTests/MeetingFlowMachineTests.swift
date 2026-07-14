import XCTest
@testable import MeetingNotch

final class MeetingFlowMachineTests: XCTestCase {
    func testHappyPathReachesCompletedState() throws {
        let meetingID = UUID()
        var machine = MeetingFlowMachine()

        try machine.send(.requestedRecording)
        XCTAssertEqual(machine.state, .preparingRecording)

        let startedAt = Date(timeIntervalSince1970: 1_000)
        try machine.send(.recordingStarted(at: startedAt))
        XCTAssertEqual(machine.state, .recording(startedAt: startedAt))

        try machine.send(.requestedStop)
        XCTAssertEqual(machine.state, .finalizingAudio)

        try machine.send(.audioFinalized)
        XCTAssertEqual(machine.state, .uploading(progress: 0))

        try machine.send(.uploadProgress(0.5))
        XCTAssertEqual(machine.state, .uploading(progress: 0.5))

        try machine.send(.uploadCompleted)
        XCTAssertEqual(machine.state, .transcribing)

        try machine.send(.transcriptionCompleted)
        XCTAssertEqual(machine.state, .summarizing)

        try machine.send(.summaryCompleted(meetingID: meetingID))
        XCTAssertEqual(machine.state, .completed(meetingID: meetingID))
    }

    func testUpcomingMeetingCanStartRecordingFlow() throws {
        let meeting = Meeting(
            title: "Standup",
            startDate: Date(),
            endDate: Date().addingTimeInterval(30 * 60)
        )
        var machine = MeetingFlowMachine()

        try machine.send(.detectedUpcomingMeeting(meeting))
        XCTAssertEqual(machine.state, .upcomingMeeting(meeting))

        try machine.send(.requestedRecording)
        XCTAssertEqual(machine.state, .preparingRecording)
    }

    func testInvalidTransitionDoesNotChangeState() {
        var machine = MeetingFlowMachine()

        XCTAssertThrowsError(try machine.send(.requestedStop)) { error in
            XCTAssertEqual(
                error as? InvalidMeetingFlowTransition,
                InvalidMeetingFlowTransition(phase: .idle, eventName: "requestedStop")
            )
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testUploadProgressIsClamped() throws {
        var machine = MeetingFlowMachine(initialState: .uploading(progress: 0))

        try machine.send(.uploadProgress(1.4))
        XCTAssertEqual(machine.state, .uploading(progress: 1))

        try machine.send(.uploadProgress(-0.2))
        XCTAssertEqual(machine.state, .uploading(progress: 0))
    }

    func testRetryableFailureReturnsToPreviousState() throws {
        var machine = MeetingFlowMachine(initialState: .transcribing)
        let failure = AppFailure.network("Bağlantı kesildi.")

        try machine.send(.fail(failure))
        XCTAssertEqual(machine.state, .failed(failure))

        try machine.send(.retry)
        XCTAssertEqual(machine.state, .transcribing)
    }

    func testPermanentFailureCannotRetry() throws {
        var machine = MeetingFlowMachine(initialState: .preparingRecording)
        let failure = AppFailure.permission("Mikrofon izni reddedildi.", settings: true)

        try machine.send(.fail(failure))

        XCTAssertThrowsError(try machine.send(.retry))
        XCTAssertEqual(machine.state, .failed(failure))
    }

    func testActiveFlowCanBeCancelledAndReset() throws {
        var machine = MeetingFlowMachine(initialState: .recording(startedAt: Date()))

        try machine.send(.cancel)
        XCTAssertEqual(machine.state, .cancelled)

        try machine.send(.reset)
        XCTAssertEqual(machine.state, .idle)
    }
}
