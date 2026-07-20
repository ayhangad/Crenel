import AVFoundation
import CoreMedia

enum SampleBufferPCMExtractor {
    static func copyPCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMSampleBufferError_InvalidMediaFormat))
        }

        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMSampleBufferError_InvalidSampleData))
        }

        var requiredBufferListSize = 0
        let sizingStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredBufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: nil
        )
        guard sizingStatus == noErr, requiredBufferListSize >= MemoryLayout<AudioBufferList>.size else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(sizingStatus))
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: requiredBufferListSize,
            alignment: 16
        )
        defer { rawBufferList.deallocate() }
        let sourceBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        let extractionStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceBufferList,
            bufferListSize: requiredBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard extractionStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(extractionStatus))
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourceBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMSampleBufferError_InvalidSampleData))
        }

        for index in sourceBuffers.indices {
            let source = sourceBuffers[index]
            let destinationCapacity = Int(destinationBuffers[index].mDataByteSize)
            let byteCount = Int(source.mDataByteSize)
            guard byteCount <= destinationCapacity,
                  byteCount == 0 || (source.mData != nil && destinationBuffers[index].mData != nil) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMSampleBufferError_InvalidSampleData))
            }
            if byteCount > 0 {
                memcpy(destinationBuffers[index].mData, source.mData, byteCount)
            }
            destinationBuffers[index].mDataByteSize = source.mDataByteSize
        }

        withExtendedLifetime(retainedBlockBuffer) {}
        return buffer
    }
}

enum AudioLevelMeter {
    static func normalizedLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let buffer = try? SampleBufferPCMExtractor.copyPCMBuffer(from: sampleBuffer) else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        let rms: Float
        if let channels = buffer.floatChannelData {
            let channel = channels[0]
            var sum: Float = 0
            for index in 0..<frameCount {
                let sample = channel[index]
                sum += sample * sample
            }
            rms = sqrt(sum / Float(frameCount))
        } else if let channels = buffer.int16ChannelData {
            let channel = channels[0]
            var sum: Float = 0
            for index in 0..<frameCount {
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
