import Foundation

enum MeetingLifecyclePrompt: Equatable, Sendable {
    case recordingOffer(sessionID: UUID, clientID: MeetingClientID?)
    case endConfirmation(sessionID: UUID, clientID: MeetingClientID?)
    case autoStop(sessionID: UUID, clientID: MeetingClientID?, deadline: Date)

    var sessionID: UUID {
        switch self {
        case .recordingOffer(let sessionID, _),
             .endConfirmation(let sessionID, _),
             .autoStop(let sessionID, _, _):
            sessionID
        }
    }
}

enum MeetingSessionLifecycleDecision: Equatable, Sendable {
    case none
    case present(MeetingLifecyclePrompt)
    case dismiss
}

struct MeetingSessionLifecyclePolicy: Sendable {
    static let autoStopCountdown: TimeInterval = 5

    private(set) var activePrompt: MeetingLifecyclePrompt?
    private var lastOfferedSessionID: UUID?
    private var suppressedEndSessionIDs: Set<UUID> = []

    mutating func evaluate(
        _ session: MeetingSession,
        isRecording: Bool,
        canOfferRecording: Bool,
        now: Date = Date()
    ) -> MeetingSessionLifecycleDecision {
        guard isRecording else {
            if session.state == .ready, session.confidence == .confirmed {
                if case .recordingOffer(let sessionID, _)? = activePrompt,
                   sessionID == session.id {
                    return .none
                }
                if canOfferRecording, lastOfferedSessionID != session.id {
                    lastOfferedSessionID = session.id
                    let prompt = MeetingLifecyclePrompt.recordingOffer(
                        sessionID: session.id,
                        clientID: session.clientID
                    )
                    activePrompt = prompt
                    return .present(prompt)
                }
            }
            guard activePrompt != nil else { return .none }
            activePrompt = nil
            return .dismiss
        }

        if case .recordingOffer = activePrompt {
            activePrompt = nil
        }

        guard !suppressedEndSessionIDs.contains(session.id) else {
            guard activePrompt != nil else { return .none }
            activePrompt = nil
            return .dismiss
        }

        if session.state == .ended, session.confidence == .confirmed {
            if case .autoStop(let sessionID, _, _)? = activePrompt,
               sessionID == session.id {
                return .none
            }
            let prompt = MeetingLifecyclePrompt.autoStop(
                sessionID: session.id,
                clientID: session.clientID,
                deadline: now.addingTimeInterval(Self.autoStopCountdown)
            )
            activePrompt = prompt
            return .present(prompt)
        }

        if session.state == .endSuspected, session.confidence == .probable {
            if case .endConfirmation(let sessionID, _)? = activePrompt,
               sessionID == session.id {
                return .none
            }
            let prompt = MeetingLifecyclePrompt.endConfirmation(
                sessionID: session.id,
                clientID: session.clientID
            )
            activePrompt = prompt
            return .present(prompt)
        }

        guard activePrompt != nil else { return .none }
        activePrompt = nil
        return .dismiss
    }

    mutating func dismissRecordingOffer() -> MeetingSessionLifecycleDecision {
        guard case .recordingOffer? = activePrompt else { return .none }
        activePrompt = nil
        return .dismiss
    }

    mutating func continueRecording(
        sessionID: UUID
    ) -> MeetingSessionLifecycleDecision {
        suppressedEndSessionIDs.insert(sessionID)
        guard activePrompt?.sessionID == sessionID else { return .none }
        activePrompt = nil
        return .dismiss
    }

    mutating func confirmEnd(
        sessionID: UUID
    ) -> MeetingSessionLifecycleDecision {
        guard activePrompt?.sessionID == sessionID else { return .none }
        activePrompt = nil
        return .dismiss
    }
}
