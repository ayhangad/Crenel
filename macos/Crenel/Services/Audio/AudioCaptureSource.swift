import Foundation

protocol AudioCaptureSource: AnyObject {
    var kind: AudioSourceKind { get }
    var onLevelChange: (@Sendable (Float) -> Void)? { get set }
    var onConnectionStateChange: (@Sendable (AudioSourceConnectionState) -> Void)? { get set }

    func prepare(outputURL: URL) async throws
    func start() async throws
    func stop() async throws -> CapturedAudioTrack
    func cancel() async
}

protocol MeetingMicrophoneGateUpdating: AnyObject {
    func updateMicrophoneGate(_ gate: MeetingMicrophoneGate)
}
