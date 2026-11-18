import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import Crenel

/// Recordings (history) and the meeting detail inside the open notch: logic checks plus
/// an offscreen render of every prototype state. PNGs are written to
/// `artifacts/ui-audit/recordings/<state>.png` when `/tmp/CrenelExportUIAudit`
/// exists, to be compared with `/tmp/proto/<state>.png`.
@MainActor
final class RecordingsGalleryTests: XCTestCase {
    private var calendar: Calendar { Calendar.current }

    /// Tue 17 Nov 2026 10:42, the prototype's clock.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 42))!
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: Logic

    func testWeekMeterAddsUpTheCurrentWeekAndLightsToday() {
        let week = RecordingsWeek(meetings: historyMeetings + [
            meeting("Last week", start: date(10, 9, 0), seconds: 3_600)
        ], now: now, calendar: calendar)

        // 16 Nov: 2:10 + 1:40:00, 17 Nov: 48:12 + 31:40 — last week is not counted.
        XCTAssertEqual(week.total, 130 + 6_000 + 2_892 + 1_900, accuracy: 0.5)
        XCTAssertEqual(RecordingsFormat.hours(week.total), "3h\u{2009}02m")
        XCTAssertEqual(week.days.filter(\.isToday).count, 1)
        let today = try? XCTUnwrap(week.days.first(where: \.isToday))
        let monday = try? XCTUnwrap(week.days.first { $0.recorded > 6_000 })
        XCTAssertEqual(today.map(week.lit), 5)
        XCTAssertEqual(monday.map(week.lit), RecordingsWeek.cells)
        XCTAssertTrue(week.days.filter { $0.recorded == 0 }.allSatisfy { week.lit($0) == 0 })
        // Empty weekend days are left out; weekdays always show.
        XCTAssertEqual(week.days.count, 5)
    }

    func testRowsOnlySpeakWhenTheyNeedAttention() {
        var noNotes = meeting("A", start: now, seconds: 60, status: .completed)
        noNotes.summaryNeedsAttention = true
        XCTAssertEqual(RecordingAttention(meeting("A", start: now, seconds: 60, status: .completed)), .none)
        XCTAssertNil(RecordingAttention.none.status)
        XCTAssertEqual(RecordingAttention(noNotes).status, .warn)
        XCTAssertEqual(RecordingAttention(meeting("A", start: now, seconds: 60, status: .processing)).status, .busy)
        XCTAssertEqual(RecordingAttention(meeting("A", start: now, seconds: 60, status: .failed)).status, .err)
        XCTAssertEqual(RecordingAttention(meeting("A", start: now, seconds: 60, status: .recorded)).status, .wait)
        XCTAssertEqual(RecordingsFormat.day(date(16, 15, 30), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(RecordingsFormat.day(date(17, 8, 0), now: now, calendar: calendar), "Today")
    }

    func testTalkTimeComesFromSegmentsOrderedByShare() {
        let talk = MeetingTalkTime(transcript: Transcript(text: "", languageCode: "en", segments: [
            TranscriptSegment(speakerID: "speaker_1", speakerName: "Deniz", startTime: 0, endTime: 30, text: "a"),
            TranscriptSegment(speakerID: "speaker_0", speakerName: nil, startTime: 30, endTime: 90, text: "b"),
            TranscriptSegment(speakerID: "speaker_1", speakerName: "Deniz", startTime: 90, endTime: 100, text: "c")
        ]))
        XCTAssertEqual(talk.speakers.map(\.id), ["speaker_0", "speaker_1"])
        XCTAssertEqual(talk.speakers.map(\.name), ["Speaker 1", "Deniz"])
        XCTAssertEqual(talk.speakers[0].share, 0.6, accuracy: 0.0001)
        XCTAssertEqual(talk.speakers[1].share, 0.4, accuracy: 0.0001)
        XCTAssertNil(talk.speakers[0].storedName)
    }

    func testTranscriptStatesAndNotesLine() {
        XCTAssertEqual(MeetingTranscriptState(.failed), .failed)
        XCTAssertEqual(MeetingTranscriptState(.recorded), .queued)
        XCTAssertEqual(MeetingTranscriptState(.processing), .preparing)
        XCTAssertEqual(MeetingTranscriptState(.completed), .unreadable)
        XCTAssertTrue(MeetingTranscriptState.unreadable.canRetry)
        XCTAssertFalse(MeetingTranscriptState.queued.canRetry)
        let missingKey = MeetingAnalysisError.missingKey.errorDescription
        XCTAssertEqual(MeetingNotesMissingConsole.line(missingKey), "No notes: Connect your OpenAI key in Settings → AI")
        XCTAssertEqual(MeetingNotesMissingConsole.remainder(missingKey), "Your transcript is ready.")
        XCTAssertNil(MeetingNotesMissingConsole.remainder("Couldn’t reach the model."))
        XCTAssertEqual(MeetingNotesMissingConsole.remainder(MeetingAnalysisError.invalidResponse.errorDescription),
                       MeetingAnalysisError.invalidResponse.errorDescription)
        XCTAssertEqual(RecordingsFormat.length(6_000), "1h 40m")
        XCTAssertEqual(RecordingsFormat.length(2_517), "42m")
        XCTAssertEqual(RecordingsFormat.date(date(16, 15, 30), now: now, calendar: calendar), "16 Nov")
        XCTAssertTrue(MeetingNotesMissingConsole.mentionsKey(missingKey))
        XCTAssertFalse(MeetingNotesMissingConsole.mentionsKey(MeetingAnalysisError.rateLimited.errorDescription))
        XCTAssertFalse(MeetingNotesMissingConsole.mentionsKey(nil))
    }

    func testWaveformPeaksAreReadFromTheAudioFile() async throws {
        let url = try sampleAudio()
        XCTAssertNil(MeetingWaveformPeaks().cached(for: url))
        let loader = MeetingWaveformPeaks()
        let loaded = await loader.peaks(for: url)
        let peaks = try XCTUnwrap(loaded)
        XCTAssertEqual(peaks.count, MeetingWaveformPeaks.defaultBars)
        XCTAssertEqual(loader.cached(for: url), peaks)
        XCTAssertTrue(peaks.allSatisfy { (0...1).contains($0) })
        // The fixture is silent in its second quarter and loud in its last.
        let quarter = peaks.count / 4
        XCTAssertLessThan(peaks[(quarter + 3)..<(2 * quarter - 3)].max() ?? 1, 0.02)
        XCTAssertGreaterThan(peaks[(3 * quarter + 3)...].min() ?? 0, 0.5)

        let missing = await loader.peaks(for: URL(fileURLWithPath: "/tmp/crenel-no-such-audio.wav"))
        XCTAssertNil(missing)
    }

    // MARK: Gallery — Recordings

    func testRecordingsStatesRender() async throws {
        let audio = try sampleAudio()
        let loader = RecordingPreviewLoader { meeting in
            RecordingPreview(
                overview: meeting.processingStatus == .completed && meeting.summaryNeedsAttention != true
                    ? "The team agreed to ship the notch redesign behind a flag next week." : nil,
                actionCount: meeting.processingStatus == .completed ? 3 : nil,
                audioURL: audio
            )
        }
        let list = { (recovery: RecordingRecoverySummary?, meetings: [StoredMeeting], hover: UUID?) in
            RecentMeetingsList(meetings: meetings, onOpen: { _ in }, onDelete: { _ in }, onRetry: { _ in },
                               recovery: recovery, now: self.now, forcedHover: hover)
                .environment(\.recordingPreviewLoader, loader)
        }
        let recovered = RecordingRecoverySummary(report: RecordingRecoveryReport(
            recoveredMeetings: [meeting("A", start: now, seconds: 60), meeting("B", start: now, seconds: 60)], preservedCount: 1
        ))
        let history = historyMeetings
        try await exportLoaded(panel(list(nil, history, nil)), "o-history", height: 640)
        try await exportLoaded(panel(list(nil, history, history[0].id)), "o-history-hover", height: 640)
        try await exportLoaded(panel(list(recovered, history, nil)), "o-history-recovery", height: 704)
        try await exportLoaded(panel(list(nil, [], nil)), "o-history-empty", height: 110)
        // `a-delete-meeting` is a native NSAlert raised by AppDelegate over this list.
        try await exportLoaded(panel(list(nil, history, nil)), "a-delete-meeting", height: 640)
    }

    // MARK: Gallery — Detail

    func testDetailStatesRender() async throws {
        let audio = try sampleAudio()
        _ = await MeetingWaveformPeaks.shared.peaks(for: audio)
        XCTAssertNotNil(MeetingWaveformPeaks.shared.cached(for: audio))

        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let base = meeting("Design review", start: start, seconds: 2_892, status: .completed)
        let summary = MeetingSummary(
            overview: "The team agreed to ship the notch redesign behind a flag next week. Onboarding copy needs one more pass, and pricing stays unchanged until the beta closes.",
            decisions: ["The detail panel keeps the width of every notch screen.", "Beta pricing is frozen until January."],
            actionItems: actionItems,
            model: "gpt-5-mini"
        )
        var withoutNotes = StoredTranscription(transcript: transcript, summary: nil)
        withoutNotes.summaryFailure = MeetingAnalysisError.missingKey.errorDescription

        try export(detail(base, StoredTranscription(transcript: transcript, summary: summary), audio: audio), "o-detail", height: 880)
        try export(detail(base, withoutNotes, audio: audio), "o-detail-summaryfailed", height: 580)

        let states: [(String, StoredMeeting.ProcessingStatus)] = [
            ("o-detail-failed", .failed), ("o-detail-queued", .recorded), ("o-detail-preparing", .processing), ("o-detail-unreadable", .completed)
        ]
        for (name, status) in states {
            var meeting = base
            meeting.processingStatus = status
            // No readable audio: the waveform rests as ghost bars.
            try export(detail(meeting, nil, audio: URL(fileURLWithPath: "/tmp/crenel-no-such-audio.wav")), name, height: 270)
        }

        let sheet = ZStack {
            detail(base, StoredTranscription(transcript: transcript, summary: summary), audio: audio)
            Color.black.opacity(0.5)
            MeetingRenameSpeakerSheet(name: .constant("Deniz"), onCancel: {}, onSave: {})
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 150)
        }
        try export(sheet, "o-detail-rename", height: 880)
    }

    // MARK: Scenes

    /// The open notch's content box: 560 pt wide, 14 pt insets, 16 pt under the content.
    private func panel(_ content: some View, band: some View = Color.clear.frame(height: Hud.Notch.bandHeight)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            band.padding(.bottom, 8)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Hud.Notch.openInset)
        .padding(.bottom, Hud.Notch.openBottom)
        .frame(width: Hud.Notch.openWidth)
        .background(Color.black)
    }

    private func detail(_ meeting: StoredMeeting, _ stored: StoredTranscription?, audio: URL) -> some View {
        let content = MeetingDetailContent(meeting: meeting, storedTranscription: stored,
                                           markdown: stored == nil ? nil : "# Design review", audioURL: audio)
        return panel(
            MeetingDetailView(content: content, onCopyText: { _ in }, onExportMarkdown: { _ in }, onRevealAudio: { _ in },
                              onRetry: { _ in }, onDelete: { _ in },
                              importedActionIDs: [actionItems[1].id], startAt: 724),
            band: MeetingDetailToolbar(content: content, onBack: {}, onCopyText: { _ in })
        )
    }

    // MARK: Fixtures

    private func meeting(_ title: String, start: Date, seconds: TimeInterval,
                         status: StoredMeeting.ProcessingStatus = .completed) -> StoredMeeting {
        StoredMeeting(id: UUID(), title: title, startedAt: start, endedAt: start.addingTimeInterval(seconds),
                      sourceMeeting: nil, audioFileName: "fixture.m4a", processingStatus: status)
    }

    private var historyMeetings: [StoredMeeting] {
        var noNotes = meeting("Interview — backend", start: date(16, 11, 0), seconds: 6_000)
        noNotes.summaryNeedsAttention = true
        return [
            meeting("Design review", start: date(17, 10, 0), seconds: 2_892),
            meeting("Partner call", start: date(17, 9, 0), seconds: 1_900, status: .processing),
            meeting("Weekly sync", start: date(16, 15, 30), seconds: 62, status: .failed),
            noNotes,
            meeting("Quick note", start: date(16, 8, 20), seconds: 68, status: .recorded),
            meeting("Onboarding research debrief", start: date(16, 12, 16).addingTimeInterval(-40 * 86_400), seconds: 3_420)
        ]
    }

    private let actionItems = [
        ActionItem(title: "Check the dark and light appearance matrix",
                   dueDate: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20)), sourceTime: 134),
        ActionItem(title: "Write onboarding copy", sourceTime: 1_120),
        ActionItem(title: "Send the beta invite list", sourceTime: 1_862)
    ]

    private var transcript: Transcript {
        Transcript(text: "", languageCode: "en", segments: [
            TranscriptSegment(speakerID: "speaker_0", speakerName: "Ayhan", startTime: 12, endTime: 31,
                              text: "Let’s start with the notch. I want the closed state to be readable in one glance."),
            TranscriptSegment(speakerID: "speaker_1", speakerName: "Deniz", startTime: 31, endTime: 47,
                              text: "Agreed. Two ears, one value each side, nothing else."),
            TranscriptSegment(speakerID: "speaker_0", speakerName: "Ayhan", startTime: 48, endTime: 52,
                              text: "And the open panel should never jump when I hover a row."),
            TranscriptSegment(speakerID: "speaker_2", speakerName: "Ece", startTime: 52, endTime: 60, text: "Works for me.")
        ])
    }

    /// Twelve seconds of noise shaped like speech: bursts with pauses, a silent second
    /// quarter, a loud last quarter.
    private func sampleAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "crenel-waveform-fixture.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rate = 8_000.0, seconds = 12.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        var seed: UInt64 = 7
        func random() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24)
        }
        var envelope: Float = 0
        for index in 0..<Int(frames) {
            let position = Double(index) / Double(frames)
            if index % 800 == 0 { envelope = pow(random(), 1.6) }
            let gain: Float = position >= 0.25 && position < 0.5 ? 0 : (position >= 0.75 ? 0.9 : 0.15 + 0.6 * envelope)
            samples[index] = (random() * 2 - 1) * gain
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ])
        try file.write(from: buffer)
        return url
    }

    // MARK: Export

    /// Hosts the scene in a window (lazy stacks, timelines and appear animations need
    /// one), lets the entrance settle, and writes the PNG when exporting.
    /// Like `export`, but suspends instead of spinning the run loop, so tasks the rows
    /// start on the main actor (preview and waveform loading) get to finish.
    private func exportLoaded(_ view: some View, _ name: String, height: CGFloat) async throws {
        let size = CGSize(width: Hud.Notch.openWidth, height: height)
        let host = NSHostingView(rootView: view.frame(height: height, alignment: .top).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertLessThanOrEqual(host.fittingSize.height, height + 0.5, "\(name) is taller than its frame")
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/recordings/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }

    private func export(_ view: some View, _ name: String, height: CGFloat) throws {
        let size = CGSize(width: Hud.Notch.openWidth, height: height)
        let host = NSHostingView(rootView: view.frame(height: height, alignment: .top).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertLessThanOrEqual(host.fittingSize.height, height + 0.5, "\(name) is taller than its frame")
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/recordings/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }
}
