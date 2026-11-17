import AVFoundation
import CoreMedia
import Foundation

final class BrowserAudioCaptureSource: AudioCaptureSource {
    let kind = AudioSourceKind.systemAudio
    var onLevelChange: (@Sendable (Float) -> Void)?
    var onConnectionStateChange: (@Sendable (AudioSourceConnectionState) -> Void)?

    private let broker: BrowserAudioStreamBroker
    private let lock = NSLock()
    private var outputURL: URL?
    private var writer: SampleBufferAudioWriter?
    private var attachedSessionID: UUID?
    private var lastSampleTime: TimeInterval?
    private var hasReceivedAudio = false

    init(broker: BrowserAudioStreamBroker) {
        self.broker = broker
    }

    func prepare(outputURL: URL) async throws {
        guard broker.hasActiveSession else {
            throw RecordingCaptureError.browserMeetingAudioIsolationUnavailable
        }
        self.outputURL = outputURL
        writer = SampleBufferAudioWriter(
            outputURL: outputURL,
            source: .systemAudio,
            appliesMicrophonePrivacyGate: false
        )
    }

    func start() async throws {
        guard writer != nil else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Browser audio writer isn’t ready.")
        }
        do {
            let sessionID = try broker.attachConsumer(
                consume: { [weak self] chunk in
                    try self?.consume(chunk)
                },
                disconnected: { [weak self] in
                    self?.onConnectionStateChange?(.pipelineStalled)
                }
            )
            lock.withBrowserCaptureLock {
                attachedSessionID = sessionID
            }
        } catch {
            throw RecordingCaptureError.browserMeetingAudioIsolationUnavailable
        }
    }

    func stop() async throws -> CapturedAudioTrack {
        let state = lock.withBrowserCaptureLock { () -> (UUID?, URL?, SampleBufferAudioWriter?, Bool, TimeInterval?) in
            let state = (attachedSessionID, outputURL, writer, hasReceivedAudio, lastSampleTime)
            attachedSessionID = nil
            writer = nil
            outputURL = nil
            return state
        }
        if let sessionID = state.0 {
            broker.detachConsumer(sessionID: sessionID)
        }
        guard let outputURL = state.1, let writer = state.2 else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Browser audio recording isn’t ready.")
        }
        let firstSampleTime = try await writer.finish()
        guard state.3, let firstSampleTime else {
            throw RecordingCaptureError.sourceDidNotProduceAudio(.systemAudio)
        }
        return CapturedAudioTrack(
            source: .systemAudio,
            fileURL: outputURL,
            firstSampleTime: firstSampleTime,
            lastSampleTime: state.4
        )
    }

    func cancel() async {
        let state = lock.withBrowserCaptureLock { () -> (UUID?, SampleBufferAudioWriter?) in
            let state = (attachedSessionID, writer)
            attachedSessionID = nil
            writer = nil
            outputURL = nil
            hasReceivedAudio = false
            lastSampleTime = nil
            return state
        }
        if let sessionID = state.0 {
            broker.detachConsumer(sessionID: sessionID)
        }
        state.1?.cancel()
    }

    private func consume(_ chunk: BrowserAudioPCMChunk) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(chunk.sampleRate),
            channels: AVAudioChannelCount(chunk.channels),
            interleaved: true
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(chunk.frameCount)
        ) else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Invalid browser PCM format.")
        }
        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Couldn’t allocate the browser PCM buffer.")
        }
        chunk.pcmS16LE.copyBytes(
            to: destination.assumingMemoryBound(to: UInt8.self),
            count: chunk.pcmS16LE.count
        )

        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        let activeWriter = try lock.withBrowserCaptureLock { () throws -> SampleBufferAudioWriter in
            guard let activeWriter = self.writer else {
                throw RecordingCaptureError.sourceFailed(.systemAudio, "Browser recording consumer is closed.")
            }
            hasReceivedAudio = true
            lastSampleTime = presentationTime.seconds
                + (Double(chunk.frameCount) / Double(chunk.sampleRate))
            return activeWriter
        }
        activeWriter.append(buffer, presentationTime: presentationTime, microphoneGateState: .open)
        onLevelChange?(Self.level(of: chunk.pcmS16LE))
    }

    private static func level(of pcm: Data) -> Float {
        guard pcm.count >= MemoryLayout<Int16>.size else { return 0 }
        var squareSum = 0.0
        var sampleCount = 0
        pcm.withUnsafeBytes { bytes in
            var offset = 0
            while offset + 1 < bytes.count {
                let sample = Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                let normalized = Double(sample) / Double(Int16.max)
                squareSum += normalized * normalized
                sampleCount += 1
                offset += MemoryLayout<Int16>.size
            }
        }
        guard sampleCount > 0 else { return 0 }
        return Float(min(1, sqrt(squareSum / Double(sampleCount))))
    }
}

private extension NSLock {
    func withBrowserCaptureLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
