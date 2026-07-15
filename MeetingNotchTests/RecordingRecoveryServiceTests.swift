import Foundation
import XCTest
@testable import MeetingNotch

final class RecordingRecoveryServiceTests: XCTestCase {
    private var root: URL!
    private var repository: FileMeetingRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RecordingRecoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        repository = FileMeetingRepository(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFinalizedCaptureLeftInTemporaryDirectoryIsImported() async throws {
        let capture = try makeFinalizedCapture(title: "Recovered", hasFinalAudio: true)
        let service = makeService()

        let report = await service.recoverInterruptedCaptures()

        XCTAssertEqual(report.recoveredMeetings.count, 1)
        XCTAssertEqual(report.recoveredMeetings.first?.title, "Recovered")
        XCTAssertEqual(report.preservedCount, 0)
        let meetings = try await repository.loadAll()
        XCTAssertEqual(meetings, report.recoveredMeetings)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: capture.session.audioFileURL!.deletingLastPathComponent().path
        ))
    }

    func testRawTracksAreFinalizedAndDurationIsReconstructed() async throws {
        let session = try makeInterruptedSession(title: "Raw Recovery")
        let temporaryAudioURL = root.appending(
            path: "Temporary/\(session.id.uuidString)/recording.m4a"
        )
        try Data("partial-audio".utf8).write(to: temporaryAudioURL)
        let service = makeService(duration: 125)

        let report = await service.recoverInterruptedCaptures()

        let meeting = try XCTUnwrap(report.recoveredMeetings.first)
        XCTAssertEqual(meeting.title, "Raw Recovery")
        XCTAssertEqual(meeting.duration, 125, accuracy: 0.001)
        XCTAssertEqual(report.preservedCount, 0)
        let audioURL = await repository.audioFileURL(for: meeting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertEqual(try Data(contentsOf: audioURL), Data("recovered-audio".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appending(path: "Temporary/\(session.id.uuidString)").path
        ))
    }

    func testUnreadableInterruptedCaptureIsPreservedInRecovery() async throws {
        try await repository.prepare()
        let id = UUID()
        let directory = root.appending(
            path: "Temporary/\(id.uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: directory.appending(path: "session.json"))

        let report = await makeService().recoverInterruptedCaptures()

        XCTAssertTrue(report.recoveredMeetings.isEmpty)
        XCTAssertEqual(report.preservedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let recoveryEntries = try FileManager.default.contentsOfDirectory(
            at: root.appending(path: "Recovery"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(recoveryEntries.count, 1)
        XCTAssertTrue(recoveryEntries[0].lastPathComponent.hasPrefix("Interrupted-\(id.uuidString)"))
    }

    private func makeService(duration: TimeInterval = 60) -> RecordingRecoveryService {
        RecordingRecoveryService(
            repository: repository,
            mixer: RecoveryTestMixer(),
            rootURL: root,
            durationLoader: { _ in duration }
        )
    }

    private func makeFinalizedCapture(
        title: String,
        hasFinalAudio: Bool
    ) throws -> RecordingCaptureResult {
        let session = try makeInterruptedSession(title: title)
        let directory = root.appending(
            path: "Temporary/\(session.id.uuidString)",
            directoryHint: .isDirectory
        )
        let audioURL = directory.appending(path: "recording.m4a")
        if hasFinalAudio {
            try Data("final".utf8).write(to: audioURL)
        }
        var completedSession = session
        completedSession.endedAt = session.startedAt.addingTimeInterval(90)
        completedSession.audioFileURL = hasFinalAudio ? audioURL : nil
        let capture = RecordingCaptureResult(
            session: completedSession,
            tracks: [
                CapturedAudioTrack(
                    source: .microphone,
                    fileURL: directory.appending(path: "microphone.m4a"),
                    firstSampleTime: 1
                ),
                CapturedAudioTrack(
                    source: .systemAudio,
                    fileURL: directory.appending(path: "system-audio.m4a"),
                    firstSampleTime: 1.1
                )
            ]
        )
        try encode(capture, to: directory.appending(path: "capture.json"))
        return capture
    }

    private func makeInterruptedSession(title: String) throws -> RecordingSession {
        let meeting = Meeting(
            title: title,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let session = RecordingSession(
            sourceMeeting: meeting,
            startedAt: meeting.startDate
        )
        let directory = root.appending(
            path: "Temporary/\(session.id.uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("microphone".utf8).write(to: directory.appending(path: "microphone.m4a"))
        try Data("system".utf8).write(to: directory.appending(path: "system-audio.m4a"))
        try encode(session, to: directory.appending(path: "session.json"))
        return session
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }
}

private actor RecoveryTestMixer: AudioTrackMixing {
    func mix(tracks: [CapturedAudioTrack], outputURL: URL) async throws -> URL {
        for track in tracks {
            guard FileManager.default.fileExists(atPath: track.fileURL.path) else {
                throw AudioMixError.missingSource(track.source)
            }
        }
        try Data("recovered-audio".utf8).write(to: outputURL)
        return outputURL
    }
}
