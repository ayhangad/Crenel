@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioCapturePermissionService {
    struct Dependencies {
        var microphoneStatus: () -> AVAuthorizationStatus
        var requestMicrophoneAccess: () async -> Bool
        var hasSystemAudioAccess: () -> Bool
        var requestSystemAudioAccess: () async -> Bool

        static let live = Dependencies(
            microphoneStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
            requestMicrophoneAccess: { await AVCaptureDevice.requestAccess(for: .audio) },
            hasSystemAudioAccess: { false },
            requestSystemAudioAccess: { await SystemAudioPermissionProbe.requestAccess() }
        )
    }

    private enum Key {
        static let requestedSystemAudioAccess = "permissions.requestedSystemAudioAccess"
    }

    private let dependencies: Dependencies
    private let defaults: UserDefaults
    private var verifiedSystemAudioAccess = false
    private var rejectedSystemAudioAccess = false
    private var isRequestingSystemAudioAccess = false

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

    func requestSystemAudioAccess() async -> AudioCapturePermissionSnapshot {
        guard !isRequestingSystemAudioAccess else { return currentSnapshot() }
        if !dependencies.hasSystemAudioAccess() {
            isRequestingSystemAudioAccess = true
            defer { isRequestingSystemAudioAccess = false }
            defaults.set(true, forKey: Key.requestedSystemAudioAccess)
            let granted = await dependencies.requestSystemAudioAccess()
            verifiedSystemAudioAccess = granted
            rejectedSystemAudioAccess = !granted
        }
        return currentSnapshot()
    }

    func verifyAccessForRecording() async -> AudioCapturePermissionSnapshot {
        var snapshot = currentSnapshot()
        if snapshot.microphone == .notDetermined {
            snapshot = await requestMicrophoneAccess()
        }
        if snapshot.systemAudio != .authorized {
            snapshot = await requestSystemAudioAccess()
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
        if dependencies.hasSystemAudioAccess() || verifiedSystemAudioAccess {
            defaults.set(true, forKey: Key.requestedSystemAudioAccess)
            return .authorized
        }
        if rejectedSystemAudioAccess {
            return .denied
        }
        return defaults.bool(forKey: Key.requestedSystemAudioAccess)
            ? .verificationRequired
            : .notDetermined
    }
}

@MainActor
private enum SystemAudioPermissionProbe {
    static func requestAccess() async -> Bool {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotch-PermissionProbe-\(UUID().uuidString).m4a")
        let recorder = CoreAudioTapRecorder()
        defer {
            recorder.cancel()
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try recorder.prepare(outputURL: outputURL)
            try recorder.start()
            try await Task.sleep(for: .milliseconds(150))
            return true
        } catch {
            return false
        }
    }
}
