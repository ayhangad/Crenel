import Foundation

struct StoredMeeting: Identifiable, Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    enum ProcessingStatus: String, Codable, Equatable, Sendable {
        case recorded
        case processing
        case completed
        case failed
    }

    let schemaVersion: Int
    let id: UUID
    var title: String
    let startedAt: Date
    let endedAt: Date
    let sourceMeeting: Meeting?
    let audioFileName: String
    let microphoneFileName: String?
    let systemAudioFileName: String?
    var processingStatus: ProcessingStatus
    var summaryNeedsAttention: Bool? = nil

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID,
        title: String,
        startedAt: Date,
        endedAt: Date,
        sourceMeeting: Meeting?,
        audioFileName: String,
        microphoneFileName: String? = nil,
        systemAudioFileName: String? = nil,
        processingStatus: ProcessingStatus = .recorded
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceMeeting = sourceMeeting
        self.audioFileName = audioFileName
        self.microphoneFileName = microphoneFileName
        self.systemAudioFileName = systemAudioFileName
        self.processingStatus = processingStatus
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}
