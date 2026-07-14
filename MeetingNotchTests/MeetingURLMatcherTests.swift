import XCTest
@testable import MeetingNotch

final class MeetingURLMatcherTests: XCTestCase {
    private let matcher = MeetingURLMatcher()

    func testRecognizesZoomGoogleMeetAndMicrosoftTeamsHosts() {
        XCTAssertTrue(matcher.isSupported(URL(string: "https://ACME.ZOOM.US/j/123")!))
        XCTAssertTrue(matcher.isSupported(URL(string: "https://meet.google.com/abc-defg-hij")!))
        XCTAssertTrue(matcher.isSupported(URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!))
    }

    func testRejectsLookalikeAndUnsupportedHosts() {
        XCTAssertFalse(matcher.isSupported(URL(string: "https://zoom.us.example.com/j/123")!))
        XCTAssertFalse(matcher.isSupported(URL(string: "https://example.com/meeting")!))
    }

    func testUsesExplicitURLThenLocationThenNotes() {
        let explicit = URL(string: "https://zoom.us/j/111")!
        let match = matcher.firstMeetingURL(
            explicitURL: explicit,
            location: "https://meet.google.com/location-room",
            notes: "https://teams.microsoft.com/l/meetup-join/notes-room"
        )

        XCTAssertEqual(match, explicit)
    }

    func testFallsBackToLocationWhenExplicitURLIsUnsupported() {
        let match = matcher.firstMeetingURL(
            explicitURL: URL(string: "https://example.com")!,
            location: "Katıl: https://meet.google.com/abc-defg-hij",
            notes: "https://zoom.us/j/222"
        )

        XCTAssertEqual(match?.host, "meet.google.com")
    }

    func testDecodesEncodedURLAndPreservesTrackingParameters() {
        let matches = matcher.meetingURLs(
            in: "https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc%3Futm_source%3Dcalendar"
        )

        XCTAssertEqual(matches.first?.host, "teams.microsoft.com")
        XCTAssertEqual(matches.first?.query, "utm_source=calendar")
    }

    func testChoosesFirstSupportedLinkInTheSameField() {
        let matches = matcher.meetingURLs(
            in: "Önce https://example.com sonra https://zoom.us/j/123 ve https://meet.google.com/abc-defg-hij"
        )

        XCTAssertEqual(matches.map(\.host), ["zoom.us", "meet.google.com"])
    }
}
