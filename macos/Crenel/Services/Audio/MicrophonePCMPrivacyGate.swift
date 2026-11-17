import AVFoundation
import Foundation

final class MicrophonePCMPrivacyGate {
    private let fadeFrameCount: AVAudioFrameCount
    private var pending: (buffer: AVAudioPCMBuffer, isOpen: Bool)?
    private var previousWasOpen = false

    init(sampleRate: Double, fadeDuration: TimeInterval = 0.005) {
        fadeFrameCount = AVAudioFrameCount(max(1, (sampleRate * fadeDuration).rounded()))
    }

    func enqueue(
        _ buffer: AVAudioPCMBuffer,
        state: MeetingMicrophoneState
    ) -> AVAudioPCMBuffer? {
        let isOpen = state == .open

        if !isOpen {
            zero(buffer)
        } else if !previousWasOpen {
            fadeIn(buffer)
        }

        let ready = pending
        if let ready, ready.isOpen, !isOpen {
            fadeOut(ready.buffer)
        }

        pending = (buffer, isOpen)
        previousWasOpen = isOpen
        return ready?.buffer
    }

    func flush() -> AVAudioPCMBuffer? {
        defer { pending = nil }
        return pending?.buffer
    }

    func reset() {
        pending = nil
        previousWasOpen = false
    }

    private func zero(_ buffer: AVAudioPCMBuffer) {
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            memset(data, 0, Int(audioBuffer.mDataByteSize))
        }
    }

    private func fadeIn(_ buffer: AVAudioPCMBuffer) {
        applyFade(buffer, fadesIn: true)
    }

    private func fadeOut(_ buffer: AVAudioPCMBuffer) {
        applyFade(buffer, fadesIn: false)
    }

    private func applyFade(_ buffer: AVAudioPCMBuffer, fadesIn: Bool) {
        guard let channelData = buffer.floatChannelData else {
            if !fadesIn { zero(buffer) }
            return
        }
        let frames = Int(buffer.frameLength)
        let fadeFrames = min(frames, Int(fadeFrameCount))
        guard fadeFrames > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)
        let startFrame = fadesIn ? 0 : frames - fadeFrames

        for frameOffset in 0..<fadeFrames {
            let gain: Float
            if fadesIn {
                gain = Float(frameOffset + 1) / Float(fadeFrames)
            } else {
                gain = Float(fadeFrames - frameOffset - 1) / Float(fadeFrames)
            }
            let frame = startFrame + frameOffset
            for channel in 0..<channelCount {
                channelData[channel][frame] *= gain
            }
        }
    }
}
