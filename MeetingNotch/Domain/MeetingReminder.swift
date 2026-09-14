import Foundation

enum CalendarAccessState: Equatable, Sendable {
    case notDetermined
    case requesting
    case authorized
    case denied
    case restricted
    case failed(String)
}

enum CalendarAccountKind: String, CaseIterable, Hashable, Sendable {
    case google
    case iCloud
    case exchange
    case calDAV
    case local
    case subscribed
    case other

    var title: String {
        switch self {
        case .google: "Google"
        case .iCloud: "iCloud"
        case .exchange: "Exchange"
        case .calDAV: "CalDAV"
        case .local: "Bu Mac"
        case .subscribed: "Abonelik"
        case .other: "Diğer"
        }
    }
}

struct CalendarSourceSummary: Equatable, Identifiable, Sendable {
    let kind: CalendarAccountKind
    let calendarCount: Int

    var id: CalendarAccountKind { kind }
}

struct CalendarChoice: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct CalendarMeetingQueryResult: Equatable, Sendable {
    let meetings: [Meeting]
    let sources: [CalendarSourceSummary]
    let scannedEventCount: Int
    var calendars: [CalendarChoice] = []

    var readableCalendarCount: Int {
        sources.reduce(0) { $0 + $1.calendarCount }
    }
}

struct CalendarIntegrationSnapshot: Equatable, Sendable {
    let sources: [CalendarSourceSummary]
    let scannedEventCount: Int
    let matchedMeetingCount: Int
    let refreshedAt: Date
    var calendars: [CalendarChoice] = []

    var readableCalendarCount: Int {
        sources.reduce(0) { $0 + $1.calendarCount }
    }

    var hasGoogleAccount: Bool {
        sources.contains { $0.kind == .google }
    }
}

enum MeetingReminderLevel: Int, Comparable, Codable, Sendable {
    case none = 0
    case tenMinutes = 1
    case oneMinute = 2
    case started = 3

    static func < (lhs: MeetingReminderLevel, rhs: MeetingReminderLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MeetingReminderSnapshot: Equatable, Sendable {
    let nextMeeting: Meeting?
    let level: MeetingReminderLevel
    let secondsUntilStart: TimeInterval?

    var presentationKey: String? {
        guard let nextMeeting, level != .none else { return nil }
        let source = nextMeeting.externalIdentifier ?? nextMeeting.id.uuidString
        return "\(source)|\(nextMeeting.startDate.timeIntervalSince1970)|\(level.rawValue)"
    }

    static func evaluate(
        meetings: [Meeting],
        now: Date,
        reminderLeadTime: TimeInterval = 10 * 60
    ) -> MeetingReminderSnapshot {
        let relevant = meetings
            .filter { $0.endDate > now }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }

        guard let meeting = relevant.first else {
            return MeetingReminderSnapshot(nextMeeting: nil, level: .none, secondsUntilStart: nil)
        }

        let seconds = meeting.startDate.timeIntervalSince(now)
        let level: MeetingReminderLevel

        if seconds <= 0 {
            level = .started
        } else if seconds <= 60 {
            level = .oneMinute
        } else if seconds <= max(60, reminderLeadTime) {
            level = .tenMinutes
        } else {
            level = .none
        }

        return MeetingReminderSnapshot(
            nextMeeting: meeting,
            level: level,
            secondsUntilStart: seconds
        )
    }
}

enum CalendarEmptyPresentation {
    static func message(enabled: Bool, access: CalendarAccessState, snapshot: CalendarIntegrationSnapshot?) -> String {
        guard enabled else { return "Takvim bağlantısı kapalı" }
        switch access {
        case .notDetermined: return "Toplantılarınız için takviminizi bağlayın"
        case .requesting: return "Takvim izni bekleniyor"
        case .denied, .restricted: return "Takvim erişimine izin verin"
        case .failed: return "Takvim yenilenemedi"
        case .authorized:
            guard let snapshot else { return "Takvimler okunuyor" }
            return snapshot.readableCalendarCount == 0 ? "Bu Mac’te bağlı takvim bulunamadı" : "Yaklaşan çevrim içi toplantı yok"
        }
    }
}
