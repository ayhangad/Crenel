import CoreGraphics
import XCTest
@testable import Crenel

final class MeetingExportTests: XCTestCase {
    private let meeting = StoredMeeting(
        id: UUID(),
        title: "Weekly #Plan",
        startedAt: Date(timeIntervalSince1970: 1_800_000_000),
        endedAt: Date(timeIntervalSince1970: 1_800_000_125),
        sourceMeeting: nil,
        audioFileName: "recording.m4a",
        processingStatus: .completed
    )

    private func stored(segments: [TranscriptSegment], summary: MeetingSummary? = nil) -> StoredTranscription {
        StoredTranscription(
            transcript: Transcript(text: segments.map(\.text).joined(separator: " "), languageCode: "en", segments: segments),
            summary: summary
        )
    }

    func testPlainTextHasNotesAndTranscriptWithoutMarkdown() {
        let transcription = stored(
            segments: [
                TranscriptSegment(speakerID: "speaker_0", speakerName: "Ayşe", startTime: 5, endTime: 8, text: " Hello there. "),
                TranscriptSegment(speakerID: "speaker_1", speakerName: nil, startTime: 65, endTime: 70, text: "Ship it on Friday.")
            ],
            summary: MeetingSummary(
                overview: "Scope was agreed.",
                decisions: ["Keep the V1 scope."],
                actionItems: [ActionItem(title: "Run the tests.", assignee: "Ayşe")]
            )
        )

        let text = MeetingPlainTextFormatter.text(meeting: meeting, transcription: transcription)

        XCTAssertTrue(text.hasPrefix("Weekly #Plan\n"))
        XCTAssertTrue(text.contains("SUMMARY\n\nScope was agreed."))
        XCTAssertTrue(text.contains("DECISIONS\n\n• Keep the V1 scope."))
        XCTAssertTrue(text.contains("ACTION ITEMS\n\n• Run the tests. (Ayşe)"))
        XCTAssertTrue(text.contains("TRANSCRIPT\n\nAyşe · 00:05\nHello there.\n\n"))
        XCTAssertTrue(text.contains("\(TranscriptTextFormatter.fallbackSpeakerName("speaker_1")) · 01:05\nShip it on Friday."))
        XCTAssertFalse(text.contains("## "))
        XCTAssertFalse(text.contains("\\#"))
        XCTAssertFalse(text.contains("- "))
        XCTAssertFalse(text.contains("_("))
        XCTAssertFalse(text.contains("\n\n\n"))
        XCTAssertTrue(text.hasSuffix("Friday.\n"))
    }

    func testPlainTextWithoutSummaryOrSegmentsKeepsTheText() {
        let transcription = StoredTranscription(
            transcript: Transcript(text: "Just one block of speech.", languageCode: nil, segments: [])
        )

        let text = MeetingPlainTextFormatter.text(meeting: meeting, transcription: transcription)

        XCTAssertFalse(text.contains("SUMMARY"))
        XCTAssertTrue(text.hasSuffix("TRANSCRIPT\n\nJust one block of speech.\n"))
    }

    func testPDFPaginatesALongTranscript() throws {
        let sentence = "We walked through the release checklist and agreed who signs off on each step. "
        let segments = (0..<120).map { index in
            TranscriptSegment(
                speakerID: "speaker_\(index % 3)",
                speakerName: nil,
                startTime: TimeInterval(index * 20),
                endTime: TimeInterval(index * 20 + 18),
                text: String(repeating: sentence, count: 3)
            )
        }

        for paper in [MeetingPDFRenderer.PaperSize.a4, .letter] {
            let data = MeetingPDFRenderer.pdfData(meeting: meeting, transcription: stored(segments: segments), paper: paper)
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            let document = try XCTUnwrap(CGPDFDocument(provider))
            XCTAssertGreaterThan(document.numberOfPages, 1)
            let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
            XCTAssertEqual(box.size.width, paper.points.width, accuracy: 0.5)
            XCTAssertEqual(box.size.height, paper.points.height, accuracy: 0.5)
        }
    }

    func testPDFOfAShortMeetingIsOnePage() throws {
        let transcription = stored(segments: [
            TranscriptSegment(speakerID: "speaker_0", speakerName: "Ayşe", startTime: 0, endTime: 2, text: "Short.")
        ])
        let data = MeetingExportFormat.pdf.data(meeting: meeting, transcription: transcription)
        let document = try XCTUnwrap(CGPDFDocument(XCTUnwrap(CGDataProvider(data: data as CFData))))
        XCTAssertEqual(document.numberOfPages, 1)
    }
}
