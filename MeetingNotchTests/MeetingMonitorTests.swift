import XCTest
@testable import MeetingNotch

@MainActor
final class MeetingMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testAuthorizedRefreshPublishesConnectionHealthAndReminder() async {
        let meeting = Meeting(
            title: "Planlama",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(1_860),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        let provider = CalendarProviderStub(
            authorization: .authorized,
            result: CalendarMeetingQueryResult(
                meetings: [meeting],
                sources: [CalendarSourceSummary(kind: .google, calendarCount: 3)],
                scannedEventCount: 7
            )
        )
        let monitor = MeetingMonitor(provider: provider, now: { self.now })
        var connection: CalendarIntegrationSnapshot?
        var reminder: MeetingReminderSnapshot?
        var upcomingMeetings: [Meeting] = []
        var refreshStates: [Bool] = []
        monitor.onIntegrationSnapshotChange = { connection = $0 }
        monitor.onSnapshotChange = { snapshot, _ in reminder = snapshot }
        monitor.onMeetingsChange = { upcomingMeetings = $0 }
        monitor.onRefreshStateChange = { refreshStates.append($0) }

        await monitor.refresh()

        XCTAssertEqual(connection?.sources.first?.kind, .google)
        XCTAssertEqual(connection?.readableCalendarCount, 3)
        XCTAssertEqual(connection?.scannedEventCount, 7)
        XCTAssertEqual(connection?.matchedMeetingCount, 1)
        XCTAssertEqual(connection?.refreshedAt, now)
        XCTAssertEqual(reminder?.nextMeeting, meeting)
        XCTAssertEqual(reminder?.level, .oneMinute)
        XCTAssertEqual(upcomingMeetings, [meeting])
        XCTAssertEqual(refreshStates, [true, false])
    }

    func testDeniedRefreshClearsConnectionAndDoesNotQueryEvents() async {
        let provider = CalendarProviderStub(authorization: .denied)
        let monitor = MeetingMonitor(provider: provider, now: { self.now })
        var accessState: CalendarAccessState?
        var receivedConnectionCallback = false
        var connection: CalendarIntegrationSnapshot?
        monitor.onAccessStateChange = { accessState = $0 }
        monitor.onIntegrationSnapshotChange = {
            receivedConnectionCallback = true
            connection = $0
        }

        await monitor.refresh()

        XCTAssertEqual(accessState, .denied)
        XCTAssertTrue(receivedConnectionCallback)
        XCTAssertNil(connection)
        let queryCount = await provider.queryCount
        XCTAssertEqual(queryCount, 0)
    }

    func testExplicitAccessRequestStillWorksWhileCalendarMonitoringIsDisabled() async {
        let provider = CalendarProviderStub(authorization: .notDetermined, accessGranted: true)
        let monitor = MeetingMonitor(provider: provider, now: { self.now })
        var states: [CalendarAccessState] = []
        monitor.onAccessStateChange = { states.append($0) }
        monitor.configure(isEnabled: false, reminderLeadTime: 600)

        await monitor.requestAccess()

        XCTAssertEqual(Array(states.suffix(2)), [.requesting, .authorized])
        let requestCount = await provider.requestCount
        let queryCount = await provider.queryCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(queryCount, 0)
    }

    func testBurstRefreshesAreCoalescedIntoOneFollowUpQuery() async {
        let provider = CalendarProviderStub(
            authorization: .authorized,
            queryDelay: .milliseconds(80)
        )
        let monitor = MeetingMonitor(provider: provider, now: { self.now })
        let twoQueries = expectation(description: "initial and coalesced refresh")
        twoQueries.expectedFulfillmentCount = 2
        monitor.onIntegrationSnapshotChange = { _ in twoQueries.fulfill() }

        for _ in 0..<10 {
            Task { await monitor.refresh() }
        }

        await fulfillment(of: [twoQueries], timeout: 2)
        let queryCount = await provider.queryCount
        XCTAssertEqual(queryCount, 2)
    }

    func testQueryFailureClearsStaleUpcomingMeetingAndPublishesRecoverableState() async {
        let provider = CalendarProviderStub(
            authorization: .authorized,
            queryError: CalendarProviderStub.TestError.queryFailed
        )
        let monitor = MeetingMonitor(provider: provider, now: { self.now })
        var accessState: CalendarAccessState?
        var meetings = [Meeting(
            title: "Eski",
            startDate: now,
            endDate: now.addingTimeInterval(60)
        )]
        var reminder: MeetingReminderSnapshot?
        monitor.onAccessStateChange = { accessState = $0 }
        monitor.onMeetingsChange = { meetings = $0 }
        monitor.onSnapshotChange = { snapshot, _ in reminder = snapshot }

        await monitor.refresh()

        XCTAssertEqual(accessState, .failed("Couldn’t read upcoming events."))
        XCTAssertTrue(meetings.isEmpty)
        XCTAssertNil(reminder?.nextMeeting)
    }
}

private actor CalendarProviderStub: CalendarMeetingProviding {
    enum TestError: Error {
        case queryFailed
    }

    let authorization: CalendarAccessState
    let accessGranted: Bool
    let result: CalendarMeetingQueryResult
    let queryDelay: Duration?
    let queryError: TestError?
    private(set) var requestCount = 0
    private(set) var queryCount = 0

    init(
        authorization: CalendarAccessState,
        accessGranted: Bool = false,
        queryDelay: Duration? = nil,
        queryError: TestError? = nil,
        result: CalendarMeetingQueryResult = CalendarMeetingQueryResult(
            meetings: [],
            sources: [],
            scannedEventCount: 0
        )
    ) {
        self.authorization = authorization
        self.accessGranted = accessGranted
        self.queryDelay = queryDelay
        self.queryError = queryError
        self.result = result
    }

    func authorizationState() -> CalendarAccessState {
        authorization
    }

    func requestAccess() -> Bool {
        requestCount += 1
        return accessGranted
    }

    func query(from startDate: Date, to endDate: Date) async throws -> CalendarMeetingQueryResult {
        queryCount += 1
        if let queryDelay {
            try await Task.sleep(for: queryDelay)
        }
        if let queryError {
            throw queryError
        }
        return result
    }
}
