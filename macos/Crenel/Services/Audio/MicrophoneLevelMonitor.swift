@preconcurrency import AVFoundation
import Foundation

/// Settings › Recording › Level: the selected mic's level while that page is on screen, so
/// the user can speak and see it move. Levels only — the audio is never kept, copied out or
/// written to disk — and it never asks for microphone access; without it it stays at rest.
@MainActor
final class MicrophoneLevelMonitor: ObservableObject {
    enum Status: Equatable {
        case idle
        case listening
        /// The mic could not be opened (unplugged, in use exclusively, …).
        case unavailable
    }

    @Published private(set) var level: Double = 0
    @Published private(set) var status = Status.idle

    private let capture: any DictationAudioCapturing
    private let isAuthorized: () -> Bool
    private var task: Task<Void, Never>?

    init(
        capture: any DictationAudioCapturing = DictationAudioCapture(deliversBuffers: false),
        isAuthorized: @escaping () -> Bool = { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    ) {
        self.capture = capture
        self.isAuthorized = isAuthorized
    }

    /// Starts listening to `deviceID` (nil: system default), replacing any earlier run.
    func start(deviceID: String?) {
        let previous = stopTask()
        task = Task { [weak self] in
            // One engine at a time: the previous run has stopped before this one opens the mic.
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.listen(deviceID: deviceID)
        }
    }

    func stop() {
        _ = stopTask()
    }

    /// Cancels the current run and returns it so a successor can wait for it.
    private func stopTask() -> Task<Void, Never>? {
        let previous = task
        previous?.cancel()
        task = nil
        level = 0
        status = .idle
        return previous
    }

    private func listen(deviceID: String?) async {
        guard isAuthorized() else { return }
        let stream: DictationAudioStream
        do {
            stream = try await capture.start(deviceID: deviceID)
        } catch {
            if !Task.isCancelled { status = .unavailable }
            return
        }
        defer { capture.stop() }
        guard !Task.isCancelled else { return }
        status = .listening
        // Ends when the task is cancelled (page gone, mic changed) or the capture stops.
        for await value in stream.levels {
            guard !Task.isCancelled else { break }
            level = Double(value)
        }
        if !Task.isCancelled {
            level = 0
            status = .idle
        }
    }
}
