import AVFoundation
import CoreMedia
import Foundation

final class SampleBufferAudioWriter {
    private let outputURL: URL
    private let source: AudioSourceKind
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private(set) var firstSampleTime: TimeInterval?

    init(outputURL: URL, source: AudioSourceKind) {
        self.outputURL = outputURL
        self.source = source
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        lock.lock()
        defer { lock.unlock() }

        do {
            if writer == nil {
                try configureWriter(using: sampleBuffer)
            }

            guard let writer, let input, writer.status == .writing, input.isReadyForMoreMediaData else {
                return
            }

            if !input.append(sampleBuffer), let error = writer.error {
                AppLogger.audioCaptureFailed(source: "writer", message: error.localizedDescription)
            }
        } catch {
            AppLogger.audioCaptureFailed(source: "writer", message: error.localizedDescription)
        }
    }

    func finish() async throws -> TimeInterval? {
        let state: (AVAssetWriter, AVAssetWriterInput, TimeInterval?)? = lock.withLock {
            guard let writer, let input else { return nil }
            input.markAsFinished()
            return (writer, input, firstSampleTime)
        }

        guard let (writer, _, firstSampleTime) = state else { return nil }
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? RecordingCaptureError.sourceFailed(source, "Ses dosyası yazılamadı.")
        }
        return firstSampleTime
    }

    func cancel() {
        lock.withLock {
            writer?.cancelWriting()
        }
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func configureWriter(using sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw RecordingCaptureError.sourceFailed(source, "Ses formatı okunamadı.")
        }

        let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        let sampleRate = streamDescription?.mSampleRate ?? 48_000
        let channelCount = min(max(Int(streamDescription?.mChannelsPerFrame ?? 1), 1), 2)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: 128_000,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount
            ],
            sourceFormatHint: formatDescription
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingCaptureError.sourceFailed(source, "Ses encoder'ı hazırlanamadı.")
        }

        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? RecordingCaptureError.sourceFailed(source, "Ses dosyası açılamadı.")
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startSession(atSourceTime: presentationTime)
        firstSampleTime = presentationTime.seconds
        self.writer = writer
        self.input = input
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
