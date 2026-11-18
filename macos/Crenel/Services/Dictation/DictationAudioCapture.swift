@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// Both stages use the actual PCM duration, since the audio unit can vary its tap size.
/// A stalled consumer gets a terminal error instead of a transcript with missing audio.
final class DictationPCMQueue: AsyncSequence, @unchecked Sendable {
    typealias Element = AVAudioPCMBuffer
    private let lock = NSLock()
    private let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation
    private let maximumSeconds: Double
    private var queuedSeconds = 0.0
    private var overrun = false

    init(maximumSeconds: Double = 10) {
        self.maximumSeconds = maximumSeconds
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(2048))
    }

    func yield(_ buffer: Element) throws {
        guard buffer.frameLength > 0 else { return }
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        try lock.withLock {
            guard !overrun else { throw DictationFailure.audioOverrun }
            if queuedSeconds + seconds <= maximumSeconds {
                switch continuation.yield(buffer) {
                case .enqueued:
                    queuedSeconds += seconds
                    return
                case .terminated: return
                case .dropped: break
                @unknown default: break
                }
            }
            overrun = true
            continuation.finish()
            throw DictationFailure.audioOverrun
        }
    }

    func finish() { continuation.finish() }

    struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var iterator: AsyncStream<Element>.Iterator
        fileprivate let queue: DictationPCMQueue

        mutating func next() async throws -> Element? {
            let buffer = await iterator.next()
            try queue.consumed(buffer)
            return buffer
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: stream.makeAsyncIterator(), queue: self)
    }

    private func consumed(_ buffer: Element?) throws {
        try lock.withLock {
            if overrun { throw DictationFailure.audioOverrun }
            if let buffer {
                queuedSeconds = Swift.max(0, queuedSeconds - Double(buffer.frameLength) / buffer.format.sampleRate)
            }
        }
    }
}

/// Live microphone audio for one dictation session. Nothing is ever written to disk.
struct DictationAudioStream {
    let format: AVAudioFormat
    let buffers: DictationPCMQueue
    /// Normalized 0...1 level, throttled to roughly 20 Hz.
    let levels: AsyncStream<Float>
}

protocol DictationAudioCapturing: AnyObject {
    func start(deviceID: String?) async throws -> DictationAudioStream
    func stop()
}

/// AVAudioEngine input tap used only for dictation.
///
/// Runs independently of the meeting recorder (`MicrophoneCaptureSource` uses its own
/// `AVCaptureSession`); this class never touches that session or the system default device.
final class DictationAudioCapture: DictationAudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var bufferQueue: DictationPCMQueue?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var lastLevelHostTime: UInt64 = 0
    private let levelInterval: TimeInterval
    /// False for a level meter only: buffers are not copied out and the stream ends at once.
    private let deliversBuffers: Bool

    init(levelInterval: TimeInterval = 0.05, deliversBuffers: Bool = true) {
        self.levelInterval = levelInterval
        self.deliversBuffers = deliversBuffers
    }

    func start(deviceID: String?) async throws -> DictationAudioStream {
        stop()
        guard await Self.ensureMicrophoneAccess() else {
            throw DictationFailure.microphonePermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        if let deviceID, let audioDeviceID = Self.audioDeviceID(forUID: deviceID),
           let audioUnit = inputNode.audioUnit {
            var device = audioDeviceID
            // Only affects this engine's private AUHAL instance; the default device is untouched.
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationFailure.microphoneUnavailable
        }

        let buffers = DictationPCMQueue()
        let (levels, levelContinuation) = AsyncStream.makeStream(
            of: Float.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        if !deliversBuffers { buffers.finish() }
        lock.withLock {
            self.engine = engine
            self.bufferQueue = deliversBuffers ? buffers : nil
            self.levelContinuation = levelContinuation
            self.lastLevelHostTime = 0
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, time in
            self?.handle(buffer: buffer, hostTime: time.hostTime)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw DictationFailure.microphoneUnavailable
        }

        return DictationAudioStream(format: format, buffers: buffers, levels: levels)
    }

    func stop() {
        let (engine, buffers, levels) = lock.withLock {
            let snapshot = (self.engine, self.bufferQueue, self.levelContinuation)
            self.engine = nil
            self.bufferQueue = nil
            self.levelContinuation = nil
            return snapshot
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        buffers?.finish()
        levels?.finish()
    }

    private func handle(buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        guard deliversBuffers else {
            reportLevelOnly(of: buffer, hostTime: hostTime)
            return
        }
        guard let copy = Self.copy(buffer) else { return }
        let (buffers, levels, shouldReportLevel) = lock.withLock { () -> (
            DictationPCMQueue?,
            AsyncStream<Float>.Continuation?,
            Bool
        ) in
            let elapsed = AVAudioTime.seconds(forHostTime: hostTime)
                - AVAudioTime.seconds(forHostTime: lastLevelHostTime)
            let report = lastLevelHostTime == 0 || elapsed >= levelInterval
            if report { lastLevelHostTime = hostTime }
            return (bufferQueue, levelContinuation, report)
        }
        try? buffers?.yield(copy) // The consumer receives the same terminal error.
        if shouldReportLevel {
            levels?.yield(Self.normalizedLevel(of: copy))
        }
    }

    /// The level is read from the tap's own buffer; nothing is kept.
    private func reportLevelOnly(of buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        let levels: AsyncStream<Float>.Continuation? = lock.withLock {
            let elapsed = AVAudioTime.seconds(forHostTime: hostTime)
                - AVAudioTime.seconds(forHostTime: lastLevelHostTime)
            guard lastLevelHostTime == 0 || elapsed >= levelInterval else { return nil }
            lastLevelHostTime = hostTime
            return levelContinuation
        }
        levels?.yield(Self.normalizedLevel(of: buffer))
    }

    // MARK: - Helpers

    static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return 0 }
        let channel = channels[0]
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 60) / 60, 0), 1)
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for index in source.indices {
            let byteCount = Int(min(source[index].mDataByteSize, destination[index].mDataByteSize))
            if byteCount > 0, let from = source[index].mData, let to = destination[index].mData {
                memcpy(to, from, byteCount)
            }
            destination[index].mDataByteSize = UInt32(byteCount)
        }
        return copy
    }

    private static func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// `MicrophoneDevice.id` is `AVCaptureDevice.uniqueID`, which equals the Core Audio device UID.
    static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    deinit {
        stop()
    }
}
