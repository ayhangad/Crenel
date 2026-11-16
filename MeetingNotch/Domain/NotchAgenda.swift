import Foundation

/// What the closed notch shows about the calendar: the next item counting down, or the
/// item in progress with its remaining time. Covers meetings and personal events alike.
struct NotchAgendaStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case upcoming(startsIn: TimeInterval)
        case ongoing(remaining: TimeInterval)

        var isOngoing: Bool {
            if case .ongoing = self { return true }
            return false
        }
    }

    let item: Meeting
    let phase: Phase

    /// Countdown is shown for items starting within this window.
    static let defaultHorizon: TimeInterval = 12 * 60 * 60
    /// When something is in progress, the next item takes over this long before it starts.
    static let defaultHandoff: TimeInterval = 10 * 60

    static func resolve(
        items: [Meeting],
        now: Date,
        horizon: TimeInterval = defaultHorizon,
        handoff: TimeInterval = defaultHandoff
    ) -> NotchAgendaStatus? {
        let timed = items
            .filter { !$0.isAllDay && $0.endDate > now && $0.endDate > $0.startDate }
            .sorted { lhs, rhs in
                lhs.startDate == rhs.startDate
                    ? lhs.endDate < rhs.endDate
                    : lhs.startDate < rhs.startDate
            }

        let next = timed.first { $0.startDate > now }
        // Of overlapping items in progress, the most recently started one is most relevant.
        let ongoing = timed
            .filter { $0.startDate <= now }
            .max { $0.startDate < $1.startDate }

        if let next {
            let startsIn = next.startDate.timeIntervalSince(now)
            if ongoing == nil ? startsIn <= horizon : startsIn <= handoff {
                return NotchAgendaStatus(item: next, phase: .upcoming(startsIn: startsIn))
            }
        }
        if let ongoing {
            return NotchAgendaStatus(
                item: ongoing,
                phase: .ongoing(remaining: ongoing.endDate.timeIntervalSince(now))
            )
        }
        return nil
    }

    enum Urgency: Equatable, Sendable {
        case calm
        case soon
        case imminent
    }

    var urgency: Urgency {
        switch phase {
        case .ongoing:
            .calm
        case .upcoming(let startsIn):
            startsIn <= 60 ? .imminent : (startsIn <= Self.defaultHandoff ? .soon : .calm)
        }
    }
}

/// Short Turkish texts for the closed notch, e.g. "12 dk", "1 sa 5 dk", "15:30", "25 dk kaldı".
enum NotchAgendaFormatter {
    static func compactText(
        for status: NotchAgendaStatus,
        calendar: Calendar = .current
    ) -> String {
        switch status.phase {
        case .upcoming(let startsIn):
            if startsIn < 60 { return "<1 dk" }
            if startsIn >= 3 * 60 * 60 {
                return clockText(status.item.startDate, calendar: calendar)
            }
            return durationText(startsIn)
        case .ongoing(let remaining):
            if remaining < 60 { return "Bitiyor" }
            return "\(durationText(remaining)) kaldı"
        }
    }

    static func accessibilityText(
        for status: NotchAgendaStatus,
        calendar: Calendar = .current
    ) -> String {
        let noun = status.item.isMeetingLike ? "Toplantı" : "Etkinlik"
        switch status.phase {
        case .upcoming(let startsIn):
            if startsIn >= 3 * 60 * 60 {
                return "\(status.item.title), saat \(clockText(status.item.startDate, calendar: calendar))"
            }
            return "\(noun) \(durationText(max(60, startsIn))) sonra: \(status.item.title)"
        case .ongoing(let remaining):
            return "\(status.item.title), bitmesine \(durationText(max(60, remaining)))"
        }
    }

    /// Minutes are rounded up so "starts in 59.5 min" never shows "59 dk".
    static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) dk" }
        if minutes == 0 { return "\(hours) sa" }
        return "\(hours) sa \(minutes) dk"
    }

    static func clockText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

/// Deep link that opens an event in the Calendar app.
enum CalendarAppLink {
    /// EventKit identifiers look like "UUID:UUID"; Calendar expects the colon unescaped.
    private static let identifierCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-:._~"))

    static func url(for item: Meeting) -> URL? {
        guard let identifier = item.eventIdentifier,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: Self.identifierCharacters)
        else {
            return URL(string: "ical://")
        }
        return URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
    }
}

/// Texts for agenda rows in the expanded notch and desktop.
enum AgendaRowText {
    static func subtitle(for item: Meeting, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if item.isAllDay {
            parts.append("Tüm gün")
        } else {
            let start = NotchAgendaFormatter.clockText(item.startDate, calendar: calendar)
            let end = NotchAgendaFormatter.clockText(item.endDate, calendar: calendar)
            let day = calendar.isDate(item.startDate, inSameDayAs: Date())
                ? ""
                : (calendar.isDateInTomorrow(item.startDate) ? "Yarın " : "")
            parts.append("\(day)\(start)–\(end)")
        }
        if let location = item.location, item.meetingURL == nil || !location.contains("://") {
            parts.append(location)
        } else if let calendarTitle = item.calendarTitle {
            parts.append(calendarTitle)
        }
        if item.isSuggestion { parts.append("Mail’den öneri") }
        return parts.joined(separator: " · ")
    }

    static func accessibilityLabel(for item: Meeting) -> String {
        let action = item.meetingURL == nil ? "Takvim’de aç" : "toplantıya katıl"
        return "\(item.title), \(subtitle(for: item)), \(action)"
    }
}
