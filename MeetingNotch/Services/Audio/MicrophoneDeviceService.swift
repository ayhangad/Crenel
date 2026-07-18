@preconcurrency import AVFoundation
import Foundation

@MainActor
final class MicrophoneDeviceService {
    var onDevicesChange: (([MicrophoneDevice]) -> Void)?

    private let notificationCenter: NotificationCenter
    private var observationTokens: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func startMonitoring() {
        guard observationTokens.isEmpty else {
            publishCurrentDevices()
            return
        }

        let names: [Notification.Name] = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ]
        observationTokens = names.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard (notification.object as? AVCaptureDevice)?.hasMediaType(.audio) == true else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.publishCurrentDevices()
                }
            }
        }
        publishCurrentDevices()
    }

    func stopMonitoring() {
        observationTokens.forEach(notificationCenter.removeObserver)
        observationTokens.removeAll()
    }

    func currentDevices() -> [MicrophoneDevice] {
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices
            .filter(\.isConnected)
            .map { device in
                MicrophoneDevice(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isSystemDefault: device.uniqueID == defaultID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isSystemDefault != rhs.isSystemDefault {
                    return lhs.isSystemDefault
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func publishCurrentDevices() {
        onDevicesChange?(currentDevices())
    }
}
