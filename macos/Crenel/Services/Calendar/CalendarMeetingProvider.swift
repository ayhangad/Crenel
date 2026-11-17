import CoreGraphics
import EventKit
import Foundation

protocol CalendarMeetingProviding: Sendable {
    func selectCalendars(_ ids: [String]?) async
    func authorizationState() async -> CalendarAccessState
    func requestAccess() async throws -> Bool
    func query(from startDate: Date, to endDate: Date) async throws -> CalendarMeetingQueryResult
}

extension CalendarMeetingProviding {
    func selectCalendars(_ ids: [String]?) async {}
}

actor EventKitMeetingProvider: CalendarMeetingProviding {
    private let eventStore: EKEventStore
    private let urlMatcher: MeetingURLMatcher
    private var selectedCalendarIDs: [String]?

    func selectCalendars(_ ids: [String]?) async { selectedCalendarIDs = ids }

    init(
        eventStore: EKEventStore = EKEventStore(),
        urlMatcher: MeetingURLMatcher = MeetingURLMatcher()
    ) {
        self.eventStore = eventStore
        self.urlMatcher = urlMatcher
    }

    func authorizationState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied, .writeOnly:
            .denied
        case .authorized, .fullAccess:
            .authorized
        @unknown default:
            .denied
        }
    }

    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        if granted {
            eventStore.reset()
        }
        return granted
    }

    func query(
        from startDate: Date,
        to endDate: Date
    ) -> CalendarMeetingQueryResult {
        eventStore.refreshSourcesIfNecessary()
        let allCalendars = eventStore.calendars(for: .event)
        let calendars = allCalendars.filter { selectedCalendarIDs?.contains($0.calendarIdentifier) ?? true }
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        let events = calendars.isEmpty ? [] : eventStore.events(matching: predicate)
        let meetings = deduplicatedMeetings(
            events
                .filter(isRelevantEvent)
                .compactMap(makeMeeting)
        )

        return CalendarMeetingQueryResult(
            meetings: meetings,
            sources: sourceSummaries(for: allCalendars),
            scannedEventCount: events.count,
            calendars: allCalendars.map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title) }
        )
    }

    private func isRelevantEvent(_ event: EKEvent) -> Bool {
        guard event.status != .canceled else { return false }
        return CalendarEventClassifier.isVisible(
            responseStatus: currentUserParticipantStatus(event)
        )
    }

    private func currentUserParticipantStatus(_ event: EKEvent) -> EKParticipantStatus? {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus
    }

    private func makeMeeting(from event: EKEvent) -> Meeting? {
        guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
        let meetingURL = urlMatcher.firstMeetingURL(
            explicitURL: event.url,
            location: event.location,
            notes: event.notes
        )
        let others = event.attendees?.filter { !$0.isCurrentUser } ?? []
        let otherAttendeeCount = others.count
        let kind = CalendarEventClassifier.kind(
            hasMeetingURL: meetingURL != nil,
            otherAttendeeCount: otherAttendeeCount
        )

        let occurrence = event.occurrenceDate ?? startDate
        let sourceIdentifier = [
            event.calendar.calendarIdentifier,
            event.eventIdentifier ?? "event",
            String(occurrence.timeIntervalSince1970)
        ].joined(separator: "|")

        return Meeting(
            id: MeetingStableIdentifier.uuid(for: sourceIdentifier),
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? (kind == .event ? "Untitled event" : "Untitled meeting"),
            startDate: startDate,
            endDate: endDate,
            meetingURL: meetingURL,
            calendarIdentifier: event.calendar.calendarIdentifier,
            externalIdentifier: sourceIdentifier,
            kind: kind,
            isAllDay: event.isAllDay,
            responseStatus: CalendarEventClassifier.responseStatus(
                currentUserParticipantStatus(event)
            ),
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            calendarTitle: event.calendar.title,
            calendarColorHex: event.calendar.cgColor.flatMap(CalendarEventClassifier.hexColor),
            isSuggestion: CalendarEventClassifier.isSuggestionCalendar(
                typeRawValue: event.calendar.type.rawValue
            ),
            eventIdentifier: event.eventIdentifier,
            attendees: CalendarEventClassifier.attendeeNames(others.map {
                (name: $0.name, url: $0.url, isPerson: $0.participantType != .room && $0.participantType != .resource)
            }),
            organizer: event.organizer.flatMap { organizer in
                organizer.isCurrentUser ? nil : CalendarEventClassifier.participantName(name: organizer.name, url: organizer.url)
            }
        )
    }

    private func deduplicatedMeetings(_ meetings: [Meeting]) -> [Meeting] {
        var seen = Set<String>()
        return meetings
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
            .filter { meeting in
                let key = [
                    meeting.title.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    ),
                    String(meeting.startDate.timeIntervalSince1970),
                    String(meeting.endDate.timeIntervalSince1970),
                    meeting.meetingURL?.absoluteString ?? ""
                ].joined(separator: "|")
                return seen.insert(key).inserted
            }
    }

    private func sourceSummaries(for calendars: [EKCalendar]) -> [CalendarSourceSummary] {
        let counts = calendars.reduce(into: [CalendarAccountKind: Int]()) { result, calendar in
            result[accountKind(for: calendar.source), default: 0] += 1
        }

        return CalendarAccountKind.allCases.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return CalendarSourceSummary(kind: kind, calendarCount: count)
        }
    }

    private func accountKind(for source: EKSource) -> CalendarAccountKind {
        let normalizedTitle = source.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if normalizedTitle.contains("google") || normalizedTitle.contains("gmail") {
            return .google
        }

        return switch source.sourceType {
        case .local: .local
        case .exchange: .exchange
        case .calDAV: .calDAV
        case .mobileMe: .iCloud
        case .subscribed: .subscribed
        case .birthdays: .other
        @unknown default: .other
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Pure EventKit-to-domain rules, kept separate so they can be unit tested.
enum CalendarEventClassifier {
    /// `EKCalendarType` 5 is the undocumented "Siri Suggestions" calendar, which holds
    /// events Siri found in Mail and Messages.
    static let siriSuggestionsCalendarTypeRawValue = 5

    static func kind(hasMeetingURL: Bool, otherAttendeeCount: Int) -> CalendarItemKind {
        if hasMeetingURL { return .onlineMeeting }
        return otherAttendeeCount > 0 ? .meeting : .event
    }

    static func isVisible(responseStatus: EKParticipantStatus?) -> Bool {
        responseStatus != .declined
    }

    static func responseStatus(_ status: EKParticipantStatus?) -> CalendarResponseStatus {
        switch status {
        case .accepted, .completed, .delegated, .inProcess: .accepted
        case .tentative: .tentative
        case .pending: .pending
        case .declined, .unknown, .none: .none
        @unknown default: .none
        }
    }

    /// A participant as people read it: the calendar's name, else the address from the
    /// `mailto:` URL.
    static func participantName(name: String?, url: URL?) -> String? {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        guard let url, url.scheme?.lowercased() == "mailto" else { return nil }
        let address = String(url.absoluteString.dropFirst("mailto:".count))
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return address?.isEmpty == false ? address : nil
    }

    /// The other people invited, in calendar order: rooms and resources left out, each
    /// name once.
    static func attendeeNames(_ participants: [(name: String?, url: URL?, isPerson: Bool)]) -> [String] {
        var seen = Set<String>()
        return participants.compactMap { participant in
            guard participant.isPerson,
                  let name = participantName(name: participant.name, url: participant.url),
                  seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    static func isSuggestionCalendar(typeRawValue: Int) -> Bool {
        typeRawValue == siriSuggestionsCalendarTypeRawValue
    }

    static func hexColor(_ color: CGColor) -> String? {
        guard let rgb = color.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ), let components = rgb.components, components.count >= 3 else { return nil }
        let channels = components.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
