import XCTest
@testable import Crenel

final class MeetingReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testMeetingOutsideTenMinutesIsNextButDoesNotTriggerReminder() {
        let snapshot = MeetingReminderSnapshot.evaluate(
            meetings: [meeting(startsIn: 601)],
            now: now
        )

        XCTAssertNotNil(snapshot.nextMeeting)
        XCTAssertEqual(snapshot.level, .none)
        XCTAssertNil(snapshot.presentationKey)
    }

    func testReminderEscalatesAtTenMinuteAndOneMinuteThresholds() {
        XCTAssertEqual(snapshot(startsIn: 600).level, .tenMinutes)
        XCTAssertEqual(snapshot(startsIn: 61).level, .tenMinutes)
        XCTAssertEqual(snapshot(startsIn: 60).level, .oneMinute)
        XCTAssertEqual(snapshot(startsIn: 1).level, .oneMinute)
        XCTAssertEqual(snapshot(startsIn: 0).level, .started)
    }

    func testEarliestNonEndedMeetingWins() {
        let ended = Meeting(
            title: "Bitti",
            startDate: now.addingTimeInterval(-300),
            endDate: now
        )
        let later = meeting(title: "Sonra", startsIn: 500)
        let earlier = meeting(title: "Önce", startsIn: 200)

        let snapshot = MeetingReminderSnapshot.evaluate(
            meetings: [later, ended, earlier],
            now: now
        )

        XCTAssertEqual(snapshot.nextMeeting?.title, "Önce")
        XCTAssertEqual(snapshot.level, .tenMinutes)
    }

    func testEachReminderLevelHasDistinctPresentationKey() {
        let event = meeting(startsIn: 60, externalIdentifier: "calendar-event")
        let tenMinute = MeetingReminderSnapshot(
            nextMeeting: event,
            level: .tenMinutes,
            secondsUntilStart: 600
        )
        let oneMinute = MeetingReminderSnapshot(
            nextMeeting: event,
            level: .oneMinute,
            secondsUntilStart: 60
        )

        XCTAssertNotEqual(tenMinute.presentationKey, oneMinute.presentationKey)
    }

    func testConfiguredLeadTimeChangesEarlyReminderThresholdButKeepsOneMinuteReminder() {
        let beforeFiveMinutes = MeetingReminderSnapshot.evaluate(
            meetings: [meeting(startsIn: 301)],
            now: now,
            reminderLeadTime: 5 * 60
        )
        let atFiveMinutes = MeetingReminderSnapshot.evaluate(
            meetings: [meeting(startsIn: 300)],
            now: now,
            reminderLeadTime: 5 * 60
        )
        let atOneMinute = MeetingReminderSnapshot.evaluate(
            meetings: [meeting(startsIn: 60)],
            now: now,
            reminderLeadTime: 5 * 60
        )

        XCTAssertEqual(beforeFiveMinutes.level, .none)
        XCTAssertEqual(atFiveMinutes.level, .tenMinutes)
        XCTAssertEqual(atOneMinute.level, .oneMinute)
    }

    private func snapshot(startsIn interval: TimeInterval) -> MeetingReminderSnapshot {
        .evaluate(meetings: [meeting(startsIn: interval)], now: now)
    }

    private func meeting(
        title: String = "Toplantı",
        startsIn interval: TimeInterval,
        externalIdentifier: String? = nil
    ) -> Meeting {
        Meeting(
            title: title,
            startDate: now.addingTimeInterval(interval),
            endDate: now.addingTimeInterval(interval + 1_800),
            externalIdentifier: externalIdentifier
        )
    }
}
