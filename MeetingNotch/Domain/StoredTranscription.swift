import Foundation

struct StoredTranscription: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let providerID: TranscriptionProviderID
    let completedAt: Date
    let transcript: Transcript
    let summary: MeetingSummary?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        providerID: TranscriptionProviderID,
        completedAt: Date = Date(),
        transcript: Transcript,
        summary: MeetingSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.completedAt = completedAt
        self.transcript = transcript
        self.summary = summary
    }
}
