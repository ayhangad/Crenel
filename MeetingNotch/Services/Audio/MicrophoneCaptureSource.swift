@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class MicrophoneCaptureSource: NSObject, AudioCaptureSource {
    let kind = AudioSourceKind.microphone
    var onLevelChange: (@Sendable (Float) -> Void)?

    private let captureQueue = DispatchQueue(label: "gad.MeetingNotch.audio.microphone")
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private var writer: SampleBufferAudioWriter?
    private var outputURL: URL?

    func prepare(outputURL: URL) async throws {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let isAuthorized: Bool
        switch authorizationStatus {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else {
            throw RecordingCaptureError.microphonePermissionDenied
        }
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecordingCaptureError.noMicrophone
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecordingCaptureError.sourceFailed(.microphone, "Ses oturumu oluşturulamadı.")
        }

        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: captureQueue)
        self.outputURL = outputURL
        writer = SampleBufferAudioWriter(outputURL: outputURL, source: kind)
    }

    func start() async throws {
        await withCheckedContinuation { continuation in
            captureQueue.async { [session] in
                session.startRunning()
                continuation.resume()
            }
        }

        guard session.isRunning else {
            throw RecordingCaptureError.sourceFailed(.microphone, "Mikrofon akışı başlamadı.")
        }
    }

    func stop() async throws -> CapturedAudioTrack {
        await stopSession()
        guard let writer, let outputURL else {
            throw RecordingCaptureError.sourceFailed(.microphone, "Kayıt hazırlanmamış.")
        }
        guard let firstSampleTime = try await writer.finish() else {
            throw RecordingCaptureError.sourceDidNotProduceAudio(.microphone)
        }
        return CapturedAudioTrack(
            source: .microphone,
            fileURL: outputURL,
            firstSampleTime: firstSampleTime
        )
    }

    func cancel() async {
        await stopSession()
        writer?.cancel()
        reset()
    }

    private func stopSession() async {
        await withCheckedContinuation { continuation in
            captureQueue.async { [session] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func reset() {
        output.setSampleBufferDelegate(nil, queue: nil)
        writer = nil
        outputURL = nil
    }
}

extension MicrophoneCaptureSource: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        writer?.append(sampleBuffer)
        onLevelChange?(AudioLevelMeter.normalizedLevel(from: sampleBuffer))
    }
}
