import Foundation

enum MeetingMicrophoneGateEventSource: String, Codable, Equatable, Sendable {
    case recordingStarted
    case clientAdapter
    case dictationHold
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

/// Whether the user's microphone reaches the recording.
///
/// 2026-11-20 decision: every recording starts with the microphone open; the user closes
/// it in the notch or with the shortcut. Starting closed recorded only the other side of
/// calls Crenel can't read (Slack huddles, Teams, FaceTime) unless the user noticed the
/// warning and opened it. A call app's confirmed mute still closes it and a confirmed
/// unmute opens it; an unreadable or unknown call state leaves it as it is.
struct MeetingMicrophoneGate: Equatable, Sendable {
    private var baseState: MeetingMicrophoneState
    private(set) var dictationHeld: Bool
    var state: MeetingMicrophoneState { dictationHeld ? .closed : baseState }
    private(set) var events: [MeetingMicrophoneGateEvent]

    var permitsAudio: Bool { state == .open }
    var nextManualState: MeetingMicrophoneState { baseState == .open ? .closed : .open }

    init(recordingStartedAt: Date, dictationHeld: Bool = false) {
        self.dictationHeld = dictationHeld
        baseState = .open
        events = [
            MeetingMicrophoneGateEvent(
                timestamp: recordingStartedAt,
                state: dictationHeld ? .closed : .open,
                source: .recordingStarted,
                confidence: .confirmed
            )
        ]
    }

    mutating func setDictationHeld(_ held: Bool, at timestamp: Date) {
        guard held != dictationHeld else { return }
        dictationHeld = held
        events.append(MeetingMicrophoneGateEvent(timestamp: timestamp, state: state, source: .dictationHold, confidence: .confirmed))
    }

    @discardableResult
    mutating func observeClientState(
        _ observedState: MeetingMicrophoneState,
        confidence: DetectionConfidence,
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        // An unconfirmed "open" or an unknown state is no news: keep the current state.
        guard observedState == .closed || confidence == .confirmed,
              observedState != .unknown else { return nil }
        return transition(
            to: observedState,
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

    /// The call app can no longer be read. The user's own choice (or the default open
    /// state) stands; nothing about the mute is known.
    @discardableResult
    mutating func adapterBecameUnavailable(
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        nil
    }

    /// The recorded call process went away; the microphone is still the user's choice.
    @discardableResult
    mutating func meetingProcessChanged(
        at timestamp: Date
    ) -> MeetingMicrophoneGateEvent? {
        nil
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
              newState != baseState else { return nil }
        baseState = newState
        let event = MeetingMicrophoneGateEvent(
            timestamp: timestamp,
            state: state,
            source: source,
            confidence: confidence
        )
        events.append(event)
        return event
    }
}
