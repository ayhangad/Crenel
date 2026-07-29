@preconcurrency import AVFoundation
import Foundation

@MainActor
final class MicrophoneDeviceService {
    struct Dependencies: Sendable {
        var discoverDevices: @Sendable () -> [MicrophoneDevice]

        static let live = Self {
            let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
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
    }

    var onDevicesChange: (([MicrophoneDevice]) -> Void)?

    private let notificationCenter: NotificationCenter
    private let dependencies: Dependencies
    private var observationTokens: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?

    init(
        notificationCenter: NotificationCenter = .default,
        dependencies: Dependencies = .live
    ) {
        self.notificationCenter = notificationCenter
        self.dependencies = dependencies
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
        refreshTask?.cancel()
        refreshTask = nil
        observationTokens.forEach(notificationCenter.removeObserver)
        observationTokens.removeAll()
    }

    func currentDevices() async -> [MicrophoneDevice] {
        let discoverDevices = dependencies.discoverDevices
        return await Task.detached(priority: .utility) {
            discoverDevices()
        }.value
    }

    private func publishCurrentDevices() {
        guard refreshTask == nil else { return }
        let discoverDevices = dependencies.discoverDevices
        refreshTask = Task { [weak self] in
            let devices = await Task.detached(priority: .utility) {
                discoverDevices()
            }.value
            defer { self?.refreshTask = nil }
            guard !Task.isCancelled else { return }
            self?.onDevicesChange?(devices)
        }
    }
}
