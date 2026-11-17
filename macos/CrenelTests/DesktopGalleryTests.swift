import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import Crenel

/// The desktop window: derived figures, and an offscreen render of every `d-*` prototype
/// state at 1240×760. PNGs go to `artifacts/ui-audit/desktop/` when
/// `/tmp/CrenelExportUIAudit` exists.
@MainActor
final class DesktopGalleryTests: XCTestCase {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 42))! }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: day, to: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!)!
    }

    // MARK: Derived figures

    func testWeekAddsRecordedTimePerDayAndMarksToday() {
        let week = DesktopStats.week(meetings: sampleMeetings().map(\.meeting), now: now, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.filter(\.isToday).count, 1)
        let today = week.first(where: \.isToday)
        XCTAssertEqual(today?.seconds ?? 0, 48 * 60 + 12 + 31 * 60 + 40, accuracy: 0.5)
        XCTAssertEqual(DesktopStats.stackCells(0, week: week), 0)
        XCTAssertGreaterThanOrEqual(DesktopStats.stackCells(60, week: week), 1)
        XCTAssertEqual(DesktopFormat.hoursMinutes(4 * 3_600 + 12 * 60), "4:12")
        XCTAssertEqual(DesktopFormat.tape(9 * 3_600 + 40 * 60), "9 h 40")
        XCTAssertEqual(DesktopFormat.length(48 * 60 + 12), "48:12")
    }

    func testDictationCountsOnlyTodaysWords() {
        let history = [
            DictationHistoryEntry(id: UUID(), createdAt: at(9), transcript: "", finalText: "one two three", delivery: .insertedViaPaste, appName: "Notes"),
            DictationHistoryEntry(id: UUID(), createdAt: at(9, day: -1), transcript: "", finalText: "old words here now", delivery: nil, appName: nil)
        ]
        let today = DesktopStats.dictationToday(history, now: now, calendar: calendar)
        XCTAssertEqual(today.words, 3)
        XCTAssertEqual(today.count, 1)
    }

    private func dictation(_ words: Int, day: Int, hour: Int = 9) -> DictationHistoryEntry {
        DictationHistoryEntry(id: UUID(), createdAt: at(hour, day: day), transcript: "",
                              finalText: Array(repeating: "söz", count: words).joined(separator: " "),
                              delivery: .insertedViaPaste, appName: nil)
    }

    func testUsualDictationIsTheMedianOfRecentDaysWithoutToday() {
        let history = [
            dictation(999, day: 0),                          // today: left out
            dictation(100, day: -1), dictation(50, day: -1), // one day, 150 words
            dictation(40, day: -2),
            dictation(300, day: -5),
            dictation(10, day: -14),                         // 14 days back: still in
            dictation(5_000, day: -15)                       // too old
        ]
        // Days: 10, 40, 150, 300 → median of an even count is the mean of the middle two.
        XCTAssertEqual(DesktopStats.usualDictationWords(history, now: now, calendar: calendar), 95)
        XCTAssertEqual(DesktopStats.usualDictationWords(Array(history.dropLast(2)), now: now, calendar: calendar), 150)
    }

    func testUsualDictationNeedsThreeDays() {
        let history = [dictation(80, day: -1), dictation(120, day: -3), dictation(500, day: 0), dictation(70, day: -20)]
        XCTAssertNil(DesktopStats.usualDictationWords(history, now: now, calendar: calendar))
        XCTAssertNil(DesktopStats.usualDictationWords([], now: now, calendar: calendar))
    }

    func testDictationScaleFillsTodayAgainstTheUsualDay() {
        let quiet = DesktopStats.dictationScale(todayWords: 50, usual: 100)
        XCTAssertEqual(quiet.value, 50.0 / 150, accuracy: 0.0001)
        XCTAssertEqual(quiet.mark ?? -1, 100.0 / 150, accuracy: 0.0001)

        let busy = DesktopStats.dictationScale(todayWords: 400, usual: 100)
        XCTAssertEqual(busy.value, 1, accuracy: 0.0001)
        XCTAssertEqual(busy.mark ?? -1, 0.25, accuracy: 0.0001)

        let unknown = DesktopStats.dictationScale(todayWords: 160, usual: nil)
        XCTAssertNil(unknown.mark)
        XCTAssertEqual(unknown.value, 160.0 / 1_560, accuracy: 0.0001)
    }

    func testTalkTimeSharesAndLaneFollowTheTranscript() {
        let transcript = Transcript(text: "", languageCode: "en", segments: [
            TranscriptSegment(speakerID: "a", speakerName: "You", startTime: 0, endTime: 30, text: "x"),
            TranscriptSegment(speakerID: "b", speakerName: "Deniz", startTime: 30, endTime: 40, text: "y"),
            TranscriptSegment(speakerID: "a", speakerName: "You", startTime: 40, endTime: 50, text: "z")
        ])
        let shares = DesktopStats.talkTime(transcript)
        XCTAssertEqual(shares.map(\.name), ["You", "Deniz"])
        XCTAssertEqual(shares[0].share, 0.8, accuracy: 0.001)
        let lane = DesktopStats.lane(transcript, duration: 50)
        XCTAssertEqual(lane.map(\.speaker), [0, 1, 0])
        XCTAssertEqual(lane[0].share, 0.6, accuracy: 0.001)
    }

    func testSystemsFollowRealPermissionState() {
        let state = AppState()
        var systems = DesktopSystem.all(state)
        XCTAssertEqual(systems.map(\.kind), DesktopSystem.Kind.allCases)
        XCTAssertFalse(systems.contains(where: \.isOn))
        state.updateCalendarAccessState(.denied)
        state.updateAudioCapturePermissions(.init(microphone: .authorized, systemAudio: .denied))
        state.updateDictationAvailability(.needsInputMonitoring)
        systems = DesktopSystem.all(state)
        XCTAssertTrue(systems[0].paren)
        XCTAssertEqual(systems[0].category, .calendar)
        XCTAssertTrue(systems[2].isOn)
        XCTAssertEqual(systems[3].state, .red)
        XCTAssertTrue(systems[5].needsUser)
        allOn(state)
        XCTAssertEqual(DesktopSystem.all(state).filter(\.isOn).count, 6)
    }

    func testFilterAndTranscriptSearch() {
        let meetings = sampleMeetings().map(\.meeting)
        XCTAssertEqual(meetings.filter(DesktopMeetingFilter.needsUser).map(\.title), ["Weekly sync", "Interview — backend"])
        let found = DesktopMeetingSearch.filter(meetings, query: "pricing", transcripts: [meetings[0].id: "we keep pricing frozen"])
        XCTAssertEqual(found.map(\.id), [meetings[0].id])
    }

    func testWaveformPeaksAreReadFromTheAudioFile() async throws {
        let url = try makeAudio(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let peaks = try await DesktopWaveform.read(url, buckets: 40)
        XCTAssertEqual(peaks.count, 40)
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 0.001)
        // The fixture is silent in its second half.
        XCTAssertGreaterThan(peaks[5], 0.3)
        XCTAssertLessThan(peaks[35], 0.05)
        XCTAssertEqual(DesktopWaveform.resample(peaks, to: 10).count, 10)
        let missing = await DesktopWaveform.peaks(for: URL(fileURLWithPath: "/tmp/crenel-missing-\(UUID()).m4a"))
        XCTAssertNil(missing)
    }

    // MARK: Gallery

    func testGalleryRendersEveryDesktopState() async throws {
        let audio = try makeAudio(seconds: 6, speechLike: true)
        defer { try? FileManager.default.removeItem(at: audio) }
        let samples = sampleMeetings()

        try await render("d-today", section: .today, samples: samples, audio: audio)
        try await render("d-meetings", section: .meetings, selected: 0, samples: samples, audio: audio)
        try await render("d-meetings-none", section: .meetings, samples: samples, audio: audio)
        try await render("d-meetings-recording", section: .meetings, selected: 0, samples: samples, audio: audio, recording: true)
        try await render("d-meetings-empty", section: .meetings, samples: [], audio: audio)
        try await render("d-meetings-loading", section: .meetings, selected: 1, samples: samples, audio: audio, load: .never)
        try await render("d-meetings-error", section: .meetings, selected: 2, samples: samples, audio: audio, load: .fails)
        try await render("d-tasks", section: .tasks, samples: samples, audio: audio)
        try await render("d-dictation", section: .dictation, samples: samples, audio: audio)
    }

    private enum Load { case works, never, fails }

    private func render(_ name: String, section: DesktopSection, selected: Int? = nil, samples: [Sample], audio: URL,
                        recording: Bool = false, load: Load = .works) async throws {
        let state = AppState(initialFlow: recording ? .recording(startedAt: now.addingTimeInterval(-754)) : .idle)
        allOn(state)
        state.updateUpcomingMeetings([
            Meeting(title: "Standup", startDate: at(9), endDate: at(9, 30), kind: .event),
            Meeting(title: "Design review", startDate: at(11, 15), endDate: at(12), meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            Meeting(title: "Lunch with Deniz", startDate: at(13), endDate: at(14), kind: .meeting),
            Meeting(title: "Partner call", startDate: at(16, 30), endDate: at(17, 30), meetingURL: URL(string: "https://zoom.us/j/1"), responseStatus: .pending),
            Meeting(title: "Gym", startDate: at(19), endDate: at(20), kind: .event),
            Meeting(title: "Weekly sync", startDate: at(10, day: 1), endDate: at(11, day: 1), meetingURL: URL(string: "https://zoom.us/j/2"))
        ])
        state.replaceStoredMeetings(samples.map(\.meeting))
        if samples.count > 1 {
            state.replaceProcessingJobs([ProcessingJob(meetingID: samples[1].meeting.id, state: .running)])
        }
        state.replaceTasks(sampleTasks())
        state.updateDictationHistory(sampleDictations())

        var preferences = CrenelPreferences.default
        preferences.dictationVocabulary = ["Crenel", "SwiftUI", "Deniz", "ElevenLabs"]
        let navigation = DesktopNavigation()
        navigation.section = section
        navigation.selectedMeeting = selected.map { samples[$0].meeting.id }

        var actions = DesktopActions()
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.meeting.id, $0) })
        actions.loadMeeting = { meeting in
            switch load {
            case .never where meeting.id == navigation.selectedMeeting:
                try await Task.sleep(for: .seconds(600))
                throw CancellationError()
            case .fails where meeting.id == navigation.selectedMeeting:
                throw CocoaError(.fileReadCorruptFile)
            default:
                return MeetingDetailContent(meeting: meeting, storedTranscription: byID[meeting.id]?.transcription, markdown: "# Notes", audioURL: audio)
            }
        }
        let view = DesktopWorkspaceView(actions: actions, navigation: navigation, preferences: .preset(preferences))
            .environmentObject(state)
            .environment(\.desktopFixedNow, now)

        let size = Hud.Window.size
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertLessThanOrEqual(host.fittingSize.width, size.width + 1, "\(name) must not overflow")
        if FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let path = root.appending(path: "artifacts/ui-audit/desktop/\(name).png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
        }
    }

    // MARK: Samples

    private struct Sample {
        let meeting: StoredMeeting
        var transcription: StoredTranscription?
    }

    private func allOn(_ state: AppState) {
        state.updateCalendarAccessState(.authorized)
        state.updateTaskStorageStatus(.reminders(listTitle: "Crenel"))
        state.updateAudioCapturePermissions(.init(microphone: .authorized, systemAudio: .authorized))
        state.updateAccessibilityPermission(granted: true)
        state.updateDictationAvailability(.ready)
    }

    private func sampleMeetings() -> [Sample] {
        func stored(_ title: String, _ start: Date, _ length: TimeInterval, _ status: StoredMeeting.ProcessingStatus,
                    url: String? = nil, attention: Bool = false) -> StoredMeeting {
            var meeting = StoredMeeting(id: title == "Design review" ? designReviewID : UUID(), title: title, startedAt: start, endedAt: start.addingTimeInterval(length),
                sourceMeeting: url.map { Meeting(title: title, startDate: start, endDate: start.addingTimeInterval(length), meetingURL: URL(string: $0)) },
                audioFileName: "audio.m4a", microphoneFileName: "mic.m4a", systemAudioFileName: "system.m4a", processingStatus: status)
            if attention { meeting.summaryNeedsAttention = true }
            return meeting
        }
        var segments: [TranscriptSegment] = []
        let lines: [(String, String, String)] = [
            ("speaker_0", "You", "Let’s start with the notch. I want the closed state to be readable in one glance."),
            ("speaker_1", "Deniz", "Agreed. Two ears, one value each side, nothing else."),
            ("speaker_0", "You", "And the open panel should never jump when I hover a row."),
            ("speaker_2", "Ece", "Then pricing: I’d keep it frozen until the beta closes in January."),
            ("speaker_1", "Deniz", "That works. I’ll update the pricing page copy after the review."),
            ("speaker_0", "You", "Good. I’ll check the appearance matrix and send the beta invite list.")
        ]
        let starts: [TimeInterval] = [12, 31, 48, 70, 1_400, 2_300], ends: [TimeInterval] = [31, 48, 70, 550, 2_300, 2_890]
        for (index, line) in lines.enumerated() {
            segments.append(TranscriptSegment(speakerID: line.0, speakerName: line.1, startTime: starts[index], endTime: ends[index], text: line.2))
        }
        let summary = MeetingSummary(
            overview: "The team agreed to ship the notch redesign behind a flag next week. Onboarding copy needs one more pass, and pricing stays unchanged until the beta closes.",
            decisions: ["The detail panel keeps the width of every notch screen.", "Beta pricing is frozen until January."],
            actionItems: [
                ActionItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Check the appearance matrix", dueDate: at(12, day: 3), sourceTime: 134),
                ActionItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Write onboarding copy", sourceTime: 1_120),
                ActionItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, title: "Send the beta invite list", sourceTime: 1_862)
            ], model: "Claude Haiku")
        let transcript = Transcript(text: "", languageCode: "en", segments: segments)
        return [
            Sample(meeting: stored("Design review", at(10), 48 * 60 + 12, .completed, url: "https://meet.google.com/abc"),
                   transcription: StoredTranscription(transcript: transcript, summary: summary)),
            Sample(meeting: stored("Partner call", at(9), 31 * 60 + 40, .processing, url: "https://zoom.us/j/1")),
            Sample(meeting: stored("Weekly sync", at(15, 30, day: -1), 62, .failed, url: "https://zoom.us/j/2")),
            Sample(meeting: stored("Interview — backend", at(11, day: -1), 44 * 60 + 3, .completed, attention: true),
                   transcription: StoredTranscription(transcript: transcript, summary: nil)),
            Sample(meeting: stored("Quick note", at(18, 20, day: -1 - 0), 130, .recorded))
        ]
    }

    private func sampleTasks() -> [TaskItem] {
        let designReview = sampleMeetingActionSource
        return [
            TaskItem(title: "Write release notes", status: .inProgress, startedAt: now.addingTimeInterval(-25 * 60), dueDate: at(17), dueHasTime: true),
            TaskItem(title: "Ship notarized build", notes: "waiting on QA", status: .blocked),
            TaskItem(title: "Reply to Deniz about pricing", dueDate: at(0, day: -1), priority: .high),
            TaskItem(title: "Call the bank", dueDate: at(15), dueHasTime: true),
            TaskItem(title: "Water the plants", dueDate: at(0, day: 1)),
            TaskItem(title: "Plan Q1 roadmap", dueDate: at(0, day: 6), priority: .medium),
            TaskItem(title: "Read “Shape Up”"),
            TaskItem(title: "Book flights", completedAt: at(9, 30)),
            TaskItem(title: "Write onboarding copy", dueDate: at(0, day: 2), sourceMeetingID: designReviewID, sourceActionID: designReview)
        ]
    }

    private let designReviewID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private var sampleMeetingActionSource: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000002")! }

    private func sampleDictations() -> [DictationHistoryEntry] {
        [
            DictationHistoryEntry(id: UUID(), createdAt: at(10, 32), transcript: "", finalText: "Let’s move the design review to Thursday afternoon, and send Deniz the new onboarding copy before then.", delivery: .insertedViaAccessibility, appName: "Slack"),
            DictationHistoryEntry(id: UUID(), createdAt: at(10, 5), transcript: "", finalText: "Ship the notarized build after QA signs off.", delivery: .insertedViaPaste, appName: "Notes"),
            DictationHistoryEntry(id: UUID(), createdAt: at(9, 48), transcript: "", finalText: "Thanks Mira — Thursday works. I’ll bring the pricing numbers.", delivery: .insertedViaPaste, appName: "Mail"),
            DictationHistoryEntry(id: UUID(), createdAt: at(9, 20), transcript: "", finalText: "Check the light appearance on the settings window.", delivery: nil, appName: nil)
        ]
    }

    /// A short mono WAV: a tone (optionally shaped like speech bursts), silent in its second half.
    private func makeAudio(seconds: Double, speechLike: Bool = false) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "crenel-desktop-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frames) {
            let t = Double(frame) / 16_000, progress = Double(frame) / Double(frames)
            let envelope = speechLike
                ? pow(abs(sin(t * 5.3) * sin(t * 1.7 + 0.4)), 1.5) * (0.35 + 0.65 * abs(sin(t * 0.9)))
                : (progress < 0.5 ? 0.8 : 0)
            data[frame] = Float(sin(t * 2 * .pi * 220) * envelope)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
