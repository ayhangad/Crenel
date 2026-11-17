import XCTest
@testable import Crenel

final class MeetingPeopleTests: XCTestCase {
    func testShortNamesUpToTwoThenCounts() {
        XCTAssertNil(MeetingPeopleFormatter.short([]))
        XCTAssertNil(MeetingPeopleFormatter.short(["  "]))
        XCTAssertEqual(MeetingPeopleFormatter.short(["Deniz"]), "Deniz")
        XCTAssertEqual(MeetingPeopleFormatter.short(["Deniz", "Ece"]), "Deniz and Ece")
        XCTAssertEqual(MeetingPeopleFormatter.short(["Deniz", "Ece", "Mert"]), "Deniz, Ece and Mert")
        XCTAssertEqual(MeetingPeopleFormatter.short(["Deniz", "Ece", "Mert", "Ada"]), "Deniz, Ece and 2 others")
        XCTAssertEqual(MeetingPeopleFormatter.short(["Deniz", "", "Ece", "Mert", "Ada", "Can"]), "Deniz, Ece and 3 others")
    }

    func testWithYouCountAndInitials() {
        XCTAssertNil(MeetingPeopleFormatter.withYou([]))
        XCTAssertEqual(MeetingPeopleFormatter.withYou(["Deniz", "Ece"]), "Deniz, Ece, you")
        XCTAssertEqual(MeetingPeopleFormatter.withYou(["Deniz", "Ece", "Mert", "Ada", "Can"]), "Deniz, Ece, you and 3 others")

        XCTAssertNil(MeetingPeopleFormatter.count([]))
        XCTAssertEqual(MeetingPeopleFormatter.count(["Deniz", "Ece", "Mert", "Ada"]), "5 people")

        XCTAssertEqual(MeetingPeopleFormatter.initials(["deniz", "Ece", "Mert", "Ada"]), ["D", "E", "M", "+1"])
        XCTAssertEqual(MeetingPeopleFormatter.initials(["Deniz"]), ["D"])
    }

    func testParticipantNamesFallBackToTheAddressAndSkipRooms() {
        XCTAssertEqual(CalendarEventClassifier.participantName(name: " Deniz Kaya ", url: nil), "Deniz Kaya")
        XCTAssertEqual(CalendarEventClassifier.participantName(name: "", url: URL(string: "mailto:ece@example.com")),
                       "ece@example.com")
        XCTAssertNil(CalendarEventClassifier.participantName(name: nil, url: URL(string: "https://example.com")))

        let names = CalendarEventClassifier.attendeeNames([
            (name: "Deniz", url: URL(string: "mailto:deniz@example.com"), isPerson: true),
            (name: nil, url: URL(string: "mailto:ece@example.com"), isPerson: true),
            (name: "Room 4", url: URL(string: "mailto:room4@example.com"), isPerson: false),
            (name: "deniz", url: URL(string: "mailto:deniz2@example.com"), isPerson: true)
        ])
        XCTAssertEqual(names, ["Deniz", "ece@example.com"])
    }

    func testMeetingKeepsPeopleAndDecodesOldDocumentsWithout() throws {
        let meeting = Meeting(title: "Design review", startDate: Date(timeIntervalSince1970: 1_000),
                              endDate: Date(timeIntervalSince1970: 2_000),
                              attendees: ["Deniz", "Ece"], organizer: "Deniz")
        let decoded = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
        XCTAssertEqual(decoded.attendees, ["Deniz", "Ece"])
        XCTAssertEqual(decoded.organizer, "Deniz")

        let old = """
        {"id":"\(UUID().uuidString)","title":"Old","startDate":0,"endDate":60}
        """
        let legacy = try JSONDecoder().decode(Meeting.self, from: Data(old.utf8))
        XCTAssertEqual(legacy.attendees, [])
        XCTAssertNil(legacy.organizer)
    }

    func testReadySentenceCountsActionItems() {
        XCTAssertEqual(NotchClosedText.readySentence(actionItems: 3), "Notes and 3 action items")
        XCTAssertEqual(NotchClosedText.readySentence(actionItems: 1), "Notes and 1 action item")
        XCTAssertEqual(NotchClosedText.readySentence(actionItems: 0), "Notes are ready")
        XCTAssertEqual(NotchClosedText.readySentence(actionItems: nil), "Notes are ready")
    }
}
