import XCTest
@testable import Crenel

@MainActor
final class MicrophoneLevelMonitorTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testFollowsTheMicWhileRunningAndStopsTheCapture() async {
        let capture = FakeDictationCapture()
        let monitor = MicrophoneLevelMonitor(capture: capture, isAuthorized: { true })

        monitor.start(deviceID: "mic-1")
        await waitUntil { monitor.status == .listening }
        XCTAssertEqual(monitor.status, .listening)

        capture.levelContinuation?.yield(0.6)
        await waitUntil { monitor.level > 0 }
        XCTAssertEqual(monitor.level, 0.6, accuracy: 0.001)

        monitor.stop()
        await waitUntil { capture.stopCount > 0 }
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(monitor.level, 0)
        XCTAssertEqual(monitor.status, .idle)
    }

    func testNeverOpensTheMicWithoutAccess() async {
        let capture = FakeDictationCapture()
        let monitor = MicrophoneLevelMonitor(capture: capture, isAuthorized: { false })

        monitor.start(deviceID: nil)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(capture.levelContinuation)
        XCTAssertEqual(monitor.status, .idle)
    }

    func testReportsAMicThatCannotOpen() async {
        let capture = FakeDictationCapture()
        capture.startError = DictationFailure.microphoneUnavailable
        let monitor = MicrophoneLevelMonitor(capture: capture, isAuthorized: { true })

        monitor.start(deviceID: "gone")
        await waitUntil { monitor.status == .unavailable }

        XCTAssertEqual(monitor.status, .unavailable)
    }
}
