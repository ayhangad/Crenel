import EventKit
import XCTest
@testable import MeetingNotch

final class NotchAgendaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    func testNoItemsResolvesToNil() {
        XCTAssertNil(NotchAgendaStatus.resolve(items: [], now: now))
    }

    func testNextItemWithinHorizonCountsDown() {
        let event = item("Diş hekimi", startsIn: 25 * 60, kind: .event)
        let status = NotchAgendaStatus.resolve(items: [event], now: now)
        XCTAssertEqual(status, NotchAgendaStatus(item: event, phase: .upcoming(startsIn: 25 * 60)))
        XCTAssertEqual(status?.urgency, .calm)
    }

    func testItemBeyondHorizonIsHidden() {
        let event = item("Yarın", startsIn: 13 * 60 * 60)
        XCTAssertNil(NotchAgendaStatus.resolve(items: [event], now: now))
    }

    func testAllDayItemsNeverCountDown() {
        let holiday = item("Tatil", startsIn: 60, isAllDay: true)
        XCTAssertNil(NotchAgendaStatus.resolve(items: [holiday], now: now))
    }

    func testOngoingItemShowsRemainingTime() {
        let ongoing = item("Odak", startsIn: -10 * 60, duration: 40 * 60)
        let status = NotchAgendaStatus.resolve(items: [ongoing], now: now)
        XCTAssertEqual(status, NotchAgendaStatus(item: ongoing, phase: .ongoing(remaining: 30 * 60)))
    }

    func testNextItemTakesOverOngoingWithinHandoff() {
        let ongoing = item("Odak", startsIn: -30 * 60, duration: 60 * 60)
        let next = item("Planlama", startsIn: 8 * 60)
        let status = NotchAgendaStatus.resolve(items: [ongoing, next], now: now)
        XCTAssertEqual(status?.item, next)
        XCTAssertEqual(status?.urgency, .soon)
    }

    func testOngoingItemWinsUntilHandoff() {
        let ongoing = item("Odak", startsIn: -30 * 60, duration: 60 * 60)
        let next = item("Planlama", startsIn: 40 * 60)
        XCTAssertEqual(NotchAgendaStatus.resolve(items: [ongoing, next], now: now)?.item, ongoing)
    }

    func testMostRecentlyStartedOverlappingItemIsShown() {
        let long = item("Gün boyu atölye", startsIn: -3 * 60 * 60, duration: 6 * 60 * 60)
        let recent = item("Ara toplantı", startsIn: -5 * 60, duration: 30 * 60)
        XCTAssertEqual(NotchAgendaStatus.resolve(items: [long, recent], now: now)?.item, recent)
    }

    func testImminentUrgencyInLastMinute() {
        let meeting = item("Standup", startsIn: 45)
        XCTAssertEqual(NotchAgendaStatus.resolve(items: [meeting], now: now)?.urgency, .imminent)
    }

    func testCompactTextFormats() {
        func text(_ phase: NotchAgendaStatus.Phase, start: TimeInterval = 0) -> String {
            NotchAgendaFormatter.compactText(
                for: NotchAgendaStatus(item: item("x", startsIn: start), phase: phase),
                calendar: calendar
            )
        }
        XCTAssertEqual(text(.upcoming(startsIn: 30)), "<1 min")
        XCTAssertEqual(text(.upcoming(startsIn: 12 * 60)), "12 min")
        XCTAssertEqual(text(.upcoming(startsIn: 11 * 60 + 5)), "12 min")
        XCTAssertEqual(text(.upcoming(startsIn: 60 * 60)), "1 h")
        XCTAssertEqual(text(.upcoming(startsIn: 65 * 60)), "1 h 5 min")
        XCTAssertEqual(text(.ongoing(remaining: 25 * 60)), "25 min left")
        XCTAssertEqual(text(.ongoing(remaining: 20)), "Ending")
        // 1_800_000_000 + 4h is 15:00 in Istanbul (UTC+3).
        XCTAssertEqual(text(.upcoming(startsIn: 4 * 60 * 60), start: 4 * 60 * 60), "15:00")
    }

    func testCompactStatusPrefersAgendaOverTasks() {
        let event = item("Kahve", startsIn: 5 * 60, kind: .event)
        let status = NotchStatusResolver.compactStatus(
            flow: .idle,
            nextMeeting: nil,
            activeTaskCount: 3,
            agendaItems: [event],
            now: now
        )
        XCTAssertEqual(status, .agenda(NotchAgendaStatus(item: event, phase: .upcoming(startsIn: 300))))
    }

    func testClassifierKinds() {
        XCTAssertEqual(CalendarEventClassifier.kind(hasMeetingURL: true, otherAttendeeCount: 0), .onlineMeeting)
        XCTAssertEqual(CalendarEventClassifier.kind(hasMeetingURL: false, otherAttendeeCount: 2), .meeting)
        XCTAssertEqual(CalendarEventClassifier.kind(hasMeetingURL: false, otherAttendeeCount: 0), .event)
    }

    func testClassifierResponseAndVisibility() {
        XCTAssertFalse(CalendarEventClassifier.isVisible(responseStatus: .declined))
        XCTAssertTrue(CalendarEventClassifier.isVisible(responseStatus: .pending))
        XCTAssertTrue(CalendarEventClassifier.isVisible(responseStatus: nil))
        XCTAssertEqual(CalendarEventClassifier.responseStatus(.pending), .pending)
        XCTAssertEqual(CalendarEventClassifier.responseStatus(.tentative), .tentative)
        XCTAssertEqual(CalendarEventClassifier.responseStatus(.accepted), .accepted)
        XCTAssertEqual(CalendarEventClassifier.responseStatus(nil), .none)
        XCTAssertTrue(CalendarEventClassifier.isSuggestionCalendar(typeRawValue: 5))
        XCTAssertFalse(CalendarEventClassifier.isSuggestionCalendar(typeRawValue: EKCalendarType.calDAV.rawValue))
    }

    func testOnlyMeetingsAreReminderCandidates() {
        XCTAssertTrue(item("Toplantı", startsIn: 0, kind: .onlineMeeting).isReminderCandidate)
        XCTAssertTrue(item("Yüz yüze", startsIn: 0, kind: .meeting).isReminderCandidate)
        XCTAssertFalse(item("Spor", startsIn: 0, kind: .event).isReminderCandidate)
        XCTAssertFalse(item("Tüm gün", startsIn: 0, kind: .meeting, isAllDay: true).isReminderCandidate)
    }

    func testLegacyMeetingJSONDecodesAsOnlineMeeting() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"Eski","startDate":0,"endDate":60,"meetingURL":"https://meet.google.com/abc-defg-hij"}
        """
        let meeting = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
        XCTAssertEqual(meeting.kind, .onlineMeeting)
        XCTAssertFalse(meeting.isAllDay)
        XCTAssertEqual(meeting.responseStatus, .none)
    }

    func testCalendarAppLinkUsesEventIdentifier() {
        var event = item("x", startsIn: 0)
        event.eventIdentifier = "ABC:123"
        XCTAssertEqual(CalendarAppLink.url(for: event)?.absoluteString, "ical://ekevent/ABC:123?method=show&options=more")
    }

    private func item(
        _ title: String,
        startsIn: TimeInterval,
        duration: TimeInterval = 30 * 60,
        kind: CalendarItemKind = .meeting,
        isAllDay: Bool = false
    ) -> Meeting {
        Meeting(
            id: MeetingStableIdentifier.uuid(for: title + "\(startsIn)"),
            title: title,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + duration),
            kind: kind,
            isAllDay: isAllDay
        )
    }
}
