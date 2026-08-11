import AVFoundation
import CoreMedia
import Foundation

final class SampleBufferAudioWriter {
    private static let outputSampleRate = 48_000.0
    private static let outputChannelCount: AVAudioChannelCount = 1

    private let outputURL: URL
    private let source: AudioSourceKind
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var terminalError: RecordingCaptureError?
    private var isFinished = false
    private let privacyGate: MicrophonePCMPrivacyGate?
    private(set) var firstSampleTime: TimeInterval?
    private(set) var lastSampleTime: TimeInterval?

    init(
        outputURL: URL,
        source: AudioSourceKind,
        appliesMicrophonePrivacyGate: Bool = true
    ) {
        self.outputURL = outputURL
        self.source = source
        privacyGate = appliesMicrophonePrivacyGate
            ? MicrophonePCMPrivacyGate(sampleRate: Self.outputSampleRate)
            : nil
    }

    func append(
        _ sampleBuffer: CMSampleBuffer,
        microphoneGateState: MeetingMicrophoneState
    ) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        do {
            let buffer = try SampleBufferPCMExtractor.copyPCMBuffer(from: sampleBuffer)
            append(
                buffer,
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                microphoneGateState: microphoneGateState
            )
        } catch {
            recordTerminalError(error)
        }
    }

    func append(
        _ buffer: AVAudioPCMBuffer,
        presentationTime: CMTime,
        microphoneGateState: MeetingMicrophoneState
    ) {
        guard buffer.frameLength > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, terminalError == nil else { return }

        do {
            let file = try configuredAudioFile()
            let converter = try configuredConverter(
                from: buffer.format,
                to: file.processingFormat
            )
            let sampleRateRatio = file.processingFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(
                max(1, ceil(Double(buffer.frameLength) * sampleRateRatio) + 64)
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: capacity
            ) else {
                throw RecordingCaptureError.sourceFailed(
                    source,
                    "\(source.displayName) buffer'ı hazırlanamadı."
                )
            }

            var suppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status == .error {
                throw conversionError
                    ?? RecordingCaptureError.sourceFailed(source, "Mikrofon formatı dönüştürülemedi.")
            }
            guard convertedBuffer.frameLength > 0 else { return }

            let bufferStartTime = Self.numericTime(presentationTime)
            if firstSampleTime == nil { firstSampleTime = bufferStartTime }
            lastSampleTime = max(
                lastSampleTime ?? bufferStartTime,
                bufferStartTime + (Double(buffer.frameLength) / buffer.format.sampleRate)
            )
            if let privacyGate,
               let readyBuffer = privacyGate.enqueue(
                   convertedBuffer,
                   state: microphoneGateState
               ) {
                try file.write(from: readyBuffer)
            } else if privacyGate == nil {
                try file.write(from: convertedBuffer)
            }
        } catch {
            storeTerminalError(error)
        }
    }

    func finish() async throws -> TimeInterval? {
        var fileToClose: AVAudioFile?
        let result: (RecordingCaptureError?, TimeInterval?) = lock.withLock {
            if terminalError == nil,
               let finalBuffer = privacyGate?.flush(),
               let audioFile {
                do {
                    try audioFile.write(from: finalBuffer)
                } catch {
                    storeTerminalError(error)
                }
            }
            isFinished = true
            fileToClose = audioFile
            audioFile = nil
            converter = nil
            privacyGate?.reset()
            return (terminalError, firstSampleTime)
        }

        // AVAudioFile finalizes the AAC container when its last strong reference is released.
        withExtendedLifetime(fileToClose) {}
        fileToClose = nil
        if let error = result.0 { throw error }
        return result.1
    }

    func cancel() {
        var fileToClose: AVAudioFile?
        lock.withLock {
            isFinished = true
            fileToClose = audioFile
            audioFile = nil
            converter = nil
            privacyGate?.reset()
        }
        withExtendedLifetime(fileToClose) {}
        fileToClose = nil
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func configuredAudioFile() throws -> AVAudioFile {
        if let audioFile { return audioFile }

        try? FileManager.default.removeItem(at: outputURL)
        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.outputSampleRate,
                AVNumberOfChannelsKey: Self.outputChannelCount,
                AVEncoderBitRateKey: 128_000
            ]
        )
        guard audioFile.processingFormat.sampleRate == Self.outputSampleRate,
              audioFile.processingFormat.channelCount == Self.outputChannelCount else {
            throw RecordingCaptureError.sourceFailed(
                source,
                "\(source.displayName) dosya formatı hazırlanamadı."
            )
        }
        self.audioFile = audioFile
        return audioFile
    }

    private func configuredConverter(
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioConverter {
        if let converter, converter.inputFormat.isEqual(inputFormat) {
            return converter
        }
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecordingCaptureError.sourceFailed(source, "Mikrofon formatı desteklenmiyor.")
        }
        converter.primeMethod = .none
        self.converter = converter
        return converter
    }

    private func recordTerminalError(_ error: Error) {
        lock.withLock {
            guard !isFinished, terminalError == nil else { return }
            storeTerminalError(error)
        }
    }

    private func storeTerminalError(_ error: Error) {
        AppLogger.audioCaptureFailed(source: source.rawValue, error: error)
        terminalError = .sourceFailed(source, "Ses dosyası yazılamadı.")
    }

    private static func numericTime(_ time: CMTime) -> TimeInterval {
        if time.isNumeric, time.seconds.isFinite, time.seconds >= 0 {
            return time.seconds
        }
        return CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
