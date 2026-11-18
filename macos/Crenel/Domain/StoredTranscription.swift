import Foundation

struct StoredTranscription: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let completedAt: Date
    let transcript: Transcript
    let summary: MeetingSummary?
    /// Allows a retried retranscription to resume its own durable checkpoint.
    var transcriptionJobID: UUID?
    var summaryFailure: String? = nil

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        completedAt: Date = Date(),
        transcript: Transcript,
        summary: MeetingSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.completedAt = completedAt
        self.transcript = transcript
        self.summary = summary
    }
}
