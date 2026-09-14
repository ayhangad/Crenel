import Foundation

struct Transcript: Codable, Equatable, Sendable {
    var text: String
    var languageCode: String?
    var segments: [TranscriptSegment]
}

struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var speakerID: String
    var speakerName: String?
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    init(
        id: UUID = UUID(),
        speakerID: String,
        speakerName: String? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.id = id
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

struct MeetingSummary: Codable, Equatable, Sendable {
    var overview: String
    var decisions: [String]
    var actionItems: [ActionItem]
    var suggestedTitle: String? = nil
    var model: String? = nil
}

struct ActionItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var assignee: String?
    var dueDate: Date?
    var speakerID: String?
    var sourceSegmentID: UUID?
    var sourceTime: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String,
        assignee: String? = nil,
        dueDate: Date? = nil,
        speakerID: String? = nil,
        sourceSegmentID: UUID? = nil,
        sourceTime: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.dueDate = dueDate
        self.speakerID = speakerID
        self.sourceSegmentID = sourceSegmentID
        self.sourceTime = sourceTime
    }
}
