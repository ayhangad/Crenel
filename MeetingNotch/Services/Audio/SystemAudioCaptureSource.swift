import Foundation

final class SystemAudioCaptureSource: AudioCaptureSource {
    let kind = AudioSourceKind.systemAudio
    var onLevelChange: (@Sendable (Float) -> Void)?

    private let levelQueue = DispatchQueue(label: "gad.MeetingNotch.audio.system.level")
    private var levelTimer: DispatchSourceTimer?
    private var recorder: CoreAudioTapRecorder?
    private var outputURL: URL?

    func prepare(outputURL: URL) async throws {
        let recorder = CoreAudioTapRecorder()
        do {
            try recorder.prepare(outputURL: outputURL)
        } catch {
            throw RecordingCaptureError.systemAudioPermissionDenied
        }
        self.outputURL = outputURL
        self.recorder = recorder
    }

    func start() async throws {
        guard let recorder else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Sistem sesi hazırlanmamış.")
        }
        do {
            try recorder.start()
            startLevelUpdates(recorder: recorder)
        } catch {
            throw RecordingCaptureError.systemAudioPermissionDenied
        }
    }

    func stop() async throws -> CapturedAudioTrack {
        stopLevelUpdates()
        guard let recorder, let outputURL else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Sistem sesi hazırlanmamış.")
        }
        do {
            try recorder.stop()
        } catch {
            reset()
            throw RecordingCaptureError.sourceFailed(
                .systemAudio,
                "Sistem sesi dosyası sonlandırılamadı."
            )
        }
        guard recorder.hasCapturedAudio, recorder.firstSampleTime >= 0 else {
            reset()
            throw RecordingCaptureError.sourceDidNotProduceAudio(.systemAudio)
        }
        let track = CapturedAudioTrack(
            source: .systemAudio,
            fileURL: outputURL,
            firstSampleTime: recorder.firstSampleTime
        )
        reset()
        return track
    }

    func cancel() async {
        stopLevelUpdates()
        recorder?.cancel()
        reset()
    }

    private func startLevelUpdates(recorder: CoreAudioTapRecorder) {
        stopLevelUpdates()
        let timer = DispatchSource.makeTimerSource(queue: levelQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self, weak recorder] in
            guard let recorder else { return }
            self?.onLevelChange?(recorder.currentLevel)
        }
        levelTimer = timer
        timer.resume()
    }

    private func stopLevelUpdates() {
        levelTimer?.setEventHandler {}
        levelTimer?.cancel()
        levelTimer = nil
    }

    private func reset() {
        recorder = nil
        outputURL = nil
    }
}
