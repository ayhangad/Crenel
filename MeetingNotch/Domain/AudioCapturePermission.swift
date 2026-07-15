import Foundation

enum AudioCapturePermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case verificationRequired
    case authorized
    case denied
    case restricted

    var requiresSystemSettings: Bool {
        self == .denied || self == .restricted
    }
}

struct AudioCapturePermissionSnapshot: Equatable, Sendable {
    var microphone: AudioCapturePermissionStatus
    var systemAudio: AudioCapturePermissionStatus

    var canRecord: Bool {
        microphone == .authorized
            && (systemAudio == .authorized || systemAudio == .verificationRequired)
    }
}
