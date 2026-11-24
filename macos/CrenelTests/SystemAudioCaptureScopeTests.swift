import XCTest
@testable import Crenel

final class SystemAudioCaptureScopeTests: XCTestCase {
    private let resolver = MeetingAudioCaptureScopeResolver()

    func testZoomDetectionProducesOnlyItsVerifiedProcessObject() throws {
        let process = AudioProcessSnapshot(
            audioObjectID: 81,
            processID: 4_200,
            bundleIdentifier: "us.zoom.xos",
            isRunningInput: true,
            isRunningOutput: true
        )
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(
                state: .ready,
                confidence: .confirmed,
                clientID: .zoom,
                processID: process.processID
            ),
            audioProcess: process,
            client: nil
        )

        XCTAssertEqual(
            resolver.resolve(detection: detection, meeting: nil),
            .meetingProcesses([81])
        )
    }

    func testZoomRecordsSystemAudioWhenProcessDoesNotMatchSession() {
        let process = AudioProcessSnapshot(
            audioObjectID: 81,
            processID: 4_201,
            bundleIdentifier: "us.zoom.xos",
            isRunningInput: true,
            isRunningOutput: true
        )
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(clientID: .zoom, processID: 4_200),
            audioProcess: process,
            client: nil
        )

        XCTAssertEqual(resolver.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
    }

    func testGoogleMeetWithoutBridgeRecordsSystemAudioNotChromeProcess() {
        let process = AudioProcessSnapshot(
            audioObjectID: 91,
            processID: 5_200,
            bundleIdentifier: "com.google.Chrome",
            isRunningInput: true,
            isRunningOutput: true
        )
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(clientID: .googleMeetChrome, processID: process.processID),
            audioProcess: process,
            client: nil
        )

        XCTAssertEqual(resolver.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
    }

    func testGoogleMeetUsesBrowserTabOnlyWhenNativeBridgeIsActive() throws {
        let resolver = MeetingAudioCaptureScopeResolver(browserAudioAvailable: { true })
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(clientID: .googleMeetChrome, processID: 5_200),
            audioProcess: AudioProcessSnapshot(
                audioObjectID: 91,
                processID: 5_200,
                bundleIdentifier: "com.google.Chrome",
                isRunningInput: true,
                isRunningOutput: true
            ),
            client: nil
        )

        XCTAssertEqual(
            resolver.resolve(detection: detection, meeting: nil),
            .browserTab
        )
    }

    func testCalendarLinkAloneDoesNotBlockRecordingAnotherCall() throws {
        // A Slack huddle while a Zoom or Meet event sits in the calendar.
        let zoomMeeting = Meeting(
            title: "Zoom",
            startDate: .now,
            endDate: .now.addingTimeInterval(1_800),
            meetingURL: URL(string: "https://acme.zoom.us/j/123")
        )
        let meetMeeting = Meeting(
            title: "Meet",
            startDate: .now,
            endDate: .now.addingTimeInterval(1_800),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )

        XCTAssertEqual(resolver.resolve(detection: nil, meeting: zoomMeeting), .explicitManualGlobal)
        XCTAssertEqual(resolver.resolve(detection: nil, meeting: meetMeeting), .explicitManualGlobal)
    }

    func testEndedSessionNoLongerScopesTheNextRecording() throws {
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(state: .ended, clientID: .zoom, processID: 4_200),
            audioProcess: nil,
            client: nil
        )

        XCTAssertEqual(resolver.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
    }

    func testIdleZoomInTheBackgroundIsNotACall() throws {
        let process = AudioProcessSnapshot(
            audioObjectID: 81,
            processID: 4_200,
            bundleIdentifier: "us.zoom.xos",
            isRunningInput: false,
            isRunningOutput: false
        )
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(state: .candidate, clientID: .zoom, processID: process.processID),
            audioProcess: process,
            client: clientSnapshot(.zoom, processID: process.processID, inCall: false)
        )

        XCTAssertEqual(resolver.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
    }

    func testChromePlayingAudioWithoutAMeetCallUsesGlobalScope() throws {
        // Slack in a Chrome tab, or a video, while Chrome is readable and shows no Meet call.
        let process = AudioProcessSnapshot(
            audioObjectID: 91,
            processID: 5_200,
            bundleIdentifier: "com.google.Chrome",
            isRunningInput: true,
            isRunningOutput: true
        )
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(state: .candidate, clientID: .googleMeetChrome, processID: process.processID),
            audioProcess: process,
            client: clientSnapshot(.googleMeetChrome, processID: process.processID, inCall: false)
        )

        XCTAssertEqual(resolver.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
    }

    func testVisibleMeetCallWithoutTheBridgeStillRecords() {
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(state: .ready, clientID: .googleMeetChrome, processID: 5_200),
            audioProcess: nil,
            client: clientSnapshot(.googleMeetChrome, processID: 5_200, inCall: true)
        )

        XCTAssertEqual(resolver.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
        XCTAssertEqual(
            MeetingAudioCaptureScopeResolver(browserAudioAvailable: { true })
                .resolve(detection: detection, meeting: nil),
            .browserTab
        )
    }

    func testUnreadableChromeUsesTheBridgeOnlyWhenTheCalendarSaysMeet() throws {
        let unreadable = MeetingClientSnapshot(
            clientID: .googleMeetChrome,
            processID: 5_200,
            availability: .accessibilityPermissionRequired,
            meetingWindowPresent: false,
            callControlsPresent: false,
            microphoneState: .unknown
        )
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(state: .candidate, clientID: .googleMeetChrome, processID: 5_200),
            audioProcess: nil,
            client: unreadable
        )
        let meetMeeting = Meeting(
            title: "Meet",
            startDate: .now,
            endDate: .now.addingTimeInterval(1_800),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )

        let bridged = MeetingAudioCaptureScopeResolver(browserAudioAvailable: { true })
        XCTAssertEqual(bridged.resolve(detection: detection, meeting: nil), .explicitManualGlobal)
        XCTAssertEqual(bridged.resolve(detection: detection, meeting: meetMeeting), .browserTab)
        XCTAssertEqual(resolver.resolve(detection: detection, meeting: meetMeeting), .explicitManualGlobal)
    }

    private func clientSnapshot(_ client: MeetingClientID, processID: Int32, inCall: Bool) -> MeetingClientSnapshot {
        MeetingClientSnapshot(
            clientID: client,
            processID: processID,
            availability: .available,
            meetingWindowPresent: inCall,
            callControlsPresent: inCall,
            microphoneState: inCall ? .open : .unknown
        )
    }

    func testExplicitManualRecordingWithoutSupportedMeetingUsesGlobalScope() throws {
        XCTAssertEqual(
            resolver.resolve(detection: nil, meeting: nil),
            .explicitManualGlobal
        )
    }

    func testMeetingProcessScopeNormalizesInvalidAndDuplicateObjectIDs() {
        XCTAssertEqual(
            SystemAudioCaptureScope.meetingProcesses([7, 0, 7, 3]).includedProcessObjectIDs,
            [3, 7]
        )
    }

    func testPipelineHeartbeatTreatsAdvancingSilentFramesAsHealthy() {
        var heartbeat = AudioPipelineHeartbeat(unchangedPollLimit: 2)

        XCTAssertNil(heartbeat.observe(capturedFrameCount: 0))
        XCTAssertNil(heartbeat.observe(capturedFrameCount: 480))
        XCTAssertNil(heartbeat.observe(capturedFrameCount: 960))
        XCTAssertFalse(heartbeat.isStalled)
    }

    func testPipelineHeartbeatReportsStallOnlyAfterUnchangedLimit() {
        var heartbeat = AudioPipelineHeartbeat(unchangedPollLimit: 2)

        XCTAssertNil(heartbeat.observe(capturedFrameCount: 480))
        XCTAssertNil(heartbeat.observe(capturedFrameCount: 480))
        XCTAssertEqual(
            heartbeat.observe(capturedFrameCount: 480),
            .pipelineStalled
        )
        XCTAssertNil(heartbeat.observe(capturedFrameCount: 480))
    }

    func testPipelineHeartbeatReportsRecoveryWhenFramesResume() {
        var heartbeat = AudioPipelineHeartbeat(unchangedPollLimit: 1)

        XCTAssertNil(heartbeat.observe(capturedFrameCount: 100))
        XCTAssertEqual(heartbeat.observe(capturedFrameCount: 100), .pipelineStalled)
        XCTAssertEqual(heartbeat.observe(capturedFrameCount: 200), .pipelineRecovered)
        XCTAssertFalse(heartbeat.isStalled)
    }

    func testPipelineHeartbeatFailsImmediatelyOnWriterError() {
        var heartbeat = AudioPipelineHeartbeat(unchangedPollLimit: 30)

        XCTAssertEqual(
            heartbeat.observe(capturedFrameCount: 100, hasWriteError: true),
            .pipelineStalled
        )
        XCTAssertTrue(heartbeat.isStalled)
    }
}
