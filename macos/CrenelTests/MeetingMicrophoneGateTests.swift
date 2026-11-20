import XCTest
@testable import Crenel

final class MeetingMicrophoneGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testEveryRecordingStartsOpenWithTimestampedEvent() {
        let gate = MeetingMicrophoneGate(recordingStartedAt: start)

        XCTAssertEqual(gate.state, .open)
        XCTAssertTrue(gate.permitsAudio)
        XCTAssertEqual(
            gate.events,
            [
                MeetingMicrophoneGateEvent(
                    timestamp: start,
                    state: .open,
                    source: .recordingStarted,
                    confidence: .confirmed
                )
            ]
        )
    }

    func testStartingWhileDictationIsHeldRecordsTheClosedState() {
        let gate = MeetingMicrophoneGate(recordingStartedAt: start, dictationHeld: true)

        XCTAssertFalse(gate.permitsAudio)
        XCTAssertEqual(gate.events.first?.state, .closed)
    }

    func testOnlyConfirmedClientOpenSignalReopensAfterMute() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.observeClientState(.closed, confidence: .confirmed, at: start.addingTimeInterval(1))
        XCTAssertFalse(gate.permitsAudio)

        XCTAssertNil(gate.observeClientState(.open, confidence: .probable, at: start.addingTimeInterval(2)))
        XCTAssertEqual(gate.state, .closed)

        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(3))
        XCTAssertEqual(gate.state, .open)
        XCTAssertTrue(gate.permitsAudio)
    }

    func testUnknownClientStateKeepsTheMicrophoneAsItIs() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        XCTAssertNil(gate.observeClientState(.unknown, confidence: .unknown, at: start.addingTimeInterval(1)))
        XCTAssertTrue(gate.permitsAudio)

        gate.observeClientState(.closed, confidence: .probable, at: start.addingTimeInterval(2))
        XCTAssertFalse(gate.permitsAudio, "A mute in the call app closes the microphone")
        XCTAssertEqual(gate.state, .closed)
    }

    func testManualMuteDuringDictationSurvivesRelease() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.setDictationHeld(true, at: start.addingTimeInterval(2))
        XCTAssertFalse(gate.permitsAudio)
        gate.setManualState(gate.nextManualState, at: start.addingTimeInterval(3))
        gate.setDictationHeld(false, at: start.addingTimeInterval(4))
        XCTAssertEqual(gate.state, .closed)
        XCTAssertEqual(gate.nextManualState, .open)
    }

    func testVisibleManualControlCanOpenAndCloseGate() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        let closed = gate.setManualState(.closed, at: start.addingTimeInterval(1))
        let opened = gate.setManualState(.open, at: start.addingTimeInterval(2))

        XCTAssertEqual(closed?.source, .manualControl)
        XCTAssertEqual(closed?.confidence, .confirmed)
        XCTAssertEqual(closed?.state, .closed)
        XCTAssertEqual(opened?.state, .open)
        XCTAssertTrue(gate.permitsAudio)
    }

    func testManualUnknownRequestIsNormalizedToClosed() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        let event = gate.setManualState(.unknown, at: start.addingTimeInterval(2))

        XCTAssertEqual(event?.state, .closed)
        XCTAssertFalse(gate.permitsAudio)
    }

    func testAdapterLossAndProcessChangeKeepTheUsersChoice() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        XCTAssertNil(gate.adapterBecameUnavailable(at: start.addingTimeInterval(1)))
        XCTAssertNil(gate.meetingProcessChanged(at: start.addingTimeInterval(2)))
        XCTAssertTrue(gate.permitsAudio)

        gate.setManualState(.closed, at: start.addingTimeInterval(3))
        XCTAssertNil(gate.adapterBecameUnavailable(at: start.addingTimeInterval(4)))
        XCTAssertFalse(gate.permitsAudio)
    }

    func testSystemInterruptionImmediatelyFailsClosedAndIsPersistable() throws {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        let event = gate.systemWasInterrupted(at: start.addingTimeInterval(2))

        XCTAssertEqual(event?.source, .systemInterruption)
        XCTAssertEqual(event?.state, .unknown)
        XCTAssertFalse(gate.permitsAudio)
        let data = try JSONEncoder().encode(gate.events)
        XCTAssertEqual(
            try JSONDecoder().decode([MeetingMicrophoneGateEvent].self, from: data),
            gate.events
        )
    }

    func testDuplicateAndOutOfOrderObservationsDoNotCreateEvents() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        XCTAssertNil(
            gate.observeClientState(
                .open,
                confidence: .confirmed,
                at: start.addingTimeInterval(1)
            )
        )
        gate.observeClientState(.closed, confidence: .confirmed, at: start.addingTimeInterval(2))
        XCTAssertNil(
            gate.observeClientState(
                .open,
                confidence: .confirmed,
                at: start.addingTimeInterval(1)
            )
        )
        XCTAssertEqual(gate.state, .closed)
        XCTAssertEqual(gate.events.count, 2)
    }

    func testGateEventsRoundTripWithoutRawUIContent() throws {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.observeClientState(.closed, confidence: .confirmed, at: start.addingTimeInterval(1))

        let data = try JSONEncoder().encode(gate.events)
        let decoded = try JSONDecoder().decode([MeetingMicrophoneGateEvent].self, from: data)

        XCTAssertEqual(decoded, gate.events)
    }
}
