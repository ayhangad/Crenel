import EventKit
import Foundation

protocol CalendarMeetingProviding: Sendable {
    func selectSource(_ kind: CalendarConnectionKind) async
    func selectCalendars(_ ids: [String]?) async
    func authorizationState() async -> CalendarAccessState
    func requestAccess() async throws -> Bool
    func query(from startDate: Date, to endDate: Date) async throws -> CalendarMeetingQueryResult
}

extension CalendarMeetingProviding {
    func selectSource(_ kind: CalendarConnectionKind) async {}
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
        guard !event.isAllDay, event.status != .canceled else { return false }

        let currentUserDeclined = event.attendees?
            .first(where: \.isCurrentUser)?
            .participantStatus == .declined

        return !currentUserDeclined
    }

    private func makeMeeting(from event: EKEvent) -> Meeting? {
        guard let meetingURL = urlMatcher.firstMeetingURL(
            explicitURL: event.url,
            location: event.location,
            notes: event.notes
        ) else {
            return nil
        }

        let occurrence = event.occurrenceDate ?? event.startDate
        let sourceIdentifier = [
            event.calendar.calendarIdentifier,
            event.eventIdentifier ?? "event",
            String(occurrence?.timeIntervalSince1970 ?? 0)
        ].joined(separator: "|")

        return Meeting(
            id: MeetingStableIdentifier.uuid(for: sourceIdentifier),
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "İsimsiz Toplantı",
            startDate: event.startDate,
            endDate: event.endDate,
            meetingURL: meetingURL,
            calendarIdentifier: event.calendar.calendarIdentifier,
            externalIdentifier: sourceIdentifier
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
