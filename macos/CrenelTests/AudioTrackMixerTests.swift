import AVFoundation
import Foundation
import XCTest
@testable import Crenel

@MainActor
final class AudioTrackMixerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AudioTrackMixerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testMixesSourcesWithTimestampOffsetIntoReadableM4A() async throws {
        let microphoneURL = temporaryDirectory.appending(path: "microphone.m4a")
        let systemURL = temporaryDirectory.appending(path: "system.m4a")
        try makeTone(at: microphoneURL, duration: 0.25, frequency: 440)
        try makeTone(at: systemURL, duration: 0.25, frequency: 660)
        let outputURL = temporaryDirectory.appending(path: "recording.m4a")
        let mixer = AudioTrackMixer()

        _ = try await mixer.mix(
            tracks: [
                CapturedAudioTrack(source: .microphone, fileURL: microphoneURL, firstSampleTime: 10),
                CapturedAudioTrack(source: .systemAudio, fileURL: systemURL, firstSampleTime: 10.1)
            ],
            outputURL: outputURL
        )

        let asset = AVURLAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertGreaterThan(duration, 0.30)
        XCTAssertLessThan(duration, 0.50)
    }

    func testMissingSourceDoesNotLeavePartialOutput() async {
        let microphoneURL = temporaryDirectory.appending(path: "microphone.m4a")
        let outputURL = temporaryDirectory.appending(path: "recording.m4a")
        XCTAssertNoThrow(try makeTone(at: microphoneURL, duration: 0.1, frequency: 440))

        do {
            _ = try await AudioTrackMixer().mix(
                tracks: [CapturedAudioTrack(
                    source: .microphone,
                    fileURL: microphoneURL,
                    firstSampleTime: 1
                )],
                outputURL: outputURL
            )
            XCTFail("Mix should fail")
        } catch let error as AudioMixError {
            XCTAssertEqual(error, .missingSource(.systemAudio))
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMicrophoneWriterNormalizesBluetoothRateAndFormatChanges() async throws {
        let outputURL = temporaryDirectory.appending(path: "microphone-normalized.m4a")
        let writer = SampleBufferAudioWriter(outputURL: outputURL, source: .microphone)

        for index in 0..<4 {
            let sampleRate = index < 2 ? 24_000.0 : 48_000.0
            let buffer = makeToneBuffer(
                sampleRate: sampleRate,
                duration: 0.1,
                frequency: 440
            )
            writer.append(
                buffer,
                presentationTime: CMTime(
                    seconds: 10 + (Double(index) * 0.1),
                    preferredTimescale: 48_000
                ),
                microphoneGateState: .open
            )
        }

        let firstSampleTime = try await writer.finish()
        let file = try AVAudioFile(forReading: outputURL)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds

        XCTAssertEqual(try XCTUnwrap(firstSampleTime), 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(writer.lastSampleTime), 10.4, accuracy: 0.001)
        XCTAssertEqual(file.fileFormat.sampleRate, 48_000, accuracy: 0.1)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertGreaterThan(duration, 0.35)
        XCTAssertLessThan(duration, 0.50)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testClockDriftPolicyCorrectsOnlyBoundedLongRunningDrift() {
        let policy = AudioClockDriftPolicy()

        XCTAssertEqual(
            policy.playbackRate(
                fileDuration: 3_603.6,
                capturedTimelineDuration: 3_600
            ),
            1.001,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            policy.playbackRate(fileDuration: 30.1, capturedTimelineDuration: 30),
            1
        )
        XCTAssertEqual(
            policy.playbackRate(fileDuration: 3_700, capturedTimelineDuration: 3_600),
            1
        )
    }

    func testSoftLimiterPreservesNormalSamplesAndBoundsHotMixes() {
        XCTAssertEqual(AudioSampleLimiter.limited(0.5), 0.5)
        XCTAssertEqual(AudioSampleLimiter.limited(-0.5), -0.5)
        XCTAssertLessThanOrEqual(AudioSampleLimiter.limited(1.5), 0.999)
        XCTAssertGreaterThanOrEqual(AudioSampleLimiter.limited(-1.5), -0.999)
        XCTAssertEqual(AudioSampleLimiter.limited(.infinity), 0)
    }

    func testMixerAppliesTimestampBasedDriftCorrectionToRenderedDuration() async throws {
        let microphoneURL = temporaryDirectory.appending(path: "drift-microphone.m4a")
        let systemURL = temporaryDirectory.appending(path: "drift-system.m4a")
        try makeTone(at: microphoneURL, duration: 0.5, frequency: 440)
        try makeTone(at: systemURL, duration: 0.5, frequency: 660)
        let outputURL = temporaryDirectory.appending(path: "drift-recording.m4a")
        let mixer = AudioTrackMixer(driftPolicy: AudioClockDriftPolicy(minimumDuration: 0))

        _ = try await mixer.mix(
            tracks: [
                CapturedAudioTrack(
                    source: .microphone,
                    fileURL: microphoneURL,
                    firstSampleTime: 10,
                    lastSampleTime: 10.51
                ),
                CapturedAudioTrack(
                    source: .systemAudio,
                    fileURL: systemURL,
                    firstSampleTime: 10,
                    lastSampleTime: 10.51
                )
            ],
            outputURL: outputURL
        )

        let duration = try await AVURLAsset(url: outputURL).load(.duration).seconds
        XCTAssertGreaterThan(duration, 0.505)
        XCTAssertLessThan(duration, 0.54)
    }

    private func makeTone(at url: URL, duration: TimeInterval, frequency: Double) throws {
        try autoreleasepool {
            let sampleRate = 48_000.0
            let buffer = makeToneBuffer(
                sampleRate: sampleRate,
                duration: duration,
                frequency: frequency
            )

            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 96_000
                ]
            )
            try file.write(from: buffer)
        }
    }

    private func makeToneBuffer(
        sampleRate: Double,
        duration: TimeInterval,
        frequency: Double
    ) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate) * 0.2)
        }
        return buffer
    }
}
