import Foundation

enum CalendarAccessState: Equatable, Sendable {
    case notDetermined
    case requesting
    case authorized
    case denied
    case restricted
    case failed(String)
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
