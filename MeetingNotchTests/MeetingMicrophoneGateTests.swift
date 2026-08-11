import XCTest
@testable import MeetingNotch

final class MeetingMicrophoneGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testEveryRecordingStartsClosedWithTimestampedEvent() {
        let gate = MeetingMicrophoneGate(recordingStartedAt: start)

        XCTAssertEqual(gate.state, .closed)
        XCTAssertFalse(gate.permitsAudio)
        XCTAssertEqual(
            gate.events,
            [
                MeetingMicrophoneGateEvent(
                    timestamp: start,
                    state: .closed,
                    source: .recordingStarted,
                    confidence: .confirmed
                )
            ]
        )
    }

    func testOnlyConfirmedClientOpenSignalPermitsAudio() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        gate.observeClientState(.open, confidence: .probable, at: start.addingTimeInterval(1))
        XCTAssertEqual(gate.state, .unknown)
        XCTAssertFalse(gate.permitsAudio)

        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(2))
        XCTAssertEqual(gate.state, .open)
        XCTAssertTrue(gate.permitsAudio)
    }

    func testClosedAndUnknownClientSignalsFailClosed() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(1))

        gate.observeClientState(.unknown, confidence: .unknown, at: start.addingTimeInterval(2))
        XCTAssertFalse(gate.permitsAudio)
        XCTAssertEqual(gate.state, .unknown)

        gate.observeClientState(.closed, confidence: .confirmed, at: start.addingTimeInterval(3))
        XCTAssertFalse(gate.permitsAudio)
        XCTAssertEqual(gate.state, .closed)
    }

    func testVisibleManualControlCanOpenAndCloseGate() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)

        let opened = gate.setManualState(.open, at: start.addingTimeInterval(1))
        let closed = gate.setManualState(.closed, at: start.addingTimeInterval(2))

        XCTAssertEqual(opened?.source, .manualControl)
        XCTAssertEqual(opened?.confidence, .confirmed)
        XCTAssertEqual(closed?.state, .closed)
        XCTAssertFalse(gate.permitsAudio)
    }

    func testManualUnknownRequestIsNormalizedToClosed() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(1))

        let event = gate.setManualState(.unknown, at: start.addingTimeInterval(2))

        XCTAssertEqual(event?.state, .closed)
        XCTAssertFalse(gate.permitsAudio)
    }

    func testAdapterLossAndProcessChangeImmediatelyFailClosed() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(1))

        let adapterEvent = gate.adapterBecameUnavailable(at: start.addingTimeInterval(2))
        XCTAssertEqual(adapterEvent?.source, .adapterUnavailable)
        XCTAssertEqual(gate.state, .unknown)
        XCTAssertFalse(gate.permitsAudio)

        gate.setManualState(.open, at: start.addingTimeInterval(3))
        let processEvent = gate.meetingProcessChanged(at: start.addingTimeInterval(4))
        XCTAssertEqual(processEvent?.source, .processChanged)
        XCTAssertEqual(gate.state, .unknown)
        XCTAssertFalse(gate.permitsAudio)
    }

    func testSystemInterruptionImmediatelyFailsClosedAndIsPersistable() throws {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.setManualState(.open, at: start.addingTimeInterval(1))

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
                .closed,
                confidence: .confirmed,
                at: start.addingTimeInterval(1)
            )
        )
        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(2))
        XCTAssertNil(
            gate.observeClientState(
                .closed,
                confidence: .confirmed,
                at: start.addingTimeInterval(1)
            )
        )
        XCTAssertEqual(gate.state, .open)
        XCTAssertEqual(gate.events.count, 2)
    }

    func testGateEventsRoundTripWithoutRawUIContent() throws {
        var gate = MeetingMicrophoneGate(recordingStartedAt: start)
        gate.observeClientState(.open, confidence: .confirmed, at: start.addingTimeInterval(1))

        let data = try JSONEncoder().encode(gate.events)
        let decoded = try JSONDecoder().decode([MeetingMicrophoneGateEvent].self, from: data)

        XCTAssertEqual(decoded, gate.events)
    }
}
