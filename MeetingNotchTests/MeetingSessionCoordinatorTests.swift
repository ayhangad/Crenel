import CoreAudio
import XCTest
@testable import MeetingNotch

final class MeetingSessionCoordinatorTests: XCTestCase {
    func testCalendarContextAloneRemainsScheduledAndUnknown() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let coordinator = makeCoordinator(monitor: monitor)
        await coordinator.start { await recorder.append($0) }

        let now = Date(timeIntervalSince1970: 1_000)
        await coordinator.updateCalendarMeeting(
            meeting(
                externalIdentifier: "calendar-1",
                url: URL(string: "https://zoom.us/j/123")!,
                startDate: now.addingTimeInterval(-60),
                endDate: now.addingTimeInterval(60)
            ),
            at: now
        )

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .scheduled)
        XCTAssertEqual(snapshot?.session.confidence, .unknown)
        XCTAssertEqual(snapshot?.session.calendarMeetingID, "calendar-1")
        await coordinator.stop()
    }

    func testJoinAndProcessAudioWithoutClientUIAreOnlyProbable() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let coordinator = makeCoordinator(monitor: monitor)
        await coordinator.start { await recorder.append($0) }

        let url = URL(string: "https://zoom.us/j/123")!
        await coordinator.recordJoinAction(meeting: nil, url: url)
        await monitor.emit([
            process(
                objectID: 10,
                processID: 42,
                bundleIdentifier: "us.zoom.xos",
                input: true,
                output: true
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .candidate)
        XCTAssertEqual(snapshot?.session.confidence, .probable)
        XCTAssertEqual(snapshot?.session.processID, 42)
        XCTAssertEqual(snapshot?.session.clientID, .zoom)
        await coordinator.stop()
    }

    func testMeetingControlsAndProcessConfirmReadySession() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = StubMeetingClientAdapter(snapshots: [
            84: client(
                clientID: .googleMeetChrome,
                processID: 84,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        ])
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }

        await monitor.emit([
            process(
                objectID: 20,
                processID: 84,
                bundleIdentifier: "com.google.Chrome",
                input: true,
                output: true
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .ready)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        XCTAssertEqual(snapshot?.session.clientID, .googleMeetChrome)
        XCTAssertEqual(snapshot?.microphoneState, .closed)
        await coordinator.stop()
    }

    func testJoinURLSelectsMatchingClientWhenMultipleProcessesAreActive() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let coordinator = makeCoordinator(monitor: monitor)
        await coordinator.start { await recorder.append($0) }

        await coordinator.recordJoinAction(
            meeting: nil,
            url: URL(string: "https://meet.google.com/abc-defg-hij")!
        )
        await monitor.emit([
            process(
                objectID: 10,
                processID: 42,
                bundleIdentifier: "us.zoom.xos",
                input: true,
                output: true
            ),
            process(
                objectID: 20,
                processID: 84,
                bundleIdentifier: "com.google.Chrome",
                input: true,
                output: true
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.audioProcess?.processID, 84)
        XCTAssertEqual(snapshot?.session.clientID, .googleMeetChrome)
        await coordinator.stop()
    }

    func testProcessAudioAndClientDisappearanceConfirmRecordedSessionEnd() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = StubMeetingClientAdapter(snapshots: [
            42: client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .open
            )
        ])
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }
        await monitor.emit([
            process(
                objectID: 10,
                processID: 42,
                bundleIdentifier: "us.zoom.xos",
                input: true,
                output: true
            )
        ])
        await coordinator.recordingStarted()

        await monitor.emit([])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .ended)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        XCTAssertNil(snapshot?.audioProcess)
        XCTAssertNil(snapshot?.client)
        await coordinator.stop()
    }

    func testOrdinaryIdleChromeIsIgnoredWithoutMeetingContext() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let coordinator = makeCoordinator(monitor: monitor)
        await coordinator.start { await recorder.append($0) }

        await monitor.emit([
            process(
                objectID: 20,
                processID: 84,
                bundleIdentifier: "com.google.Chrome",
                input: false,
                output: false
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.evidence, [])
        XCTAssertNil(snapshot?.audioProcess)
        await coordinator.stop()
    }

    func testUnplannedMeetingCanBeConfirmedWithoutCalendarContext() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = MutableMeetingClientAdapter()
        adapter.setSnapshot(
            client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        )
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }

        await monitor.emit([activeZoomProcess()])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .ready)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        XCTAssertNil(snapshot?.session.calendarMeetingID)
        await coordinator.stop()
    }

    func testLateMeetingStillUsesClientEvidenceAfterCalendarWindow() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = MutableMeetingClientAdapter()
        adapter.setSnapshot(
            client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .open
            )
        )
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }
        let now = Date(timeIntervalSince1970: 3_000)
        await coordinator.updateCalendarMeeting(
            meeting(
                externalIdentifier: "late-calendar",
                url: URL(string: "https://zoom.us/j/late")!,
                startDate: now.addingTimeInterval(-3_600),
                endDate: now.addingTimeInterval(-1_800)
            ),
            at: now
        )

        await monitor.emit([activeZoomProcess()])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .ready)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        XCTAssertEqual(snapshot?.session.calendarMeetingID, "late-calendar")
        await coordinator.stop()
    }

    func testEarlyJoinBeforeCalendarWindowCanBeConfirmed() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = MutableMeetingClientAdapter()
        adapter.setSnapshot(
            client(
                clientID: .googleMeetChrome,
                processID: 84,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        )
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }
        let now = Date(timeIntervalSince1970: 4_000)
        let earlyMeeting = meeting(
            externalIdentifier: "early-calendar",
            url: URL(string: "https://meet.google.com/abc-defg-hij")!,
            startDate: now.addingTimeInterval(900),
            endDate: now.addingTimeInterval(4_500)
        )
        await coordinator.updateCalendarMeeting(earlyMeeting, at: now)
        await coordinator.recordJoinAction(
            meeting: earlyMeeting,
            url: earlyMeeting.meetingURL!,
            at: now
        )

        await monitor.emit([
            process(
                objectID: 20,
                processID: 84,
                bundleIdentifier: "com.google.Chrome",
                input: true,
                output: true
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .ready)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        await coordinator.stop()
    }

    func testSilenceOrBreakWithMeetingUIPresentNeverEndsRecording() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = MutableMeetingClientAdapter()
        adapter.setSnapshot(
            client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        )
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }
        await monitor.emit([activeZoomProcess()])
        await coordinator.recordingStarted()

        await monitor.emit([
            process(
                objectID: 10,
                processID: 42,
                bundleIdentifier: "us.zoom.xos",
                input: false,
                output: false
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .recording)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        await coordinator.stop()
    }

    func testClientLeftOpenAfterUnplannedCallProducesOnlyProbableEnd() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = MutableMeetingClientAdapter()
        adapter.setSnapshot(
            client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .open
            )
        )
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }
        await monitor.emit([activeZoomProcess()])
        await coordinator.recordingStarted()
        adapter.setSnapshot(
            client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: false,
                callControlsPresent: false,
                microphoneState: .unknown
            )
        )

        await monitor.emit([
            process(
                objectID: 10,
                processID: 42,
                bundleIdentifier: "us.zoom.xos",
                input: false,
                output: false
            )
        ])

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .endSuspected)
        XCTAssertEqual(snapshot?.session.confidence, .probable)
        await coordinator.stop()
    }

    func testAccessibilityUnavailableKeepsManualRecordingAvailable() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let coordinator = makeCoordinator(monitor: monitor)
        await coordinator.start { await recorder.append($0) }
        await monitor.emit([activeZoomProcess()])
        let detected = await recorder.lastSnapshot()
        XCTAssertEqual(detected?.session.confidence, .probable)

        await coordinator.recordingStarted()

        let snapshot = await recorder.lastSnapshot()
        XCTAssertEqual(snapshot?.session.state, .recording)
        XCTAssertEqual(snapshot?.session.confidence, .confirmed)
        await coordinator.stop()
    }

    func testBackToBackCallWithSameProcessCreatesNewSession() async {
        let monitor = StubAudioProcessMonitor()
        let recorder = MeetingSessionDetectionRecorder()
        let adapter = MutableMeetingClientAdapter()
        adapter.setSnapshot(
            client(
                clientID: .zoom,
                processID: 42,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        )
        let coordinator = makeCoordinator(monitor: monitor, adapter: adapter)
        await coordinator.start { await recorder.append($0) }
        await monitor.emit([activeZoomProcess()])
        let firstSessionID = (await recorder.lastSnapshot())?.session.id
        await coordinator.recordingStarted()
        await monitor.emit([])
        let ended = await recorder.lastSnapshot()
        XCTAssertEqual(ended?.session.state, .ended)

        await monitor.emit([activeZoomProcess()])

        let second = await recorder.lastSnapshot()
        XCTAssertEqual(second?.session.state, .ready)
        XCTAssertEqual(second?.session.confidence, .confirmed)
        XCTAssertNotEqual(second?.session.id, firstSessionID)
        await coordinator.stop()
    }

    private func makeCoordinator(
        monitor: StubAudioProcessMonitor,
        adapter: any MeetingClientAdapting = StubMeetingClientAdapter()
    ) -> MeetingSessionCoordinator {
        MeetingSessionCoordinator(
            audioProcessMonitor: monitor,
            clientAdapter: adapter
        )
    }

    private func meeting(
        externalIdentifier: String,
        url: URL,
        startDate: Date,
        endDate: Date
    ) -> Meeting {
        Meeting(
            title: "Fixture Meeting",
            startDate: startDate,
            endDate: endDate,
            meetingURL: url,
            externalIdentifier: externalIdentifier
        )
    }

    private func process(
        objectID: AudioObjectID,
        processID: Int32,
        bundleIdentifier: String,
        input: Bool,
        output: Bool
    ) -> AudioProcessSnapshot {
        AudioProcessSnapshot(
            audioObjectID: objectID,
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            isRunningInput: input,
            isRunningOutput: output
        )
    }

    private func client(
        clientID: MeetingClientID,
        processID: Int32,
        meetingWindowPresent: Bool,
        callControlsPresent: Bool,
        microphoneState: MeetingMicrophoneState
    ) -> MeetingClientSnapshot {
        MeetingClientSnapshot(
            clientID: clientID,
            processID: processID,
            availability: .available,
            meetingWindowPresent: meetingWindowPresent,
            callControlsPresent: callControlsPresent,
            microphoneState: microphoneState
        )
    }

    private func activeZoomProcess() -> AudioProcessSnapshot {
        process(
            objectID: 10,
            processID: 42,
            bundleIdentifier: "us.zoom.xos",
            input: true,
            output: true
        )
    }
}

private actor StubAudioProcessMonitor: AudioProcessMonitoring {
    private var handler: (@Sendable ([AudioProcessSnapshot]) async -> Void)?

    func start(
        onUpdate: @escaping @Sendable ([AudioProcessSnapshot]) async -> Void
    ) async {
        handler = onUpdate
    }

    func refresh() async {}

    func stop() async {
        handler = nil
    }

    func emit(_ snapshots: [AudioProcessSnapshot]) async {
        await handler?(snapshots)
    }
}

private struct StubMeetingClientAdapter: MeetingClientAdapting {
    let snapshots: [Int32: MeetingClientSnapshot]

    init(snapshots: [Int32: MeetingClientSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func inspect(
        processID: Int32,
        bundleIdentifier: String?,
        promptForAccessibility: Bool
    ) -> MeetingClientSnapshot? {
        if let snapshot = snapshots[processID] {
            return snapshot
        }
        let matcher = MeetingClientProcessMatcher()
        guard let clientID = matcher.clientID(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return MeetingClientSnapshot(
            clientID: clientID,
            processID: processID,
            availability: .clientUnavailable,
            meetingWindowPresent: false,
            callControlsPresent: false,
            microphoneState: .unknown
        )
    }
}

private final class MutableMeetingClientAdapter:
    MeetingClientAdapting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [Int32: MeetingClientSnapshot] = [:]

    func setSnapshot(_ snapshot: MeetingClientSnapshot) {
        lock.withLock {
            snapshots[snapshot.processID] = snapshot
        }
    }

    func inspect(
        processID: Int32,
        bundleIdentifier: String?,
        promptForAccessibility: Bool
    ) -> MeetingClientSnapshot? {
        lock.withLock { snapshots[processID] }
    }
}

private actor MeetingSessionDetectionRecorder {
    private var snapshots: [MeetingSessionDetectionSnapshot] = []

    func append(_ snapshot: MeetingSessionDetectionSnapshot) {
        snapshots.append(snapshot)
    }

    func lastSnapshot() -> MeetingSessionDetectionSnapshot? {
        snapshots.last
    }
}
