import Foundation
import XCTest
@testable import MeetingNotch

final class FileMeetingRepositoryTests: XCTestCase {
    private var root: URL!
    private var repository: FileMeetingRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "MeetingRepositoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        repository = FileMeetingRepository(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPrepareCreatesApplicationDirectories() async throws {
        try await repository.prepare()

        for name in ["Meetings", "Tasks", "Temporary", "Recovery"] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: root.appending(path: name).path,
                isDirectory: &isDirectory
            ))
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testSaveIsAtomicCleansTemporaryFilesAndLoadsAfterRestart() async throws {
        let capture = try makeCapture(
            title: "Ürün / Haftalık: Plan?",
            startedAt: Date(timeIntervalSince1970: 1_720_980_000)
        )

        let stored = try await repository.saveCapture(capture)

        XCTAssertEqual(stored.schemaVersion, StoredMeeting.currentSchemaVersion)
        XCTAssertFalse(stored.audioFileName.contains("/"))
        XCTAssertTrue(stored.audioFileName.hasSuffix(".m4a"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: capture.session.audioFileURL!.deletingLastPathComponent().path
        ))

        let finalDirectory = root.appending(path: "Meetings/\(stored.id.uuidString)")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: finalDirectory.appending(path: "metadata.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: finalDirectory.appending(path: stored.audioFileName).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: finalDirectory.appending(path: "microphone.m4a").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: finalDirectory.appending(path: "system-audio.m4a").path
        ))

        let restartedRepository = FileMeetingRepository(rootURL: root)
        let restartedMeetings = try await restartedRepository.loadAll()
        XCTAssertEqual(restartedMeetings, [stored])
    }

    func testLoadSortsNewestFirstAndConcurrentSavesAreSerialized() async throws {
        let oldCapture = try makeCapture(
            title: "Old",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newCapture = try makeCapture(
            title: "New",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        async let oldMeeting = repository.saveCapture(oldCapture)
        async let newMeeting = repository.saveCapture(newCapture)
        _ = try await [oldMeeting, newMeeting]

        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.map(\.title), ["New", "Old"])
    }

    func testCorruptAndIncompleteDirectoriesMoveToRecovery() async throws {
        try await repository.prepare()
        let corrupt = root.appending(path: "Meetings/corrupt", directoryHint: .isDirectory)
        let staging = root.appending(path: "Meetings/.staging-leftover", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: corrupt.appending(path: "metadata.json"))

        let loaded = try await repository.loadAll()
        XCTAssertTrue(loaded.isEmpty)

        let recoveryEntries = try FileManager.default.contentsOfDirectory(
            at: root.appending(path: "Recovery"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(recoveryEntries.count, 2)
        XCTAssertTrue(recoveryEntries.contains { $0.lastPathComponent.hasPrefix("Corrupt-") })
        XCTAssertTrue(recoveryEntries.contains { $0.lastPathComponent.hasPrefix("Incomplete-") })
    }

    func testMetadataCannotReferenceAudioOutsideItsMeetingDirectory() async throws {
        try await repository.prepare()
        let meeting = StoredMeeting(
            id: UUID(),
            title: "Unsafe",
            startedAt: .now,
            endedAt: .now,
            sourceMeeting: nil,
            audioFileName: "../outside.m4a"
        )
        let directory = root.appending(
            path: "Meetings/\(meeting.id.uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meeting).write(to: directory.appending(path: "metadata.json"))
        try Data("outside".utf8).write(to: root.appending(path: "Meetings/outside.m4a"))

        let loaded = try await repository.loadAll()

        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDeleteRemovesMeetingAndAllLinkedFiles() async throws {
        let stored = try await repository.saveCapture(try makeCapture(title: "Delete", startedAt: .now))

        try await repository.delete(id: stored.id)

        let loaded = try await repository.loadAll()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appending(path: "Meetings/\(stored.id.uuidString)").path
        ))
    }

    func testSaveTranscriptionPersistsSummaryAndMarkdownAtomically() async throws {
        let meeting = try await repository.saveCapture(
            try makeCapture(title: "Markdown Meeting", startedAt: .now)
        )
        let transcript = Transcript(
            text: "Karar verdik: V1 devam edecek.",
            languageCode: "tr",
            segments: [TranscriptSegment(
                speakerID: "speaker_0",
                startTime: 3,
                endTime: 6,
                text: "Karar verdik: V1 devam edecek."
            )]
        )
        let summary = MeetingSummary(
            overview: "V1 kapsamı konuşuldu.",
            decisions: ["V1 devam edecek."],
            actionItems: []
        )

        let updated = try await repository.saveTranscription(
            TranscriptionResult(transcript: transcript),
            summary: summary,
            for: meeting
        )

        XCTAssertEqual(updated.processingStatus, .completed)
        let loadedTranscription = try await repository.loadTranscription(for: meeting.id)
        let stored = try XCTUnwrap(loadedTranscription)
        XCTAssertEqual(stored.summary, summary)
        let loadedMarkdown = try await repository.loadMarkdown(for: meeting.id)
        let markdown = try XCTUnwrap(loadedMarkdown)
        XCTAssertTrue(markdown.contains("# Markdown Meeting"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("V1 devam edecek."))
        let directory = root.appending(path: "Meetings/\(meeting.id.uuidString)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "meeting.md").path))
    }

    func testFileNameSanitizesAndLimitsLongTitles() {
        let title = String(repeating: "Çok/Uzun:*? Başlık ", count: 20)
        let fileName = MeetingFileName.audioFileName(
            title: title,
            startedAt: Date(timeIntervalSince1970: 0),
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.contains(":"))
        XCTAssertLessThan(fileName.count, 90)
        XCTAssertTrue(fileName.hasSuffix("_aaaaaaaa.m4a"))
    }

    func testRenamingSpeakerPersistsAcrossReloadAndUpdatesActionOwnership() async throws {
        let meeting = try await repository.saveCapture(try makeCapture(title: "İsimsiz Toplantı", startedAt: .now))
        let segment = TranscriptSegment(speakerID: "speaker_0", startTime: 45, endTime: 50, text: "Teklifi ben göndereceğim.")
        let transcript = Transcript(text: segment.text, languageCode: "tr", segments: [segment])
        let summary = MeetingSummary(overview: "Teklif görüşüldü.", decisions: [], actionItems: [
            ActionItem(title: "Teklifi gönder", speakerID: "speaker_0", sourceSegmentID: segment.id, sourceTime: 45)
        ], suggestedTitle: "Teklif görüşmesi", model: "fixture")
        _ = try await repository.saveTranscription(.init(transcript: transcript), summary: summary, for: meeting)
        let metadataURL = root.appending(path: "Meetings/\(meeting.id.uuidString)/metadata.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(StoredMeeting.self, from: Data(contentsOf: metadataURL))
        XCTAssertFalse(metadata.summaryNeedsAttention ?? true)
        let audioURL = await repository.audioFileURL(for: metadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.map(\.id), [meeting.id])
        let renamed = try await repository.renameSpeaker(meetingID: meeting.id, speakerID: "speaker_0", name: "Ayşe")
        XCTAssertEqual(renamed.title, "Teklif görüşmesi")
        let restarted = FileMeetingRepository(rootURL: root)
        let stored = try await restarted.loadTranscription(for: meeting.id)
        XCTAssertEqual(stored?.transcript.segments.first?.speakerName, "Ayşe")
        XCTAssertEqual(stored?.summary?.actionItems.first?.assignee, "Ayşe")
        let markdown = try await restarted.loadMarkdown(for: meeting.id)
        XCTAssertTrue(markdown?.contains("Ayşe") == true)
        XCTAssertTrue(markdown?.contains("00:45") == true)
    }

    private func makeCapture(title: String, startedAt: Date) throws -> RecordingCaptureResult {
        let id = UUID()
        let directory = root
            .appending(path: "Temporary", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let finalAudio = directory.appending(path: "recording.m4a")
        let microphone = directory.appending(path: "microphone.m4a")
        let systemAudio = directory.appending(path: "system-audio.m4a")
        try Data("final".utf8).write(to: finalAudio)
        try Data("microphone".utf8).write(to: microphone)
        try Data("system".utf8).write(to: systemAudio)

        let meeting = Meeting(
            title: title,
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(1_800)
        )
        let session = RecordingSession(
            id: id,
            meetingID: meeting.id,
            sourceMeeting: meeting,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            audioFileURL: finalAudio
        )
        return RecordingCaptureResult(
            session: session,
            tracks: [
                CapturedAudioTrack(source: .microphone, fileURL: microphone, firstSampleTime: 1),
                CapturedAudioTrack(source: .systemAudio, fileURL: systemAudio, firstSampleTime: 1)
            ]
        )
    }
}
