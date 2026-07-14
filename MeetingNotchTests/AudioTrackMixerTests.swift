import AVFoundation
import Foundation
import XCTest
@testable import MeetingNotch

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

    private func makeTone(at url: URL, duration: TimeInterval, frequency: Double) throws {
        try autoreleasepool {
            let sampleRate = 48_000.0
            let frameCount = AVAudioFrameCount(sampleRate * duration)
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            let samples = buffer.floatChannelData![0]
            for frame in 0..<Int(frameCount) {
                samples[frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate) * 0.2)
            }

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
}
