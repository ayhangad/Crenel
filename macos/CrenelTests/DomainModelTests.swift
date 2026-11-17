import XCTest
@testable import Crenel

final class DomainModelTests: XCTestCase {
    func testMeetingStableIdentifierIsDeterministicAndNamespaced() {
        let first = MeetingStableIdentifier.uuid(for: "calendar|event|100")
        let repeated = MeetingStableIdentifier.uuid(for: "calendar|event|100")
        let different = MeetingStableIdentifier.uuid(for: "calendar|event|101")

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual((first.uuid.6 & 0xf0) >> 4, 8)
        XCTAssertEqual(first.uuid.8 & 0xc0, 0x80)
    }

    func testMeetingRoundTripsThroughJSON() throws {
        let meeting = Meeting(
            title: "Ürün Toplantısı",
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_000),
            meetingURL: URL(string: "https://meet.google.com/example")
        )

        let data = try JSONEncoder().encode(meeting)
        let decoded = try JSONDecoder().decode(Meeting.self, from: data)

        XCTAssertEqual(decoded, meeting)
    }

    func testTranscriptRoundTripsThroughJSON() throws {
        let transcript = Transcript(
            text: "Merhaba.",
            languageCode: "tr",
            segments: [
                TranscriptSegment(
                    speakerID: "speaker_0",
                    speakerName: "Ayhan",
                    startTime: 0,
                    endTime: 1.2,
                    text: "Merhaba."
                )
            ]
        )

        let data = try JSONEncoder().encode(transcript)
        let decoded = try JSONDecoder().decode(Transcript.self, from: data)

        XCTAssertEqual(decoded, transcript)
    }

    func testArchivedTaskKeepsStableIdentity() throws {
        let id = UUID()
        let task = TaskItem(
            id: id,
            title: "Toplantı özetini paylaş",
            createdAt: Date(timeIntervalSince1970: 1_000),
            completedAt: Date(timeIntervalSince1970: 2_000)
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertFalse(decoded.isArchived)
        XCTAssertEqual(decoded.status, .completed)
        XCTAssertEqual(decoded.completedAt, Date(timeIntervalSince1970: 2_000))
    }

    func testTaskStatusAndArchiveHaveSeparateLifecycles() {
        let completionDate = Date(timeIntervalSince1970: 2_000)
        var task = TaskItem(title: "Durumlu görev", status: .inProgress)

        task.archive(at: Date(timeIntervalSince1970: 1_500))
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertTrue(task.isArchived)
        XCTAssertNil(task.completedAt)

        task.restore()
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertFalse(task.isArchived)

        task.setStatus(.completed, at: completionDate)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.completedAt, completionDate)
        // Crenel: completing never archives.
        XCTAssertNil(task.archivedAt)

        task.archive(at: completionDate)
        task.restore()
        XCTAssertEqual(task.status, .open)
        XCTAssertNil(task.completedAt)
        XCTAssertFalse(task.isArchived)
    }
}
