import AVFoundation
import CoreMedia

enum AudioLevelMeter {
    static func normalizedLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: AVAudioFormat(cmAudioFormatDescription: formatDescription),
                frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
            )
        else {
            return 0
        }

        let frameCount = Int32(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return 0 }

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: frameCount,
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return 0 }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let rms: Float
        if let channels = buffer.floatChannelData {
            let channel = channels[0]
            var sum: Float = 0
            for index in 0..<Int(frameCount) {
                let sample = channel[index]
                sum += sample * sample
            }
            rms = sqrt(sum / Float(frameCount))
        } else if let channels = buffer.int16ChannelData {
            let channel = channels[0]
            var sum: Float = 0
            for index in 0..<Int(frameCount) {
                let sample = Float(channel[index]) / Float(Int16.max)
                sum += sample * sample
            }
            rms = sqrt(sum / Float(frameCount))
        } else {
            return 0
        }

        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
