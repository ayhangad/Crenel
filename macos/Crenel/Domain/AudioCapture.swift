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
    case pipelineRecovered
    case pipelineStalled

    var isReady: Bool {
        switch self {
        case .ready, .recovered, .pipelineRecovered: true
        case .preparing, .disconnected, .pipelineStalled: false
        }
    }

    var message: String? {
        switch self {
        case .preparing, .ready:
            nil
        case .recovered(let deviceName):
            "Microphone changed. Recording continues with \(deviceName)."
        case .disconnected(let deviceName):
            "\(deviceName) disconnected. Reconnect the microphone or stop recording."
        case .pipelineRecovered:
            "System audio stream restored."
        case .pipelineStalled:
            "System audio stream dropped. Stopping to protect the recording."
        }
    }

    var needsAttention: Bool {
        switch self {
        case .recovered, .disconnected, .pipelineRecovered, .pipelineStalled: true
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
    let lastSampleTime: TimeInterval?

    init(
        source: AudioSourceKind,
        fileURL: URL,
        firstSampleTime: TimeInterval?,
        lastSampleTime: TimeInterval? = nil
    ) {
        self.source = source
        self.fileURL = fileURL
        self.firstSampleTime = firstSampleTime
        self.lastSampleTime = lastSampleTime
    }
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
    case diskSpaceBecameLow
    case meetingProcessUnavailable
    case sourceDidNotProduceAudio(AudioSourceKind)
    case sourceFailed(AudioSourceKind, String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already in progress."
        case .microphonePermissionDenied:
            "Microphone access is off. Turn it on in System Settings."
        case .systemAudioPermissionDenied:
            "System audio access is off. Turn on System Audio Recording in System Settings."
        case .noMicrophone:
            "No microphone available."
        case .noDisplay:
            "No display available to capture system audio."
        case .insufficientDiskSpace:
            "Not enough free disk space to record."
        case .diskSpaceBecameLow:
            "Disk space is critically low. Stopping to protect the recording."
        case .meetingProcessUnavailable:
            "Couldn’t safely verify the meeting audio process. Try again with the meeting app open."
        case .sourceDidNotProduceAudio(let source):
            "\(source.displayName) produced no audio."
        case .sourceFailed(let source, let message):
            "\(source.displayName) couldn’t start: \(message)"
        }
    }
}

extension AudioSourceKind {
    var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudio: "System audio"
        }
    }
}
