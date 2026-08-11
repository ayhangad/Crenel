import Foundation

struct RecordingSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let meetingID: UUID?
    let sourceMeeting: Meeting?
    let startedAt: Date
    var endedAt: Date?
    var audioFileURL: URL?
    var microphoneGateEvents: [MeetingMicrophoneGateEvent]

    init(
        id: UUID = UUID(),
        meetingID: UUID? = nil,
        sourceMeeting: Meeting? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        audioFileURL: URL? = nil,
        microphoneGateEvents: [MeetingMicrophoneGateEvent] = []
    ) {
        self.id = id
        self.meetingID = meetingID
        self.sourceMeeting = sourceMeeting
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioFileURL = audioFileURL
        self.microphoneGateEvents = microphoneGateEvents
    }

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case meetingID
        case sourceMeeting
        case startedAt
        case endedAt
        case audioFileURL
        case microphoneGateEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        meetingID = try container.decodeIfPresent(UUID.self, forKey: .meetingID)
        sourceMeeting = try container.decodeIfPresent(Meeting.self, forKey: .sourceMeeting)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        audioFileURL = try container.decodeIfPresent(URL.self, forKey: .audioFileURL)
        microphoneGateEvents = try container.decodeIfPresent(
            [MeetingMicrophoneGateEvent].self,
            forKey: .microphoneGateEvents
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(meetingID, forKey: .meetingID)
        try container.encodeIfPresent(sourceMeeting, forKey: .sourceMeeting)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(audioFileURL, forKey: .audioFileURL)
        try container.encode(microphoneGateEvents, forKey: .microphoneGateEvents)
    }
}
