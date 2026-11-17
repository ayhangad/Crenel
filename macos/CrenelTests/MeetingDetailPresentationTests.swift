import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import Crenel

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
            "Ayşe [00:05]\nMerhaba\n\nSpeaker 2 [01:05]\nDünya"
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

    func testLongTranscriptAvoidsNativeInlineSelectionPerRow() {
        XCTAssertTrue(
            TranscriptPresentationPolicy.allowsInlineTextSelection(
                segmentCount: TranscriptPresentationPolicy.inlineSelectionSegmentLimit
            )
        )
        XCTAssertFalse(
            TranscriptPresentationPolicy.allowsInlineTextSelection(
                segmentCount: TranscriptPresentationPolicy.inlineSelectionSegmentLimit + 1
            )
        )
        XCTAssertFalse(
            TranscriptPresentationPolicy.allowsInlineTextSelection(segmentCount: 390)
        )
    }

    @MainActor
    func testLongTranscriptDetailHandlesRepeatedScrollEventsResponsively() throws {
        let segments = (0..<390).map { index in
            TranscriptSegment(
                speakerID: "speaker_\(index % 3)",
                startTime: TimeInterval(index * 7),
                endTime: TimeInterval(index * 7 + 6),
                text: "Uzun toplantı regresyon segmenti \(index). Karar ve takip notları burada yer alır."
            )
        }
        let meeting = StoredMeeting(
            id: UUID(),
            title: "Uzun toplantı regresyonu",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_000),
            sourceMeeting: nil,
            audioFileName: "missing-test-audio.m4a",
            processingStatus: .completed
        )
        let content = MeetingDetailContent(
            meeting: meeting,
            storedTranscription: StoredTranscription(
                transcript: Transcript(text: "", languageCode: "tr", segments: segments),
                summary: nil
            ),
            markdown: nil,
            audioURL: URL(fileURLWithPath: "/tmp/missing-test-audio.m4a")
        )
        let rootView = ScrollView {
            MeetingDetailView(
                content: content,
                onCopyText: { _ in },
                onExportMarkdown: { _ in },
                onRevealAudio: { _ in },
                onRetry: { _ in },
                onDelete: { _ in }
            )
        }
        .scrollIndicators(.hidden)
        .frame(width: 600, height: 600)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let scrollView = try XCTUnwrap(allScrollViews(in: hostingView).first)
        let downwardEvent = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -240,
                wheel2: 0,
                wheel3: 0
            ).flatMap(NSEvent.init(cgEvent:))
        )
        let upwardEvent = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: 240,
                wheel2: 0,
                wheel3: 0
            ).flatMap(NSEvent.init(cgEvent:))
        )

        let startedAt = CFAbsoluteTimeGetCurrent()
        for step in 0..<64 {
            scrollView.scrollWheel(with: step < 48 ? downwardEvent : upwardEvent)
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertLessThan(elapsed, 5, "390 segmentlik transcript kaydırması ana thread'i bloke etmemeli")
    }

    private func allScrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(allScrollViews(in:))
    }
}
