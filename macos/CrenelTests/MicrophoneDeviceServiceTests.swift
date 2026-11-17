import XCTest
@testable import Crenel

@MainActor
final class MicrophoneDeviceServiceTests: XCTestCase {
    func testDeviceDiscoveryDoesNotRunOnMainThread() async {
        let callback = expectation(description: "Publishes discovered devices")
        let observation = DiscoveryObservation()
        let expected = [
            MicrophoneDevice(id: "system", name: "System", isSystemDefault: true)
        ]
        let service = MicrophoneDeviceService(
            notificationCenter: NotificationCenter(),
            dependencies: .init {
                observation.record(isMainThread: Thread.isMainThread)
                Thread.sleep(forTimeInterval: 0.5)
                return expected
            }
        )
        service.onDevicesChange = { devices in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(devices, expected)
            callback.fulfill()
        }

        let startedAt = ContinuousClock.now
        service.startMonitoring()
        let startDuration = ContinuousClock.now - startedAt

        XCTAssertLessThan(startDuration, .milliseconds(200))
        await fulfillment(of: [callback], timeout: 2)
        service.stopMonitoring()

        XCTAssertEqual(observation.wasMainThread, false)
    }

    func testExplicitDeviceRefreshDoesNotRunOnMainThread() async {
        let observation = DiscoveryObservation()
        let expected = [
            MicrophoneDevice(id: "usb", name: "USB", isSystemDefault: false)
        ]
        let service = MicrophoneDeviceService(
            notificationCenter: NotificationCenter(),
            dependencies: .init {
                observation.record(isMainThread: Thread.isMainThread)
                return expected
            }
        )

        let devices = await service.currentDevices()

        XCTAssertEqual(devices, expected)
        XCTAssertEqual(observation.wasMainThread, false)
    }
}

private final class DiscoveryObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedWasMainThread: Bool?

    var wasMainThread: Bool? {
        lock.withLock { storedWasMainThread }
    }

    func record(isMainThread: Bool) {
        lock.withLock {
            storedWasMainThread = isMainThread
        }
    }
}
