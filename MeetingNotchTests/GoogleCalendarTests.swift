import XCTest
@testable import MeetingNotch

final class GoogleCalendarTests: XCTestCase {
    func testGoogleRefreshesTokenAndHonorsEmptyCalendarSelectionThroughRouter() async throws {
        let keys = GoogleTokenFixture()
        let http = GoogleHTTPFixture()
        let provider = GoogleCalendarProvider(configuration: .init(clientID: "fixture.apps.googleusercontent.com", clientSecret: ""), keys: keys, http: http)
        let router = CalendarProviderRouter(google: provider)
        await router.selectSource(.google)
        await router.selectCalendars([])
        let result = try await router.query(from: .now, to: Date().addingTimeInterval(86400))
        XCTAssertTrue(result.meetings.isEmpty)
        XCTAssertEqual(result.calendars.map(\.id), ["google:work", "google:personal"])
        let requests = await http.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.first?.url?.host, "oauth2.googleapis.com")
        XCTAssertTrue(requests.last?.url?.query?.contains("pageToken=next") == true)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
        let keyValue = await keys.value
        let saved = try XCTUnwrap(keyValue)
        XCTAssertTrue(saved.contains("refresh-fixture"))
        try await provider.disconnect()
        let state = await router.authorizationState()
        XCTAssertEqual(state, .notDetermined)
    }

    func testPKCEUsesRFC7636SHA256Challenge() {
        XCTAssertEqual(GoogleOAuthSession.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testOAuthRejectsWrongStatePathAndDuplicateCodes() throws {
        XCTAssertEqual(try GoogleOAuthSession.callbackCode(requestLine: "GET /oauth/callback?state=nonce&code=abc%2Bdef HTTP/1.1", expectedState: "nonce"), "abc+def")
        for target in ["/oauth/callback?state=wrong&code=a", "/elsewhere?state=nonce&code=a",
                       "/oauth/callback?state=nonce&code=a&code=b", "/oauth/callback?state=nonce&error=access_denied"] {
            XCTAssertThrowsError(try GoogleOAuthSession.callbackCode(requestLine: "GET \(target) HTTP/1.1", expectedState: "nonce"))
        }
    }

    func testGoogleEventDecodesMeetLinkAndKeepsOccurrenceIDStable() throws {
        let data = Data("""
        {"id":"event1","summary":"Ürün Review","status":"confirmed",
         "start":{"dateTime":"2026-09-14T12:00:00+03:00"},"end":{"dateTime":"2026-09-14T13:00:00+03:00"},
         "conferenceData":{"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/abc-defg-hij"}]}}
        """.utf8)
        let event = try JSONDecoder().decode(GoogleCalendarProvider.Event.self, from: data)
        let meeting = try XCTUnwrap(GoogleCalendarProvider.meeting(from: event, calendarID: "cal"))
        XCTAssertEqual(meeting.meetingURL?.host, "meet.google.com")
        XCTAssertEqual(meeting.title, "Ürün Review")
        XCTAssertEqual(meeting.id, GoogleCalendarProvider.meeting(from: event, calendarID: "cal")?.id)
        XCTAssertEqual(meeting.endDate.timeIntervalSince(meeting.startDate), 3600)
    }

    func testGoogleIgnoresDeclinedAndAllDayEvents() throws {
        for json in [
            """
            {"id":"1","start":{"date":"2026-09-14"},"end":{"date":"2026-09-15"},"hangoutLink":"https://meet.google.com/abc-defg-hij"}
            """,
            """
            {"id":"1","start":{"dateTime":"2026-09-14T09:00:00Z"},"end":{"dateTime":"2026-09-14T10:00:00Z"},"hangoutLink":"https://meet.google.com/abc-defg-hij","attendees":[{"self":true,"responseStatus":"declined"}]}
            """
        ] {
            let event = try JSONDecoder().decode(GoogleCalendarProvider.Event.self, from: Data(json.utf8))
            XCTAssertNil(GoogleCalendarProvider.meeting(from: event, calendarID: "cal"))
        }
    }

    func testRecordingContextRejectsTomorrowAndAmbiguousMeetings() {
        let now = Date()
        let meeting = Meeting(title: "Tomorrow", startDate: now.addingTimeInterval(86400), endDate: now.addingTimeInterval(90000))
        XCTAssertNil(RecordingMeetingContext.resolve(meetings: [meeting], session: nil, now: now))
        let current = Meeting(title: "Now", startDate: now.addingTimeInterval(-60), endDate: now.addingTimeInterval(600))
        XCTAssertEqual(RecordingMeetingContext.resolve(meetings: [current, meeting], session: nil, now: now)?.id, current.id)
        var overlap = current
        overlap = Meeting(title: "Other", startDate: current.startDate, endDate: current.endDate)
        XCTAssertNil(RecordingMeetingContext.resolve(meetings: [current, overlap], session: nil, now: now))
    }
}

private actor GoogleTokenFixture: APIKeyRepository {
    var value: String? = "{\"accessToken\":\"expired\",\"expiresAt\":0,\"refreshToken\":\"refresh-fixture\"}"
    func apiKey() -> String? { value }
    func saveAPIKey(_ apiKey: String) { value = apiKey }
    func deleteAPIKey() { value = nil }
}

private actor GoogleHTTPFixture: TranscriptionHTTPClient {
    var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> TranscriptionHTTPResponse {
        requests.append(request)
        let json: String
        if request.url?.host == "oauth2.googleapis.com" {
            json = "{\"access_token\":\"refreshed\",\"expires_in\":3600}"
        } else if request.url?.query?.contains("pageToken=next") == true {
            json = "{\"items\":[{\"id\":\"personal\",\"summary\":\"Personal\"}]}"
        } else {
            json = "{\"items\":[{\"id\":\"work\",\"summary\":\"Work\"}],\"nextPageToken\":\"next\"}"
        }
        return .init(data: Data(json.utf8), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func upload(for request: URLRequest, fromFile fileURL: URL, progress: @escaping TranscriptionUploadProgress) async throws -> TranscriptionHTTPResponse {
        throw GoogleCalendarError.invalidResponse
    }
}
