import Foundation

enum MeetingClientID: String, Codable, CaseIterable, Equatable, Sendable {
    case zoom
    case googleMeetChrome
    case unsupported
}

enum DetectionConfidence: Int, Codable, Comparable, Equatable, Sendable {
    case unknown
    case probable
    case confirmed

    static func < (lhs: DetectionConfidence, rhs: DetectionConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MeetingSessionState: String, Codable, Equatable, Sendable {
    case scheduled
    case candidate
    case ready
    case recording
    case endSuspected
    case ended
}

enum MeetingEvidence: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case calendarContext
        case joinAction
        case process
        case audioIO
        case clientUI
        case manualRecording
        case manualStop
    }

    case calendarContext(meetingID: String, isWithinScheduledWindow: Bool)
    case joinAction
    case process(processID: Int32, isRunning: Bool)
    case audioIO(processID: Int32, isRunningInput: Bool, isRunningOutput: Bool)
    case clientUI(
        clientID: MeetingClientID,
        meetingWindowPresent: Bool,
        callControlsPresent: Bool
    )
    case manualRecording
    case manualStop

    var kind: Kind {
        switch self {
        case .calendarContext: .calendarContext
        case .joinAction: .joinAction
        case .process: .process
        case .audioIO: .audioIO
        case .clientUI: .clientUI
        case .manualRecording: .manualRecording
        case .manualStop: .manualStop
        }
    }
}

struct MeetingSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var state: MeetingSessionState
    var confidence: DetectionConfidence
    var evidence: Set<MeetingEvidence>
    var clientID: MeetingClientID?
    var processID: Int32?
    var calendarMeetingID: String?
    var lastChangedAt: Date

    init(
        id: UUID = UUID(),
        state: MeetingSessionState = .candidate,
        confidence: DetectionConfidence = .unknown,
        evidence: Set<MeetingEvidence> = [],
        clientID: MeetingClientID? = nil,
        processID: Int32? = nil,
        calendarMeetingID: String? = nil,
        lastChangedAt: Date = Date()
    ) {
        self.id = id
        self.state = state
        self.confidence = confidence
        self.evidence = evidence
        self.clientID = clientID
        self.processID = processID
        self.calendarMeetingID = calendarMeetingID
        self.lastChangedAt = lastChangedAt
    }
}

struct MeetingSessionMachine: Sendable {
    private(set) var session: MeetingSession
    private var latestEvidence: [MeetingEvidence.Kind: MeetingEvidence]

    init(session: MeetingSession = MeetingSession()) {
        self.session = session
        var latestEvidence: [MeetingEvidence.Kind: MeetingEvidence] = [:]
        for evidence in session.evidence {
            latestEvidence[evidence.kind] = evidence
        }
        self.latestEvidence = latestEvidence
    }

    mutating func observe(_ evidence: MeetingEvidence, at date: Date = Date()) {
        guard session.state != .ended else { return }
        latestEvidence[evidence.kind] = evidence
        applyMetadata(from: evidence)
        reduce(at: date)
    }

    mutating func recordingStarted(at date: Date = Date()) {
        guard session.state != .ended else { return }
        latestEvidence[.manualRecording] = .manualRecording
        update(state: .recording, confidence: .confirmed, at: date)
    }

    mutating func recordingStopped(at date: Date = Date()) {
        guard session.state == .recording || session.state == .endSuspected else {
            return
        }
        latestEvidence[.manualStop] = .manualStop
        update(state: .ended, confidence: .confirmed, at: date)
    }

    private mutating func applyMetadata(from evidence: MeetingEvidence) {
        switch evidence {
        case .calendarContext(let meetingID, _):
            session.calendarMeetingID = meetingID
        case .process(let processID, _), .audioIO(let processID, _, _):
            session.processID = processID
        case .clientUI(let clientID, _, _):
            session.clientID = clientID
        case .joinAction, .manualRecording, .manualStop:
            break
        }
    }

    private mutating func reduce(at date: Date) {
        if session.state == .recording || session.state == .endSuspected {
            let endConfidence = detectedEndConfidence()
            switch endConfidence {
            case .confirmed:
                update(state: .ended, confidence: .confirmed, at: date)
            case .probable:
                update(state: .endSuspected, confidence: .probable, at: date)
            case .unknown:
                update(state: .recording, confidence: detectedStartConfidence(), at: date)
            }
            return
        }

        let startConfidence = detectedStartConfidence()
        let state: MeetingSessionState
        switch startConfidence {
        case .confirmed:
            state = .ready
        case .probable:
            state = .candidate
        case .unknown:
            state = latestEvidence[.calendarContext] == nil ? .candidate : .scheduled
        }
        update(state: state, confidence: startConfidence, at: date)
    }

    private func detectedStartConfidence() -> DetectionConfidence {
        if latestEvidence[.manualRecording] != nil {
            return .confirmed
        }

        let processRunning: Bool = {
            guard case .process(_, let isRunning)? = latestEvidence[.process] else {
                return false
            }
            return isRunning
        }()
        let audioActive: Bool = {
            guard case .audioIO(_, let input, let output)? = latestEvidence[.audioIO] else {
                return false
            }
            return input || output
        }()
        let meetingUIPresent: Bool = {
            guard case .clientUI(_, let window, let controls)? = latestEvidence[.clientUI] else {
                return false
            }
            return window && controls
        }()
        let joinedFromMeetingNotch = latestEvidence[.joinAction] != nil

        if processRunning && meetingUIPresent {
            return .confirmed
        }
        if (processRunning && audioActive)
            || meetingUIPresent
            || (joinedFromMeetingNotch && processRunning) {
            return .probable
        }
        return .unknown
    }

    private func detectedEndConfidence() -> DetectionConfidence {
        let processStopped: Bool = {
            guard case .process(_, let isRunning)? = latestEvidence[.process] else {
                return false
            }
            return !isRunning
        }()
        let audioStopped: Bool = {
            guard case .audioIO(_, let input, let output)? = latestEvidence[.audioIO] else {
                return false
            }
            return !input && !output
        }()
        let meetingUIGone: Bool = {
            guard case .clientUI(_, let window, let controls)? = latestEvidence[.clientUI] else {
                return false
            }
            return !window && !controls
        }()
        let calendarWindowEnded: Bool = {
            guard case .calendarContext(_, let isWithinWindow)? =
                    latestEvidence[.calendarContext] else {
                return false
            }
            return !isWithinWindow
        }()

        if meetingUIGone && audioStopped && (processStopped || calendarWindowEnded) {
            return .confirmed
        }
        if (meetingUIGone && audioStopped)
            || (processStopped && (meetingUIGone || audioStopped)) {
            return .probable
        }
        return .unknown
    }

    private mutating func update(
        state: MeetingSessionState,
        confidence: DetectionConfidence,
        at date: Date
    ) {
        let evidence = Set(latestEvidence.values)
        let changed = session.state != state
            || session.confidence != confidence
            || session.evidence != evidence
        session.state = state
        session.confidence = confidence
        session.evidence = evidence
        if changed {
            session.lastChangedAt = date
        }
    }
}
