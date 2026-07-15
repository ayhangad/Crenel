@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

@MainActor
final class AudioCapturePermissionService {
    struct Dependencies {
        var microphoneStatus: () -> AVAuthorizationStatus
        var requestMicrophoneAccess: () async -> Bool
        var hasSystemAudioAccess: () -> Bool
        var requestSystemAudioAccess: () -> Bool

        static let live = Dependencies(
            microphoneStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
            requestMicrophoneAccess: { await AVCaptureDevice.requestAccess(for: .audio) },
            hasSystemAudioAccess: { CGPreflightScreenCaptureAccess() },
            requestSystemAudioAccess: { CGRequestScreenCaptureAccess() }
        )
    }

    private enum Key {
        static let requestedSystemAudioAccess = "permissions.requestedSystemAudioAccess"
    }

    private let dependencies: Dependencies
    private let defaults: UserDefaults

    init(dependencies: Dependencies = .live, defaults: UserDefaults = .standard) {
        self.dependencies = dependencies
        self.defaults = defaults
    }

    func currentSnapshot() -> AudioCapturePermissionSnapshot {
        AudioCapturePermissionSnapshot(
            microphone: microphonePermissionStatus(),
            systemAudio: systemAudioPermissionStatus()
        )
    }

    func requestMicrophoneAccess() async -> AudioCapturePermissionSnapshot {
        if dependencies.microphoneStatus() == .notDetermined {
            _ = await dependencies.requestMicrophoneAccess()
        }
        return currentSnapshot()
    }

    func requestSystemAudioAccess() -> AudioCapturePermissionSnapshot {
        if !dependencies.hasSystemAudioAccess() {
            defaults.set(true, forKey: Key.requestedSystemAudioAccess)
            _ = dependencies.requestSystemAudioAccess()
        }
        return currentSnapshot()
    }

    func verifyAccessForRecording() async -> AudioCapturePermissionSnapshot {
        var snapshot = currentSnapshot()
        if snapshot.microphone == .notDetermined {
            snapshot = await requestMicrophoneAccess()
        }
        if snapshot.systemAudio == .notDetermined {
            snapshot = requestSystemAudioAccess()
        }
        return snapshot
    }

    private func microphonePermissionStatus() -> AudioCapturePermissionStatus {
        switch dependencies.microphoneStatus() {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    private func systemAudioPermissionStatus() -> AudioCapturePermissionStatus {
        if dependencies.hasSystemAudioAccess() {
            defaults.set(true, forKey: Key.requestedSystemAudioAccess)
            return .authorized
        }
        return defaults.bool(forKey: Key.requestedSystemAudioAccess) ? .denied : .notDetermined
    }
}
