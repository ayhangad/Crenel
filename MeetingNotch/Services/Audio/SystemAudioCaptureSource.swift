import Foundation

struct AudioPipelineHeartbeat: Equatable, Sendable {
    let unchangedPollLimit: Int

    private(set) var lastFrameCount: UInt64?
    private(set) var unchangedPollCount = 0
    private(set) var isStalled = false

    init(unchangedPollLimit: Int = 30) {
        self.unchangedPollLimit = max(1, unchangedPollLimit)
    }

    mutating func observe(
        capturedFrameCount: UInt64,
        hasWriteError: Bool = false
    ) -> AudioSourceConnectionState? {
        if hasWriteError {
            guard !isStalled else { return nil }
            isStalled = true
            return .pipelineStalled
        }

        guard let lastFrameCount else {
            self.lastFrameCount = capturedFrameCount
            return nil
        }

        guard capturedFrameCount == lastFrameCount else {
            self.lastFrameCount = capturedFrameCount
            unchangedPollCount = 0
            guard isStalled else { return nil }
            isStalled = false
            return .pipelineRecovered
        }

        unchangedPollCount += 1
        guard unchangedPollCount >= unchangedPollLimit, !isStalled else { return nil }
        isStalled = true
        return .pipelineStalled
    }
}

final class SystemAudioCaptureSource: AudioCaptureSource {
    let kind = AudioSourceKind.systemAudio
    var onLevelChange: (@Sendable (Float) -> Void)?
    var onConnectionStateChange: (@Sendable (AudioSourceConnectionState) -> Void)?

    private let levelQueue = DispatchQueue(label: "gad.MeetingNotch.audio.system.level")
    private var levelTimer: DispatchSourceTimer?
    private var recorder: CoreAudioTapRecorder?
    private var outputURL: URL?
    private let scope: SystemAudioCaptureScope
    private var heartbeat = AudioPipelineHeartbeat()

    init(scope: SystemAudioCaptureScope) {
        self.scope = scope
    }

    func prepare(outputURL: URL) async throws {
        let recorder = CoreAudioTapRecorder()
        do {
            switch scope {
            case .meetingProcesses:
                guard let objectIDs = scope.includedProcessObjectIDs, !objectIDs.isEmpty else {
                    throw RecordingCaptureError.meetingProcessUnavailable
                }
                try recorder.prepare(
                    outputURL: outputURL,
                    includedProcessObjectIDs: objectIDs.map(NSNumber.init(value:))
                )
            case .browserTab:
                throw RecordingCaptureError.browserMeetingAudioIsolationUnavailable
            case .explicitManualGlobal:
                try recorder.prepare(outputURL: outputURL)
            }
        } catch let error as RecordingCaptureError {
            throw error
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
            firstSampleTime: recorder.firstSampleTime,
            lastSampleTime: recorder.lastSampleTime >= 0 ? recorder.lastSampleTime : nil
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
        heartbeat = AudioPipelineHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: levelQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self, weak recorder] in
            guard let self, let recorder else { return }
            self.onLevelChange?(recorder.currentLevel)
            if let connectionState = self.heartbeat.observe(
                capturedFrameCount: recorder.capturedFrameCount,
                hasWriteError: recorder.hasWriteError
            ) {
                self.onConnectionStateChange?(connectionState)
            }
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
