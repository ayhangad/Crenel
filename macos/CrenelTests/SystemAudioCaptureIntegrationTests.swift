import AVFoundation
import Foundation
import XCTest
@testable import Crenel

final class SystemAudioCaptureIntegrationTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard AudioIntegrationTestOptIn.isEnabled else {
            throw XCTSkip(
                "Gerçek sistem sesi testi opt-in çalışır: Scripts/audio-integration-tests.sh"
            )
        }

        outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CrenelSystemAudioPrototype-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    func testCapturesReadableM4AFromExternalSystemAudio() async throws {
        let outputURL = outputDirectory.appending(path: "system-audio-prototype.m4a")
        let source = SystemAudioCaptureSource(scope: .explicitManualGlobal)
        let levelProbe = SystemAudioLevelProbe()
        source.onLevelChange = { level in
            levelProbe.record(level)
        }

        do {
            try await source.prepare(outputURL: outputURL)
            try await source.start()
            try await Task.sleep(for: .milliseconds(350))
            try playSystemSound()
            try await Task.sleep(for: .seconds(2))

            let track = try await source.stop()
            let asset = AVURLAsset(url: track.fileURL)
            let duration = try await asset.load(.duration).seconds
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let fileSize = try XCTUnwrap(
                try track.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            )

            XCTAssertEqual(track.source, .systemAudio)
            XCTAssertEqual(track.fileURL, outputURL)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(track.firstSampleTime), 0)
            XCTAssertGreaterThan(duration, 1)
            XCTAssertEqual(audioTracks.count, 1)
            XCTAssertGreaterThan(fileSize, 2_048)
            XCTAssertGreaterThan(levelProbe.sampleCount, 0)
            XCTAssertGreaterThan(levelProbe.peakLevel, 0)
        } catch {
            await source.cancel()
            throw error
        }
    }

    @MainActor
    func testPermissionRequestStartsTapAndReturnsAuthorizedState() async throws {
        let suiteName = "SystemAudioPermissionIntegration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AudioCapturePermissionService(defaults: defaults)

        let snapshot = await service.requestSystemAudioAccess()

        XCTAssertEqual(snapshot.systemAudio, .authorized)
    }

    private func playSystemSound() throws {
        let player = Process()
        player.executableURL = URL(filePath: "/usr/bin/afplay")
        player.arguments = ["/System/Library/Sounds/Glass.aiff"]
        try player.run()
        player.waitUntilExit()
        XCTAssertEqual(player.terminationStatus, 0)
    }
}

private final class SystemAudioLevelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var levels: [Float] = []

    var sampleCount: Int {
        lock.withLock { levels.count }
    }

    var peakLevel: Float {
        lock.withLock { levels.max() ?? 0 }
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
