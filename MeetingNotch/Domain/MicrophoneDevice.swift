import Foundation

struct MicrophoneDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isSystemDefault: Bool
}

struct MicrophoneSettingsSnapshot: Equatable, Sendable {
    var devices: [MicrophoneDevice]
    var selectedDeviceID: String?

    var selectedDeviceIsAvailable: Bool {
        guard let selectedDeviceID else { return true }
        return devices.contains { $0.id == selectedDeviceID }
    }
}

enum MicrophoneSelectionPolicy {
    static func resolvedDeviceID(
        selectedDeviceID: String?,
        devices: [MicrophoneDevice]
    ) -> String? {
        if let selectedDeviceID,
           devices.contains(where: { $0.id == selectedDeviceID }) {
            return selectedDeviceID
        }
        return devices.first(where: \.isSystemDefault)?.id ?? devices.first?.id
    }
}
