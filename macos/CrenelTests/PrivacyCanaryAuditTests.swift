import AVFoundation
import CoreMedia
import XCTest
@testable import Crenel

@MainActor
final class PrivacyCanaryAuditTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let canaryFrequency = 997.0
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "CrenelPrivacyCanary-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testClosedUniqueCanaryIsAbsentFromRawMicSystemMixAndTranscript() async throws {
        let microphoneURL = directory.appending(path: "microphone.m4a")
        let systemURL = directory.appending(path: "system.m4a")
        let mixedURL = directory.appending(path: "recording.m4a")
        let writer = SampleBufferAudioWriter(outputURL: microphoneURL, source: .microphone)

        for index in 0..<5 {
            writer.append(
                makeToneBuffer(frequency: canaryFrequency, duration: 0.1),
                presentationTime: CMTime(
                    seconds: 20 + (Double(index) * 0.1),
                    preferredTimescale: 48_000
                ),
                microphoneGateState: index == 2 ? .unknown : .closed
            )
        }
        let finishedMicrophoneStart = try await writer.finish()
        let microphoneStart = try XCTUnwrap(finishedMicrophoneStart)
        try writeTone(to: systemURL, frequency: 440, duration: 0.5)

        _ = try await AudioTrackMixer().mix(
            tracks: [
                CapturedAudioTrack(
                    source: .microphone,
                    fileURL: microphoneURL,
                    firstSampleTime: microphoneStart
                ),
                CapturedAudioTrack(
                    source: .systemAudio,
                    fileURL: systemURL,
                    firstSampleTime: microphoneStart
                )
            ],
            outputURL: mixedURL
        )

        XCTAssertLessThan(try toneAmplitude(in: microphoneURL, frequency: canaryFrequency), 0.01)
        XCTAssertLessThan(try toneAmplitude(in: systemURL, frequency: canaryFrequency), 0.02)
        XCTAssertLessThan(try toneAmplitude(in: mixedURL, frequency: canaryFrequency), 0.02)

        let uniquePhrase = "kehribar pusula yedi kırmızı lale"
        let transcript = Transcript(
            text: "Toplantının güvenli bölümünde konuşulan içerik.",
            languageCode: "tr",
            segments: []
        )
        XCTAssertFalse(transcript.text.localizedCaseInsensitiveContains(uniquePhrase))
        XCTAssertFalse(
            transcript.segments.contains {
                $0.text.localizedCaseInsensitiveContains(uniquePhrase)
            }
        )
    }

    func testRapidMuteUnmuteAndBluetoothRateChangePreserveTimeline() async throws {
        let outputURL = directory.appending(path: "rapid-gate.m4a")
        let writer = SampleBufferAudioWriter(outputURL: outputURL, source: .microphone)
        let states: [MeetingMicrophoneState] = [
            .closed, .open, .closed, .unknown, .open, .closed
        ]

        for (index, state) in states.enumerated() {
            let inputRate = index < 3 ? 24_000.0 : 48_000.0
            writer.append(
                makeToneBuffer(
                    frequency: index.isMultiple(of: 2) ? canaryFrequency : 440,
                    duration: 0.1,
                    sampleRate: inputRate
                ),
                presentationTime: CMTime(
                    seconds: 30 + (Double(index) * 0.1),
                    preferredTimescale: 48_000
                ),
                microphoneGateState: state
            )
        }

        let finishedStart = try await writer.finish()
        let firstSampleTime = try XCTUnwrap(finishedStart)
        XCTAssertEqual(firstSampleTime, 30, accuracy: 0.001)
        let duration = try await AVURLAsset(url: outputURL).load(.duration).seconds
        XCTAssertGreaterThan(duration, 0.55)
        XCTAssertLessThan(duration, 0.70)
    }

    private func makeToneBuffer(
        frequency: Double,
        duration: TimeInterval,
        sampleRate: Double? = nil
    ) -> AVAudioPCMBuffer {
        let resolvedRate = sampleRate ?? self.sampleRate
        let frames = AVAudioFrameCount(resolvedRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: resolvedRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frames) {
            let phase = 2 * Double.pi * frequency * Double(frame) / resolvedRate
            samples[frame] = Float(0.7 * sin(phase))
        }
        return buffer
    }

    private func writeTone(to url: URL, frequency: Double, duration: TimeInterval) throws {
        let buffer = makeToneBuffer(frequency: frequency, duration: duration)
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
        )
        try file.write(from: buffer)
    }

    private func toneAmplitude(in url: URL, frequency: Double) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let capacity = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: capacity
        )!
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let rate = file.processingFormat.sampleRate
        var sine = 0.0
        var cosine = 0.0
        for index in 0..<count {
            let phase = 2 * Double.pi * frequency * Double(index) / rate
            let sample = Double(samples[index])
            sine += sample * sin(phase)
            cosine += sample * cos(phase)
        }
        return 2 * hypot(sine, cosine) / Double(count)
    }
}
