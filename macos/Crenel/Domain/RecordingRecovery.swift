import Foundation

struct RecordingRecoveryReport: Equatable, Sendable {
    let recoveredMeetings: [StoredMeeting]
    let preservedCount: Int

    static let empty = RecordingRecoveryReport(recoveredMeetings: [], preservedCount: 0)

    var hasResults: Bool {
        !recoveredMeetings.isEmpty || preservedCount > 0
    }
}

struct RecordingRecoverySummary: Equatable, Sendable {
    let recoveredCount: Int
    let preservedCount: Int

    init(report: RecordingRecoveryReport) {
        recoveredCount = report.recoveredMeetings.count
        preservedCount = report.preservedCount
    }
}
