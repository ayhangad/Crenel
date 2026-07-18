import Foundation

enum AudioSourceKind: String, Codable, CaseIterable, Sendable {
    case microphone
    case systemAudio
}

struct AudioSourceStatus: Equatable, Sendable {
    var connectionState = AudioSourceConnectionState.preparing
    var level: Float = 0

    var isReady: Bool { connectionState.isReady }
}

enum AudioSourceConnectionState: Equatable, Sendable {
    case preparing
    case ready
    case recovered(deviceName: String)
    case disconnected(deviceName: String)

    var isReady: Bool {
        switch self {
        case .ready, .recovered: true
        case .preparing, .disconnected: false
        }
    }

    var message: String? {
        switch self {
        case .preparing, .ready:
            nil
        case .recovered(let deviceName):
            "Mikrofon bağlantısı değişti; \(deviceName) ile kayıt sürüyor."
        case .disconnected(let deviceName):
            "\(deviceName) bağlantısı kesildi. Mikrofonu yeniden bağlayın veya kaydı durdurun."
        }
    }

    var needsAttention: Bool {
        switch self {
        case .recovered, .disconnected: true
        case .preparing, .ready: false
        }
    }
}

struct RecordingCaptureStatus: Equatable, Sendable {
    var microphone = AudioSourceStatus()
    var systemAudio = AudioSourceStatus()

    static let idle = RecordingCaptureStatus()
}

struct CapturedAudioTrack: Codable, Equatable, Sendable {
    let source: AudioSourceKind
    let fileURL: URL
    let firstSampleTime: TimeInterval?
}

struct RecordingCaptureResult: Codable, Equatable, Sendable {
    let session: RecordingSession
    let tracks: [CapturedAudioTrack]
}

enum RecordingCaptureError: LocalizedError, Equatable, Sendable {
    case alreadyRecording
    case microphonePermissionDenied
    case systemAudioPermissionDenied
    case noMicrophone
    case noDisplay
    case insufficientDiskSpace
    case sourceDidNotProduceAudio(AudioSourceKind)
    case sourceFailed(AudioSourceKind, String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Zaten devam eden bir kayıt var."
        case .microphonePermissionDenied:
            "Mikrofon izni verilmedi. Sistem Ayarları'ndan erişimi açın."
        case .systemAudioPermissionDenied:
            "Sistem sesi izni verilmedi. Sistem Ayarları'nda Sistem Sesini Kaydetme erişimini açın."
        case .noMicrophone:
            "Kullanılabilir bir mikrofon bulunamadı."
        case .noDisplay:
            "Sistem sesini yakalamak için kullanılabilir ekran bulunamadı."
        case .insufficientDiskSpace:
            "Kayıt için yeterli boş disk alanı yok."
        case .sourceDidNotProduceAudio(let source):
            "\(source.displayName) ses verisi üretmedi."
        case .sourceFailed(let source, let message):
            "\(source.displayName) başlatılamadı: \(message)"
        }
    }
}

extension AudioSourceKind {
    var displayName: String {
        switch self {
        case .microphone: "Mikrofon"
        case .systemAudio: "Sistem sesi"
        }
    }
}
