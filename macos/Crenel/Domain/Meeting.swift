import Foundation

/// How a calendar item should be treated by the notch.
enum CalendarItemKind: String, Codable, Sendable {
    /// Has a recognised video-call link (Zoom, Meet, Teams…).
    case onlineMeeting
    /// Has other attendees but no call link (in-person or phone meeting).
    case meeting
    /// A personal event: no attendees and no call link.
    case event
}

/// The current user's answer to an invitation.
enum CalendarResponseStatus: String, Codable, Sendable {
    /// Organizer, personal event or a calendar without RSVP.
    case none
    case accepted
    case tentative
    /// Invitation waiting for an answer (e.g. arrived by e-mail).
    case pending
}

/// A calendar item read from Apple Calendar. Historically only online meetings were
/// modelled, hence the name; it now represents every timed or all-day event.
struct Meeting: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var meetingURL: URL?
    var calendarIdentifier: String?
    var externalIdentifier: String?
    var kind: CalendarItemKind
    var isAllDay: Bool
    var responseStatus: CalendarResponseStatus
    var location: String?
    var calendarTitle: String?
    var calendarColorHex: String?
    /// Event found by Siri in Mail/Messages and not yet confirmed by the user.
    var isSuggestion: Bool
    /// EventKit identifier used to open the event in Calendar.
    var eventIdentifier: String?
    /// Display names of the other people invited, without the current user.
    var attendees: [String]
    /// Who sent the invitation; nil when it was the current user or unknown.
    var organizer: String?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        meetingURL: URL? = nil,
        calendarIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        kind: CalendarItemKind? = nil,
        isAllDay: Bool = false,
        responseStatus: CalendarResponseStatus = .none,
        location: String? = nil,
        calendarTitle: String? = nil,
        calendarColorHex: String? = nil,
        isSuggestion: Bool = false,
        eventIdentifier: String? = nil,
        attendees: [String] = [],
        organizer: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.meetingURL = meetingURL
        self.calendarIdentifier = calendarIdentifier
        self.externalIdentifier = externalIdentifier
        // Callers that do not classify (tests, legacy code) are treated as meetings.
        self.kind = kind ?? (meetingURL == nil ? .meeting : .onlineMeeting)
        self.isAllDay = isAllDay
        self.responseStatus = responseStatus
        self.location = location
        self.calendarTitle = calendarTitle
        self.calendarColorHex = calendarColorHex
        self.isSuggestion = isSuggestion
        self.eventIdentifier = eventIdentifier
        self.attendees = attendees
        self.organizer = organizer
    }

    /// Meetings (online or with attendees) get recording offers and join notifications;
    /// personal events only get the notch countdown.
    var isMeetingLike: Bool {
        kind != .event
    }

    /// Timed meeting that may drive the recording reminder flow.
    var isReminderCandidate: Bool {
        isMeetingLike && !isAllDay && !isSuggestion
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, meetingURL, calendarIdentifier, externalIdentifier
        case kind, isAllDay, responseStatus, location, calendarTitle, calendarColorHex
        case isSuggestion, eventIdentifier, attendees, organizer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        meetingURL = try container.decodeIfPresent(URL.self, forKey: .meetingURL)
        calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier)
        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
        // Documents written before Crenel only contained online meetings.
        kind = try container.decodeIfPresent(CalendarItemKind.self, forKey: .kind)
            ?? (meetingURL == nil ? .meeting : .onlineMeeting)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        responseStatus = try container.decodeIfPresent(CalendarResponseStatus.self, forKey: .responseStatus) ?? .none
        location = try container.decodeIfPresent(String.self, forKey: .location)
        calendarTitle = try container.decodeIfPresent(String.self, forKey: .calendarTitle)
        calendarColorHex = try container.decodeIfPresent(String.self, forKey: .calendarColorHex)
        isSuggestion = try container.decodeIfPresent(Bool.self, forKey: .isSuggestion) ?? false
        eventIdentifier = try container.decodeIfPresent(String.self, forKey: .eventIdentifier)
        // Documents written before attendees were read have none.
        attendees = try container.decodeIfPresent([String].self, forKey: .attendees) ?? []
        organizer = try container.decodeIfPresent(String.self, forKey: .organizer)
    }
}

enum MeetingStableIdentifier {
    static func uuid(for value: String) -> UUID {
        var high: UInt64 = 0xcbf29ce484222325
        var low: UInt64 = 0x84222325cbf29ce4
        for byte in value.utf8 {
            high ^= UInt64(byte)
            high &*= 0x100000001b3
            low ^= UInt64(byte) &+ 0x9e
            low &*= 0x100000001b3
        }

        var bytes = withUnsafeBytes(of: high.bigEndian, Array.init)
        bytes.append(contentsOf: withUnsafeBytes(of: low.bigEndian, Array.init))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
