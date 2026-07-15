import Foundation
import XCTest
@testable import MeetingNotch

final class MeetingDetailPresentationTests: XCTestCase {
    func testTranscriptPlainTextIncludesSpeakerNamesAndTimestamps() {
        let transcript = Transcript(
            text: "Merhaba Dünya",
            languageCode: "tr",
            segments: [
                TranscriptSegment(
                    speakerID: "speaker_0",
                    speakerName: "Ayşe",
                    startTime: 5,
                    endTime: 8,
                    text: " Merhaba "
                ),
                TranscriptSegment(
                    speakerID: "speaker_1",
                    startTime: 65,
                    endTime: 70,
                    text: "Dünya"
                )
            ]
        )

        XCTAssertEqual(
            TranscriptTextFormatter.plainText(transcript),
            "Ayşe [00:05]\nMerhaba\n\nKonuşmacı 2 [01:05]\nDünya"
        )
    }

    func testTimestampSupportsLongMeetingsAndClampsNegativeValues() {
        XCTAssertEqual(TranscriptTextFormatter.timestamp(-12), "00:00")
        XCTAssertEqual(TranscriptTextFormatter.timestamp(3_725), "1:02:05")
    }

    func testLargeTranscriptFormattingKeepsEverySegment() {
        let segments = (0..<10_000).map { index in
            TranscriptSegment(
                speakerID: "speaker_\(index % 3)",
                startTime: TimeInterval(index),
                endTime: TimeInterval(index + 1),
                text: "Sentetik segment \(index)"
            )
        }
        let transcript = Transcript(text: "", languageCode: "tr", segments: segments)

        let output = TranscriptTextFormatter.plainText(transcript)

        XCTAssertTrue(output.contains("Sentetik segment 0"))
        XCTAssertTrue(output.contains("Sentetik segment 9999"))
    }
}
