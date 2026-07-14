import Foundation

struct RecordingSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let meetingID: UUID?
    let sourceMeeting: Meeting?
    let startedAt: Date
    var endedAt: Date?
    var audioFileURL: URL?

    init(
        id: UUID = UUID(),
        meetingID: UUID? = nil,
        sourceMeeting: Meeting? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        audioFileURL: URL? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.sourceMeeting = sourceMeeting
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioFileURL = audioFileURL
    }

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }
}
