import XCTest
@testable import Crenel

final class MicrophoneDeviceTests: XCTestCase {
    private let builtIn = MicrophoneDevice(
        id: "built-in",
        name: "Mac Mikrofonu",
        isSystemDefault: true
    )
    private let usb = MicrophoneDevice(
        id: "usb",
        name: "USB Mikrofon",
        isSystemDefault: false
    )

    func testSelectionPolicyKeepsAvailableExplicitSelection() {
        XCTAssertEqual(
            MicrophoneSelectionPolicy.resolvedDeviceID(
                selectedDeviceID: usb.id,
                devices: [builtIn, usb]
            ),
            usb.id
        )
    }

    func testSelectionPolicyFallsBackToSystemDefaultWhenSelectionDisconnects() {
        XCTAssertEqual(
            MicrophoneSelectionPolicy.resolvedDeviceID(
                selectedDeviceID: "disconnected",
                devices: [usb, builtIn]
            ),
            builtIn.id
        )
    }

    func testSelectionPolicyUsesFirstAvailableDeviceWithoutSystemDefault() {
        XCTAssertEqual(
            MicrophoneSelectionPolicy.resolvedDeviceID(
                selectedDeviceID: nil,
                devices: [usb]
            ),
            usb.id
        )
        XCTAssertNil(
            MicrophoneSelectionPolicy.resolvedDeviceID(
                selectedDeviceID: nil,
                devices: []
            )
        )
    }

    func testSettingsSnapshotReportsDisconnectedSelection() {
        let snapshot = MicrophoneSettingsSnapshot(
            devices: [builtIn],
            selectedDeviceID: usb.id
        )

        XCTAssertFalse(snapshot.selectedDeviceIsAvailable)
        XCTAssertTrue(
            MicrophoneSettingsSnapshot(
                devices: [builtIn],
                selectedDeviceID: nil
            ).selectedDeviceIsAvailable
        )
    }

    func testConnectionStatesExposeActionableStatus() {
        let recovered = AudioSourceConnectionState.recovered(deviceName: "Mac Mikrofonu")
        let disconnected = AudioSourceConnectionState.disconnected(deviceName: "USB Mikrofon")

        XCTAssertTrue(recovered.isReady)
        XCTAssertTrue(recovered.needsAttention)
        XCTAssertTrue(recovered.message?.contains("Recording continues") == true)
        XCTAssertFalse(disconnected.isReady)
        XCTAssertTrue(disconnected.needsAttention)
        XCTAssertTrue(disconnected.message?.contains("Reconnect") == true)
    }
}
