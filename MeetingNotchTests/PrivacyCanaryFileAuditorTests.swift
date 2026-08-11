import AVFoundation
import XCTest
@testable import MeetingNotch

final class PrivacyCanaryFileAuditorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotchCanaryFileAudit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDetectsForbiddenToneAndDurationFailureInReadableM4A() throws {
        let url = directory.appending(path: "leaking.m4a")
        try writeTone(to: url, frequency: 997, duration: 0.5)

        let result = try PrivacyCanaryFileAuditor().auditAudio(
            at: url,
            toneFrequency: 997,
            maximumToneAmplitude: 0.02,
            minimumDurationSeconds: 1
        )

        XCTAssertGreaterThan(result.maximumToneAmplitude, 0.5)
        XCTAssertEqual(result.durationSeconds, 0.5, accuracy: 0.03)
        XCTAssertFalse(result.passed)
    }

    func testPassesWhenForbiddenToneIsAbsent() throws {
        let url = directory.appending(path: "isolated.m4a")
        try writeTone(to: url, frequency: 440, duration: 0.5)

        let result = try PrivacyCanaryFileAuditor().auditAudio(
            at: url,
            toneFrequency: 997,
            maximumToneAmplitude: 0.02,
            minimumDurationSeconds: 0.4
        )

        XCTAssertLessThan(result.maximumToneAmplitude, 0.02)
        XCTAssertTrue(result.passed)
    }

    func testTranscriptAuditNormalizesJSONStringsCaseWhitespaceAndDiacritics() throws {
        let url = directory.appending(path: "transcript.json")
        try Data(#"{"segments":[{"text":"KEHRİBAR   pusula yedi kırmızı lâle"}]}"#.utf8)
            .write(to: url)

        let result = try PrivacyCanaryFileAuditor().auditTranscript(
            at: url,
            forbiddenPhrases: ["kehribar pusula yedi kırmızı lale", "bulunmayan cümle"]
        )

        XCTAssertEqual(result.forbiddenPhraseCount, 2)
        XCTAssertEqual(result.matchedPhrases, ["kehribar pusula yedi kırmızı lale"])
        XCTAssertFalse(result.passed)
    }

    func testRejectsThresholdOrDurationThatCouldBypassAudit() {
        XCTAssertThrowsError(
            try PrivacyCanaryFileAuditor().audit(
                audioURLs: [],
                transcriptURLs: [],
                forbiddenPhrases: [],
                maximumToneAmplitude: 1.1
            )
        ) { error in
            XCTAssertEqual(error as? PrivacyCanaryFileAuditError, .invalidThreshold(1.1))
        }
        XCTAssertThrowsError(
            try PrivacyCanaryFileAuditor().audit(
                audioURLs: [],
                transcriptURLs: [],
                forbiddenPhrases: [],
                minimumDurationSeconds: -1
            )
        ) { error in
            XCTAssertEqual(error as? PrivacyCanaryFileAuditError, .invalidMinimumDuration(-1))
        }
    }

    private func writeTone(to url: URL, frequency: Double, duration: TimeInterval) throws {
        let sampleRate = 48_000.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(0.7 * sin(2 * .pi * frequency * Double(frame) / sampleRate))
        }
        var file: AVAudioFile? = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
        )
        try file?.write(from: buffer)
        file = nil
    }
}
