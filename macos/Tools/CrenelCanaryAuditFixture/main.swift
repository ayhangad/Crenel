import AVFoundation
import Foundation

guard CommandLine.arguments.count == 4,
      let frequency = Double(CommandLine.arguments[2]) else {
    FileHandle.standardError.write(Data("usage: fixture <directory> <frequency> <transcript-text>\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let sampleRate = 48_000.0
let duration = 0.5
let frameCount = AVAudioFrameCount(sampleRate * duration)
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
buffer.frameLength = frameCount
let samples = buffer.floatChannelData![0]
for frame in 0..<Int(frameCount) {
    samples[frame] = Float(0.7 * sin(2 * .pi * frequency * Double(frame) / sampleRate))
}

var file: AVAudioFile? = try AVAudioFile(
    forWriting: directory.appending(path: "fixture.m4a"),
    settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000
    ]
)
try file?.write(from: buffer)
file = nil

let transcript: [String: Any] = [
    "text": CommandLine.arguments[3],
    "segments": [["text": CommandLine.arguments[3]]]
]
let transcriptData = try JSONSerialization.data(withJSONObject: transcript, options: [.sortedKeys])
try transcriptData.write(to: directory.appending(path: "transcript.json"), options: .atomic)
