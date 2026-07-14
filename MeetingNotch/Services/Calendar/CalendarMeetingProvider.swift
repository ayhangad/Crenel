import EventKit
import Foundation

protocol CalendarMeetingProviding: Sendable {
    func authorizationState() async -> CalendarAccessState
    func requestAccess() async throws -> Bool
    func meetings(from startDate: Date, to endDate: Date) async throws -> [Meeting]
}

actor EventKitMeetingProvider: CalendarMeetingProviding {
    private let eventStore: EKEventStore
    private let urlMatcher: MeetingURLMatcher

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

    func meetings(from startDate: Date, to endDate: Date) -> [Meeting] {
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .filter(isRelevantEvent)
            .compactMap(makeMeeting)
            .sorted { $0.startDate < $1.startDate }
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
            event.eventIdentifier ?? "event",
            String(occurrence?.timeIntervalSince1970 ?? 0)
        ].joined(separator: "|")

        return Meeting(
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "İsimsiz Toplantı",
            startDate: event.startDate,
            endDate: event.endDate,
            meetingURL: meetingURL,
            calendarIdentifier: event.calendar.calendarIdentifier,
            externalIdentifier: sourceIdentifier
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
