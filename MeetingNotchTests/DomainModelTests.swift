import XCTest
@testable import MeetingNotch

final class DomainModelTests: XCTestCase {
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
        XCTAssertTrue(decoded.isArchived)
    }
}
