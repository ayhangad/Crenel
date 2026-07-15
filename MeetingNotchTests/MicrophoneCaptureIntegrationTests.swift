import AVFoundation
import Foundation
import XCTest
@testable import MeetingNotch

final class MicrophoneCaptureIntegrationTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard ProcessInfo.processInfo.environment["MEETINGNOTCH_RUN_AUDIO_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip(
                "Gerçek mikrofon testi opt-in çalışır: "
                    + "MEETINGNOTCH_RUN_AUDIO_INTEGRATION_TESTS=1"
            )
        }

        outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotchMicrophonePrototype-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let outputDirectory {
            try? FileManager.default.removeItem(at: outputDirectory)
        }
        try super.tearDownWithError()
    }

    func testCapturesReadableM4AFromPhysicalMicrophone() async throws {
        let outputURL = outputDirectory.appending(path: "microphone-prototype.m4a")
        let source = MicrophoneCaptureSource()
        let levelProbe = AudioLevelProbe()
        source.onLevelChange = { level in
            levelProbe.record(level)
        }

        do {
            try await source.prepare(outputURL: outputURL)
            try await source.start()
            try await Task.sleep(for: .seconds(3))

            let track = try await source.stop()
            let asset = AVURLAsset(url: track.fileURL)
            let duration = try await asset.load(.duration).seconds
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let fileSize = try XCTUnwrap(
                try track.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            )

            XCTAssertEqual(track.source, .microphone)
            XCTAssertEqual(track.fileURL, outputURL)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(track.firstSampleTime), 0)
            XCTAssertGreaterThan(duration, 2)
            XCTAssertEqual(audioTracks.count, 1)
            XCTAssertGreaterThan(fileSize, 2_048)
            XCTAssertGreaterThan(levelProbe.sampleCount, 0)
            XCTAssertTrue(levelProbe.areLevelsNormalized)
        } catch {
            await source.cancel()
            throw error
        }
    }
}

private final class AudioLevelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var levels: [Float] = []

    var sampleCount: Int {
        lock.withLock { levels.count }
    }

    var areLevelsNormalized: Bool {
        lock.withLock { levels.allSatisfy { (0 ... 1).contains($0) } }
    }

    func record(_ level: Float) {
        lock.withLock {
            levels.append(level)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
