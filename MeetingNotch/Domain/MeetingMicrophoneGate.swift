import Foundation

enum MeetingMicrophoneGateEventSource: String, Codable, Equatable, Sendable {
    case recordingStarted
    case clientAdapter
    case manualControl
    case adapterUnavailable
    case processChanged
    case systemInterruption
}

struct MeetingMicrophoneGateEvent: Codable, Equatable, Sendable {
    let timestamp: Date
    let state: MeetingMicrophoneState
    let source: MeetingMicrophoneGateEventSource
    let confidence: DetectionConfidence
}

struct MeetingMicrophoneGate: Equatable, Sendable {
    private(set) var state: MeetingMicrophoneState
    private(set) var events: [MeetingMicrophoneGateEvent]

    var permitsAudio: Bool { state == .open }

    init(recordingStartedAt: Date) {
        state = .closed
        events = [
            MeetingMicrophoneGateEvent(
                timestamp: recordingStartedAt,
                state: .closed,
                source: .recordingStarted,
                confidence: .confirmed
            )
        ]
    }

    @discardableResult
    mutating func observeClientState(
        _ observedState: MeetingMicrophoneState,
        confidence: DetectionConfidence,
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        let safeState: MeetingMicrophoneState
        if observedState == .open && confidence != .confirmed {
            safeState = .unknown
        } else {
            safeState = observedState
        }
        return transition(
            to: safeState,
            source: .clientAdapter,
            confidence: confidence,
            at: timestamp
        )
    }

    @discardableResult
    mutating func setManualState(
        _ state: MeetingMicrophoneState,
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        let safeState = state == .unknown ? MeetingMicrophoneState.closed : state
        return transition(
            to: safeState,
            source: .manualControl,
            confidence: .confirmed,
            at: timestamp
        )
    }

    @discardableResult
    mutating func adapterBecameUnavailable(
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        transition(
            to: .unknown,
            source: .adapterUnavailable,
            confidence: .unknown,
            at: timestamp
        )
    }

    @discardableResult
    mutating func meetingProcessChanged(
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        transition(
            to: .unknown,
            source: .processChanged,
            confidence: .unknown,
            at: timestamp
        )
    }

    @discardableResult
    mutating func systemWasInterrupted(
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        transition(
            to: .unknown,
            source: .systemInterruption,
            confidence: .unknown,
            at: timestamp
        )
    }

    private mutating func transition(
        to newState: MeetingMicrophoneState,
        source: MeetingMicrophoneGateEventSource,
        confidence: DetectionConfidence,
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        guard let latest = events.last,
              timestamp >= latest.timestamp,
              newState != state else { return nil }
        let event = MeetingMicrophoneGateEvent(
            timestamp: timestamp,
            state: newState,
            source: source,
            confidence: confidence
        )
        state = newState
        events.append(event)
        return event
    }
}
