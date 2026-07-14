import Foundation

protocol AudioCaptureSource: AnyObject {
    var kind: AudioSourceKind { get }
    var onLevelChange: (@Sendable (Float) -> Void)? { get set }

    func prepare(outputURL: URL) async throws
    func start() async throws
    func stop() async throws -> CapturedAudioTrack
    func cancel() async
}
