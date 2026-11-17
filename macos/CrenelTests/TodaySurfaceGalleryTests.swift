import AppKit
import SwiftUI
import XCTest
@testable import Crenel

/// The Today tab of the open notch — Today, Recording, Processing and Result — in every
/// prototype state. PNGs are written to `artifacts/ui-audit/today/<state-id>.png` when
/// `/tmp/CrenelExportUIAudit` exists, to be compared with `/tmp/proto/<state-id>.png`.
@MainActor
final class TodaySurfaceGalleryTests: XCTestCase {
    // MARK: Logic

    func testCalendarStateCoversEveryCalendarCondition() {
        let snapshot = CalendarIntegrationSnapshot(sources: [], scannedEventCount: 0, matchedMeetingCount: 0, refreshedAt: Self.now)
        XCTAssertEqual(TodayCalendarState(enabled: false, access: .authorized, snapshot: snapshot), .off)
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .notDetermined, snapshot: nil), .connect)
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .requesting, snapshot: nil), .waiting)
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .denied, snapshot: nil), .accessOff)
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .restricted, snapshot: nil), .accessOff)
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .failed("x"), snapshot: snapshot), .failed(lastRefresh: Self.now))
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .authorized, snapshot: nil), .reading)
        XCTAssertEqual(TodayCalendarState(enabled: true, access: .authorized, snapshot: snapshot), .noCalendars)
    }

    func testAgendaPicksTheNextTimedEventAndSplitsTheRest() {
        let agenda = TodayAgenda(events: Self.events(focusAt: 14.5), now: Self.now)
        XCTAssertEqual(agenda.focus?.title, "Design review")
        XCTAssertEqual(agenda.today.map(\.title), ["Lunch with Deniz", "Partner call", "Gym"])
        XCTAssertEqual(agenda.later.map(\.title), ["Weekly sync", "Company offsite"])
        XCTAssertEqual(agenda.rulerEvents.count, 4)
    }

    func testAgendaHasNoHeroWhenTheNextEventIsDaysAway() {
        let agenda = TodayAgenda(events: [Self.event("Weekly sync", day: 3, 10, 10.5, url: "https://zoom.us/j/1")], now: Self.now)
        XCTAssertNil(agenda.focus)
        XCTAssertTrue(agenda.today.isEmpty)
        XCTAssertEqual(agenda.later.count, 1)
        XCTAssertFalse(agenda.hasRows)
    }

    func testConsoleOpensOnlyWhenTheCallIsNearOrOn() {
        let far = Self.event("Design review", 11.25, 12, url: "https://meet.google.com/a")
        XCTAssertNil(TodayConsoleModel(focus: far, now: Self.now, bridge: .none))

        let near = Self.event("Design review", 10.83, 11.5, url: "https://meet.google.com/a")
        let nearModel = TodayConsoleModel(focus: near, now: Self.now, bridge: .none)
        XCTAssertEqual(nearModel?.note, .willAsk)
        XCTAssertEqual(nearModel?.canJoin, true)
        XCTAssertEqual(nearModel?.canRecord, true)

        let live = Self.event("Design review", 10, 11, url: "https://meet.google.com/a")
        XCTAssertEqual(TodayConsoleModel(focus: live, now: Self.now, bridge: .none)?.note, .notRecorded)

        let unavailable = TodayConsoleModel(focus: near, now: Self.now, bridge: .unavailable)
        XCTAssertEqual(unavailable?.note, .meetUnavailable)
        XCTAssertEqual(unavailable?.canRecord, false)

        // A Meet call without a calendar event still gets its bridge state.
        let adHoc = TodayConsoleModel(focus: nil, now: Self.now, bridge: .waiting)
        XCTAssertEqual(adHoc?.note, .meetWaiting)
        XCTAssertEqual(adHoc?.canJoin, false)

        // A personal event without a link has nothing to join or record.
        let personal = Self.event("Gym", 10.75, 11.5, kind: .event)
        XCTAssertNil(TodayConsoleModel(focus: personal, now: Self.now, bridge: .none))
    }

    func testRulerWidensOnlyWhenSomethingFallsOutsideTheDay() {
        let agenda = TodayAgenda(events: Self.events(focusAt: 14.5), now: Self.now)
        let scale = TodayRulerScale(agenda: agenda, now: Self.now)
        XCTAssertEqual(scale.span, 8...20)
        XCTAssertEqual(scale.now, 10.7, accuracy: 0.01)
        XCTAssertEqual(scale.events.map(\.kind), [.focus, .normal, .invite, .dim])

        let late = TodayAgenda(events: [Self.event("Late call", 21, 22.5, url: "https://zoom.us/j/1")], now: Self.now)
        XCTAssertEqual(TodayRulerScale(agenda: late, now: Self.now).span, 8...23)
    }

    func testTextsUseOneTimeAndShortDistances() {
        XCTAssertEqual(TodayText.distance(3 * 3_600 + 48 * 60), "in 3 h 48")
        XCTAssertEqual(TodayText.distance(2 * 3_600), "in 2 h")
        XCTAssertEqual(TodayText.distance(3 * 3_600 + 5 * 60), "in 3 h 05")
        XCTAssertEqual(TodayText.minutes(7.2 * 60), 8)
        XCTAssertEqual(TodayText.minutes(0), 1)
    }

    func testRecordingWarningsCarryTheirShape() {
        var gate = MeetingMicrophoneGate(recordingStartedAt: Self.now)
        gate.adapterBecameUnavailable(at: Self.now)
        var capture = RecordingCaptureStatus()
        capture.microphone.connectionState = .disconnected(deviceName: "AirPods Pro")
        capture.systemAudio.connectionState = .pipelineStalled
        let warnings = RecordingSurface.warnings(gate: gate, clientName: "Zoom", capture: capture, safetyMessage: nil)
        XCTAssertEqual(warnings.map(\.status), [.warn, .err, .err])
        XCTAssertEqual(warnings.first?.text, "Couldn’t read Zoom’s mute state, so your mic is kept off")
        XCTAssertTrue(RecordingSurface.warnings(gate: MeetingMicrophoneGate(recordingStartedAt: Self.now), clientName: "Zoom",
                                                capture: RecordingCaptureStatus(), safetyMessage: nil).isEmpty)
    }

    func testFlowMemoryRemembersWhatWasCancelled() {
        let state = AppState(initialFlow: .transcribing)
        let memory = state.todayFlowMemory
        XCTAssertTrue(memory === state.todayFlowMemory)
        state.cancelCurrentFlow()
        XCTAssertEqual(state.meetingFlow, .cancelled)
        XCTAssertEqual(memory.phaseBeforeCancel, .transcribing)
    }

    func testResultStatsCountSpeakersAndActionItems() {
        let transcript = Transcript(text: "", languageCode: nil, segments: [
            TranscriptSegment(speakerID: "a", startTime: 0, endTime: 1, text: "x"),
            TranscriptSegment(speakerID: "b", startTime: 1, endTime: 2, text: "y"),
            TranscriptSegment(speakerID: "a", startTime: 2, endTime: 3, text: "z")
        ])
        let summary = MeetingSummary(overview: "", decisions: [], actionItems: [ActionItem(title: "1"), ActionItem(title: "2")])
        let stats = MeetingResultStats(transcription: StoredTranscription(transcript: transcript, summary: summary))
        XCTAssertEqual(stats, MeetingResultStats(speakers: 2, actionItems: 2, hasNotes: true))
        XCTAssertFalse(MeetingResultStats(transcription: StoredTranscription(transcript: transcript)).hasNotes)
    }

    // MARK: Gallery — Today

    func testTodayGallery() throws {
        try export(today(Self.events(focusAt: 14.5)), "o-today")
        try export(today(Self.events(focusAt: 11.25)), "o-today-hour")
        try export(today(Self.events(focusAt: 10.83, focusEnd: 11.5)), "o-today-urgent")
        try export(today(Self.events(focusAt: 10, focusEnd: 11)), "o-today-live")
        try export(today(Self.events(focusAt: 10.83, focusEnd: 11.5), bridge: .waiting), "o-today-meet-waiting")
        try export(today(Self.events(focusAt: 10.83, focusEnd: 11.5), bridge: .unavailable), "o-today-meet-unavailable")
        let events = Self.events(focusAt: 14.5)
        try export(today(events, hover: TodaySurface.heroHoverID), "o-today-hover-hero")
        try export(today(events, hover: AnyHashable(events[2].id)), "o-today-hover-row")
    }

    func testTodayEmptyGallery() throws {
        try export(today([], calendar: .connect), "o-today-empty-connect")
        try export(today([], calendar: .accessOff), "o-today-empty-allow")
        try export(today([], calendar: .waiting), "o-today-empty-waiting")
        try export(today([], calendar: .failed(lastRefresh: Self.at(10.2))), "o-today-empty-failed")
        try export(today([], calendar: .off), "o-today-empty-off")
        try export(today([], calendar: .reading), "o-today-empty-reading")
        try export(today([], calendar: .noCalendars), "o-today-empty-nocal")
        try export(today([
            Self.event("Standup", 9, 10, kind: .event),
            Self.event("Weekly sync", day: 2, 10, 10.5, url: "https://zoom.us/j/1"),
            Self.event("Company offsite", day: 3, 0, 23.9, kind: .event, allDay: true, calendar: "Work")
        ], calendar: .ready), "o-today-empty-nothing")
    }

    // MARK: Gallery — Recording

    func testRecordingGallery() throws {
        let levels = Self.levels()
        try export(RecordingSurface(
            startedAt: Self.now.addingTimeInterval(-768), title: "Design review", plannedLength: 3_600, microphone: .open,
            microphoneLevel: 0.44, callLevel: 0.4, levels: levels, muteFollows: "Zoom", now: Self.now
        ), "o-recording")
        try export(RecordingSurface(
            startedAt: Self.now.addingTimeInterval(-768), title: "Design review", plannedLength: 3_600, microphone: .closed,
            microphoneLevel: 0.44, callLevel: 0.4, levels: levels, muteFollows: "Zoom", now: Self.now
        ), "o-recording-micoff")
        try export(RecordingSurface(
            startedAt: Self.now.addingTimeInterval(-768), title: "Design review", plannedLength: 3_600, microphone: .unknown,
            callLevel: 0.14, callFailed: true, levels: levels, muteFollows: "Zoom",
            warnings: [
                .init(status: .warn, text: "Couldn’t read Zoom’s mute state, so your mic is kept off"),
                .init(status: .err, text: "AirPods Pro disconnected. Reconnect it or stop the recording."),
                .init(status: .err, text: "The call’s audio stream dropped. Stopping to keep what’s recorded.")
            ],
            now: Self.now
        ), "o-recording-warnings")
        // No calendar event: no title, no ramp.
        try export(RecordingSurface(
            startedAt: Self.now.addingTimeInterval(-42), microphone: nil, microphoneLevel: 0.3, callLevel: 0.2,
            levels: Array(levels.prefix(42)), now: Self.now
        ), "o-recording-unplanned")
    }

    // MARK: Gallery — Processing and result

    func testProcessingGallery() throws {
        try export(ProcessingSurface(station: .saving, title: "Design review", recorded: 2_892, scannerPhase: 0.4), "o-proc-saving")
        try export(ProcessingSurface(station: .uploading, title: "Design review", recorded: 2_892, uploadProgress: 0.42, onStop: {}),
                   "o-proc-uploading")
        try export(ProcessingSurface(station: .transcribing, title: "Design review", recorded: 2_892, onStop: {}, scannerPhase: 0.4),
                   "o-proc-transcribing")
        try export(ProcessingSurface(station: .summarizing, title: "Design review", recorded: 2_892, onStop: {}, scannerPhase: 0.4),
                   "o-proc-summarizing")
        try export(PreparingSurface(), "o-preparing")
    }

    func testResultGallery() throws {
        try export(ReadySurface(title: "Design review", recorded: 2_892, stats: MeetingResultStats(speakers: 3, actionItems: 3),
                                onOpen: {}), "o-ready")
        try export(FlowOutcomeSurface(
            status: .err, tint: Hud.Ink.live, title: "Couldn’t reach transcription",
            message: "ElevenLabs didn’t answer. Your 48 minutes of audio are saved.",
            secondary: .init(title: "Recordings", glyph: .tape, run: {}), primary: .init(title: "Try again", run: {})
        ), "o-failed")
        try export(FlowOutcomeSurface(
            status: .off, tint: Hud.Ink.live, title: "System audio permission is off",
            message: "Allow Crenel under Screen & System Audio Recording, then relaunch.",
            secondary: .init(title: "System Settings", glyph: .link, run: {}), primary: .init(title: "Relaunch", run: {})
        ), "o-failed-permission")
        try export(FlowOutcomeSurface(
            status: .stop, title: "Processing stopped", message: "The audio is kept. You can process it later from Recordings.",
            secondary: .init(title: "Recordings", glyph: .tape, run: {}), primary: .init(title: "Done", run: {})
        ), "o-stopped")
    }

    /// The whole tab from the app's state, so the wiring is exercised too.
    func testStatusViewRendersEveryFlow() throws {
        let failure = AppFailure(category: .network, title: "Couldn’t reach transcription",
                                 message: "The service didn’t answer. Your audio is saved.", recoveryAction: .retry)
        let flows: [(String, MeetingFlowState)] = [
            ("flow-idle", .idle), ("flow-preparing", .preparingRecording),
            ("flow-recording", .recording(startedAt: Date().addingTimeInterval(-83))), ("flow-saving", .finalizingAudio),
            ("flow-uploading", .uploading(progress: 0.42)), ("flow-transcribing", .transcribing),
            ("flow-summarizing", .summarizing), ("flow-failed", .failed(failure)), ("flow-cancelled", .cancelled)
        ]
        for (name, flow) in flows {
            let state = AppState(initialFlow: flow)
            if case .recording(let startedAt) = flow {
                state.updateMeetingMicrophoneGate(MeetingMicrophoneGate(recordingStartedAt: startedAt))
            }
            let view = MeetingStatusView(
                onRequestCalendarAccess: {}, onOpenMeetingURL: { _ in }, onStartRecording: {}, onStopRecording: {},
                onToggleMeetingMicrophone: {}, onDismissMeetingPrompt: {}, onContinueRecording: {}, onConfirmMeetingEnded: {},
                onCancelFlow: {}, onRecoverFromFailure: { _ in }, onOpenStoredMeeting: { _ in }, onRelaunchApplication: {}
            )
            .environmentObject(state)
            try export(view, name)
        }
    }

    // MARK: Sample data

    /// Tuesday 17 November 2026, 10:42.
    private static let now = at(10.7)

    private static func at(_ hours: Double, day: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 11, day: 17 + day)
        components.hour = Int(hours)
        components.minute = Int(((hours - Double(Int(hours))) * 60).rounded())
        return Calendar.current.date(from: components)!
    }

    private static func event(_ title: String, day: Int = 0, _ start: Double, _ end: Double, url: String? = nil,
                              kind: CalendarItemKind? = nil, allDay: Bool = false, response: CalendarResponseStatus = .none,
                              location: String? = nil, calendar: String? = nil) -> Meeting {
        Meeting(title: title, startDate: at(start, day: day), endDate: at(end, day: day), meetingURL: url.flatMap(URL.init(string:)),
                kind: kind, isAllDay: allDay, responseStatus: response, location: location, calendarTitle: calendar)
    }

    private static func events(focusAt start: Double, focusEnd: Double? = nil) -> [Meeting] {
        [
            event("Design review", start, focusEnd ?? start + 0.75, url: "https://meet.google.com/abc-defg-hij"),
            event("Lunch with Deniz", 16, 17, kind: .meeting, location: "Karaköy Lokantası"),
            event("Partner call", 17.5, 18, url: "https://zoom.us/j/123", response: .pending),
            event("Gym", 19, 20, kind: .event, response: .tentative, calendar: "Personal"),
            event("Weekly sync", day: 1, 10, 10.5, url: "https://zoom.us/j/456"),
            event("Company offsite", day: 2, 0, 23.9, kind: .event, allDay: true, calendar: "Work")
        ]
    }

    /// A speech-like level history: a little over two minutes, deterministic.
    private static func levels() -> [Double] {
        var seed: UInt64 = 0x2545F4914F6CDD1D
        return (0..<130).map { _ in
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return 0.08 + Double(seed % 1_000) / 1_000 * 0.6
        }
    }

    private func today(_ events: [Meeting], calendar: TodayCalendarState = .ready, bridge: TodayMeetBridge = .none,
                       hover: AnyHashable? = nil) -> some View {
        TodaySurface(
            events: events, emptyMessage: "", canRequestCalendarAccess: false, onRequestCalendarAccess: {},
            onOpenMeetingURL: { _ in }, onStartRecording: {}, calendar: calendar, meetBridge: bridge,
            fixes: TodayCalendarFixes(), now: Self.now, previewHover: hover
        )
    }

    // MARK: Export

    /// Hosts the surface the way the open notch does (560 pt wide, 14 pt inset, black),
    /// lets the sections settle, checks it drew, and writes the PNG when exporting.
    private func export(_ view: some View, _ name: String) throws {
        let content = view
            .frame(width: Hud.Notch.openWidth - 2 * Hud.Notch.openInset)
            .padding(.horizontal, Hud.Notch.openInset)
            .padding(.top, 8)
            .padding(.bottom, Hud.Notch.openBottom)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        XCTAssertEqual(size.width, Hud.Notch.openWidth, accuracy: 0.5, "\(name) does not fit the open notch")
        XCTAssertGreaterThan(size.height, 30, "\(name) is empty")
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        let exporting = FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit")
        for _ in 0..<(exporting ? 14 : 2) {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard exporting else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/today/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }
}
