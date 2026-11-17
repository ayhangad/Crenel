import Foundation
import XCTest
@testable import Crenel

final class MeetingSummaryServiceTests: XCTestCase {
    func testExtractsOverviewExplicitDecisionActionOwnerAndDate() async throws {
        let transcript = Transcript(
            text: "",
            languageCode: "tr",
            segments: [
                TranscriptSegment(
                    speakerID: "speaker_0",
                    speakerName: "Ayşe",
                    startTime: 0,
                    endTime: 20,
                    text: "Bugün ürün kapsamını konuşuyoruz. Karar verdik: canlı transkript olmayacak. Raporu July 20, 2026 tarihinde hazırlayacağım."
                )
            ]
        )

        let summary = try await ExtractiveMeetingSummaryService().generate(from: transcript)

        XCTAssertTrue(summary.overview.contains("ürün kapsamını"))
        XCTAssertEqual(summary.decisions, ["Karar verdik: canlı transkript olmayacak"])
        XCTAssertEqual(summary.actionItems.count, 1)
        XCTAssertEqual(summary.actionItems.first?.assignee, "Ayşe")
        XCTAssertNotNil(summary.actionItems.first?.dueDate)
    }

    func testDoesNotInventDecisionActionOwnerOrDate() async throws {
        let transcript = Transcript(
            text: "Ekip mevcut ekranları inceledi ve kullanıcı geri bildirimlerini paylaştı.",
            languageCode: "tr",
            segments: []
        )

        let summary = try await ExtractiveMeetingSummaryService().generate(from: transcript)

        XCTAssertEqual(
            summary.overview,
            "Ekip mevcut ekranları inceledi ve kullanıcı geri bildirimlerini paylaştı"
        )
        XCTAssertTrue(summary.decisions.isEmpty)
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    func testMarkdownContainsNotesMetadataAndSpeakerTimestamps() {
        let meeting = StoredMeeting(
            id: UUID(),
            title: "Haftalık #Plan",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_125),
            sourceMeeting: nil,
            audioFileName: "recording.m4a",
            processingStatus: .completed
        )
        let stored = StoredTranscription(
            transcript: Transcript(
                text: "Merhaba",
                languageCode: "tr",
                segments: [TranscriptSegment(
                    speakerID: "speaker_0",
                    speakerName: "Ayşe",
                    startTime: 5,
                    endTime: 8,
                    text: "Merhaba"
                )]
            ),
            summary: MeetingSummary(
                overview: "Kapsam konuşuldu.",
                decisions: ["V1 kapsamı korundu."],
                actionItems: [ActionItem(title: "Testleri çalıştır.", assignee: "Ayşe")]
            )
        )

        let markdown = MeetingMarkdownFormatter.markdown(
            meeting: meeting,
            transcription: stored
        )

        XCTAssertTrue(markdown.hasPrefix("# Haftalık \\#Plan"))
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("## Action items"))
        XCTAssertTrue(markdown.contains("## Transcript"))
        XCTAssertTrue(markdown.contains("### Ayşe · 00:05"))
        XCTAssertTrue(markdown.contains("ElevenLabs Scribe v2"))
    }
}
