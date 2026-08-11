import OSLog

struct PrivacySafeDiagnostic: Equatable, Sendable {
    let errorType: String

    init(error: Error) {
        errorType = String(reflecting: type(of: error))
    }
}

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MeetingNotch"
    private static let flow = Logger(subsystem: subsystem, category: "meeting-flow")
    private static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    private static let audio = Logger(subsystem: subsystem, category: "audio")
    private static let persistence = Logger(subsystem: subsystem, category: "persistence")
    private static let meetingSession = Logger(subsystem: subsystem, category: "meeting-session")

    static func transitioned(from: MeetingFlowState.Phase, to: MeetingFlowState.Phase) {
        flow.debug("Flow transition: \(from.rawValue, privacy: .public) -> \(to.rawValue, privacy: .public)")
    }

    static func rejected(eventName: String, phase: MeetingFlowState.Phase) {
        flow.notice("Rejected flow event \(eventName, privacy: .public) in \(phase.rawValue, privacy: .public)")
    }

    static func meetingSessionUpdated(_ snapshot: MeetingSessionDetectionSnapshot) {
        let diagnostic = meetingSessionDiagnostic(snapshot)
        meetingSession.notice("\(diagnostic.logLine, privacy: .public)")
    }

    static func meetingSessionDiagnostic(
        _ snapshot: MeetingSessionDetectionSnapshot
    ) -> MeetingSessionDiagnostic {
        let session = snapshot.session
        let confidence: String
        switch session.confidence {
        case .unknown:
            confidence = "unknown"
        case .probable:
            confidence = "probable"
        case .confirmed:
            confidence = "confirmed"
        }
        return MeetingSessionDiagnostic(
            sessionID: session.id,
            state: session.state.rawValue,
            confidence: confidence,
            client: session.clientID?.rawValue ?? "none",
            microphone: snapshot.microphoneState.rawValue,
            evidenceKinds: session.evidence.map { $0.kind.rawValue }
        )
    }

    static func terminationRequiresConfirmation(phase: MeetingFlowState.Phase) {
        lifecycle.notice("Termination requested during \(phase.rawValue, privacy: .public)")
    }

    static func permissionOperationFailed(operation: String) {
        lifecycle.error("Permission operation [\(operation, privacy: .public)] failed")
    }

    static func audioCaptureFailed(source: String, error: Error) {
        let diagnostic = PrivacySafeDiagnostic(error: error)
        audio.error(
            "Audio capture failure [\(source, privacy: .public)] type=\(diagnostic.errorType, privacy: .public)"
        )
    }

    static func recordingOperationFailed(operation: String, error: Error) {
        let diagnostic = PrivacySafeDiagnostic(error: error)
        audio.error(
            "Recording operation [\(operation, privacy: .public)] failed type=\(diagnostic.errorType, privacy: .public)"
        )
    }

    static func persistenceFailed(operation: String, error: Error) {
        let diagnostic = PrivacySafeDiagnostic(error: error)
        persistence.error(
            "Persistence failure [\(operation, privacy: .public)] type=\(diagnostic.errorType, privacy: .public)"
        )
    }

    static func persistenceFailed(operation: String, failureCount: Int) {
        persistence.error(
            "Persistence failure [\(operation, privacy: .public)] count=\(failureCount, privacy: .public)"
        )
    }
}
