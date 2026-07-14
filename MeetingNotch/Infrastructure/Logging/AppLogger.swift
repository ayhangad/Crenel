import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MeetingNotch"
    private static let flow = Logger(subsystem: subsystem, category: "meeting-flow")
    private static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    private static let audio = Logger(subsystem: subsystem, category: "audio")

    static func transitioned(from: MeetingFlowState.Phase, to: MeetingFlowState.Phase) {
        flow.debug("Flow transition: \(from.rawValue, privacy: .public) -> \(to.rawValue, privacy: .public)")
    }

    static func rejected(eventName: String, phase: MeetingFlowState.Phase) {
        flow.notice("Rejected flow event \(eventName, privacy: .public) in \(phase.rawValue, privacy: .public)")
    }

    static func terminationRequiresConfirmation(phase: MeetingFlowState.Phase) {
        lifecycle.notice("Termination requested during \(phase.rawValue, privacy: .public)")
    }

    static func audioCaptureFailed(source: String, message: String) {
        audio.error("Audio capture failure [\(source, privacy: .public)]: \(message, privacy: .public)")
    }
}
