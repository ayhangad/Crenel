import XCTest
@testable import Crenel

final class MeetingClientAdapterTests: XCTestCase {
    func testZoomMeetingWindowControlsAndOpenMicrophoneAreDetected() {
        let adapter = makeAdapter(elements: [
            element(role: "AXWindow", title: "Zoom Meeting"),
            element(role: "AXButton", description: "Mute my audio"),
            element(role: "AXButton", description: "Leave meeting")
        ])

        let snapshot = adapter.inspect(
            processID: 42,
            bundleIdentifier: "us.zoom.xos",
            promptForAccessibility: false
        )

        XCTAssertEqual(
            snapshot,
            MeetingClientSnapshot(
                clientID: .zoom,
                processID: 42,
                availability: .available,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .open
            )
        )
        XCTAssertEqual(
            snapshot?.evidence,
            .clientUI(
                clientID: .zoom,
                meetingWindowPresent: true,
                callControlsPresent: true
            )
        )
    }

    func testZoomUnmuteActionMeansMicrophoneIsClosed() {
        let adapter = makeAdapter(elements: [
            element(role: "AXWindow", title: "Zoom Workplace"),
            element(role: "AXButton", description: "Unmute my audio"),
            element(role: "AXButton", description: "End meeting")
        ])

        XCTAssertEqual(
            adapter.inspect(
                processID: 43,
                bundleIdentifier: "us.zoom.xos",
                promptForAccessibility: false
            )?.microphoneState,
            .closed
        )
    }

    func testGoogleMeetURLControlsAndClosedMicrophoneAreDetected() {
        let adapter = makeAdapter(elements: [
            element(
                role: "AXWindow",
                title: "Weekly sync – Google Chrome",
                url: "https://meet.google.com/abc-defg-hij"
            ),
            element(role: "AXButton", description: "Turn on microphone"),
            element(role: "AXButton", description: "Leave call")
        ])

        XCTAssertEqual(
            adapter.inspect(
                processID: 84,
                bundleIdentifier: "com.google.Chrome",
                promptForAccessibility: false
            ),
            MeetingClientSnapshot(
                clientID: .googleMeetChrome,
                processID: 84,
                availability: .available,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        )
    }

    func testOrdinaryChromeWindowIsNotReportedAsGoogleMeet() {
        let adapter = makeAdapter(elements: [
            element(role: "AXWindow", title: "Documentation – Google Chrome"),
            element(role: "AXButton", description: "Mute site"),
            element(role: "AXButton", description: "Close tab")
        ])

        let snapshot = adapter.inspect(
            processID: 85,
            bundleIdentifier: "com.google.Chrome",
            promptForAccessibility: false
        )

        XCTAssertEqual(snapshot?.meetingWindowPresent, false)
        XCTAssertEqual(snapshot?.callControlsPresent, false)
        XCTAssertEqual(snapshot?.microphoneState, .unknown)
    }

    func testMissingAccessibilityPermissionFailsClosedWithoutReadingTree() {
        let authorizer = StubAccessibilityAuthorizer(isTrusted: false)
        let reader = StubAccessibilityTreeReader(elements: [], failure: nil)
        let adapter = AccessibilityMeetingClientAdapter(
            authorizer: authorizer,
            treeReader: reader
        )

        let snapshot = adapter.inspect(
            processID: 86,
            bundleIdentifier: "com.google.Chrome",
            promptForAccessibility: true
        )

        XCTAssertEqual(snapshot?.availability, .accessibilityPermissionRequired)
        XCTAssertEqual(snapshot?.meetingWindowPresent, false)
        XCTAssertEqual(snapshot?.callControlsPresent, false)
        XCTAssertEqual(snapshot?.microphoneState, .unknown)
        XCTAssertEqual(authorizer.receivedPrompts, [true])
        XCTAssertEqual(reader.readProcessIDs, [])
    }

    func testTreeFailureReturnsUnavailableFailClosedSnapshot() {
        let adapter = AccessibilityMeetingClientAdapter(
            authorizer: StubAccessibilityAuthorizer(isTrusted: true),
            treeReader: StubAccessibilityTreeReader(
                elements: [],
                failure: .treeUnavailable
            )
        )

        let snapshot = adapter.inspect(
            processID: 87,
            bundleIdentifier: "us.zoom.xos",
            promptForAccessibility: false
        )

        XCTAssertEqual(snapshot?.availability, .clientUnavailable)
        XCTAssertEqual(snapshot?.microphoneState, .unknown)
    }

    func testUnsupportedProcessDoesNotRequestAccessibility() {
        let authorizer = StubAccessibilityAuthorizer(isTrusted: false)
        let adapter = AccessibilityMeetingClientAdapter(
            authorizer: authorizer,
            treeReader: StubAccessibilityTreeReader(elements: [], failure: nil)
        )

        XCTAssertNil(
            adapter.inspect(
                processID: 88,
                bundleIdentifier: "com.apple.Music",
                promptForAccessibility: true
            )
        )
        XCTAssertEqual(authorizer.receivedPrompts, [])
    }

    func testProcessMatcherSupportsStableBetaAndCanaryChrome() {
        let matcher = MeetingClientProcessMatcher()

        XCTAssertEqual(matcher.clientID(bundleIdentifier: "us.zoom.xos"), .zoom)
        XCTAssertEqual(
            matcher.clientID(bundleIdentifier: "com.google.Chrome"),
            .googleMeetChrome
        )
        XCTAssertEqual(
            matcher.clientID(bundleIdentifier: "com.google.Chrome.beta"),
            .googleMeetChrome
        )
        XCTAssertEqual(
            matcher.clientID(bundleIdentifier: "com.google.Chrome.canary"),
            .googleMeetChrome
        )
        XCTAssertNil(matcher.clientID(bundleIdentifier: "com.apple.Safari"))
    }

    private func makeAdapter(
        elements: [AccessibilityElementSnapshot]
    ) -> AccessibilityMeetingClientAdapter {
        AccessibilityMeetingClientAdapter(
            authorizer: StubAccessibilityAuthorizer(isTrusted: true),
            treeReader: StubAccessibilityTreeReader(elements: elements, failure: nil)
        )
    }

    private func element(
        role: String,
        identifier: String? = nil,
        title: String? = nil,
        description: String? = nil,
        url: String? = nil
    ) -> AccessibilityElementSnapshot {
        AccessibilityElementSnapshot(
            role: role,
            subrole: nil,
            identifier: identifier,
            title: title,
            description: description,
            help: nil,
            value: nil,
            url: url
        )
    }
}

private final class StubAccessibilityAuthorizer:
    AccessibilityAuthorizing,
    @unchecked Sendable {
    private let lock = NSLock()
    private let trusted: Bool
    private var prompts: [Bool] = []

    init(isTrusted: Bool) {
        trusted = isTrusted
    }

    var receivedPrompts: [Bool] {
        lock.withLock { prompts }
    }

    func isTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            prompts.append(prompt)
            return trusted
        }
    }
}

private final class StubAccessibilityTreeReader:
    AccessibilityTreeReading,
    @unchecked Sendable {
    private let lock = NSLock()
    private let elements: [AccessibilityElementSnapshot]
    private let failure: AccessibilityTreeReaderError?
    private var processIDs: [Int32] = []

    init(
        elements: [AccessibilityElementSnapshot],
        failure: AccessibilityTreeReaderError?
    ) {
        self.elements = elements
        self.failure = failure
    }

    var readProcessIDs: [Int32] {
        lock.withLock { processIDs }
    }

    func readElements(processID: Int32) throws -> [AccessibilityElementSnapshot] {
        try lock.withLock {
            processIDs.append(processID)
            if let failure {
                throw failure
            }
            return elements
        }
    }
}
