import AppKit
import SwiftUI
import XCTest
@testable import Crenel

/// The notch shell: its three sizes, the ears, the strip and the camera band. Logic
/// checks plus an offscreen render of every closed state (`c-*` in the prototype) and of
/// the band. PNGs go to `artifacts/ui-audit/notch-shell/` when
/// `/tmp/CrenelExportUIAudit` exists.
@MainActor
final class NotchShellGalleryTests: XCTestCase {
    private let metrics = CrenelNotchMetrics(hardware: CGSize(width: 186, height: 32), hasPhysicalNotch: true)

    /// 10:42 today, so "later today" and "tomorrow" stay on the right side of midnight.
    private var now: Date {
        Calendar.current.date(bySettingHour: 10, minute: 42, second: 0, of: Date()) ?? Date()
    }

    // MARK: Sizes and motion

    func testThreeSizesMatchTheSpec() {
        XCTAssertEqual(CrenelNotchSize.compact.topRadius, 6)
        XCTAssertEqual(CrenelNotchSize.compact.bottomRadius, 10)
        XCTAssertEqual(CrenelNotchSize.strip.topRadius, 9)
        XCTAssertEqual(CrenelNotchSize.strip.bottomRadius, 18)
        XCTAssertEqual(CrenelNotchSize.open.topRadius, 14)
        XCTAssertEqual(CrenelNotchSize.open.bottomRadius, 24)
        XCTAssertEqual(Hud.Notch.stripWidth, 440)
        XCTAssertEqual(Hud.Notch.openWidth, 560)
        XCTAssertEqual(NotchPanelLayout.preferredWidth, 560)
        XCTAssertEqual(Hud.Notch.lean, CGSize(width: 14, height: 4))
    }

    func testStripNeverOpensOnHoverButTheCompactNotchDoes() {
        XCTAssertTrue(CrenelNotchController.hoverIntent(isHovering: true, presentation: .compact, isStrip: false))
        XCTAssertFalse(CrenelNotchController.hoverIntent(isHovering: true, presentation: .compact, isStrip: true))
        // The open panel stays open under the pointer whatever the closed content was.
        XCTAssertTrue(CrenelNotchController.hoverIntent(isHovering: true, presentation: .expanded, isStrip: true))
        XCTAssertFalse(CrenelNotchController.hoverIntent(isHovering: false, presentation: .compact, isStrip: false))
    }

    func testIgnitionOnlyRightAfterThePanelOpens() {
        let opened = Date()
        XCTAssertTrue(NotchPanelIgnition.ignites(openedAt: opened, now: opened.addingTimeInterval(0.1), reduceMotion: false))
        XCTAssertFalse(NotchPanelIgnition.ignites(openedAt: opened, now: opened.addingTimeInterval(2), reduceMotion: false))
        XCTAssertFalse(NotchPanelIgnition.ignites(openedAt: opened, now: opened.addingTimeInterval(0.1), reduceMotion: true))
        XCTAssertFalse(NotchPanelIgnition.ignites(openedAt: nil, reduceMotion: false))
    }

    func testStripEarsShareTheStripWidth() {
        let view = NotchFlankLayout(gap: 186, totalWidth: 440) {
            Color.red.frame(width: 60, height: 20)
            Color.blue.frame(width: 30, height: 20)
        }
        let host = NSHostingView(rootView: view)
        XCTAssertEqual(host.fittingSize.width, 440, accuracy: 0.5)
    }

    // MARK: Resolving

    func testMeetingEarsFollowTheFiveMeetingStates() {
        let now = self.now
        func ear(startsIn: TimeInterval) -> NotchMeetingEar {
            let meeting = Meeting(title: "Design review", startDate: now.addingTimeInterval(startsIn),
                                  endDate: now.addingTimeInterval(startsIn + 3_600))
            return NotchMeetingEar(NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: startsIn)), now: now)
        }
        XCTAssertEqual(ear(startsIn: 3 * 3_600).kind, .later)
        XCTAssertNil(ear(startsIn: 3 * 3_600).fuse)

        let hour = ear(startsIn: 33 * 60)
        XCTAssertEqual(hour.kind, .hour)
        XCTAssertEqual(hour.minutes, 33)
        XCTAssertEqual(hour.fuse, CrenelNotchFuse(fraction: 0.55, tone: .white))

        // The fuse rescales to the last ten minutes.
        let urgent = ear(startsIn: 8 * 60)
        XCTAssertEqual(urgent.kind, .urgent)
        XCTAssertEqual(urgent.fuse?.tone, .amber)
        XCTAssertEqual(urgent.fuse?.fraction ?? 0, 0.8, accuracy: 0.001)

        XCTAssertEqual(ear(startsIn: 23 * 3_600).kind, .otherDay)

        let meeting = Meeting(title: "Design review", startDate: now.addingTimeInterval(-42 * 60), endDate: now.addingTimeInterval(18 * 60))
        let live = NotchMeetingEar(NotchAgendaStatus(item: meeting, phase: .ongoing(remaining: 18 * 60)), now: now)
        XCTAssertEqual(live.kind, .live)
        XCTAssertEqual(live.minutes, 18)
        XCTAssertEqual(live.fuse?.fraction ?? 0, 0.3, accuracy: 0.001)
    }

    func testPromptsDictationAndResultsBecomeStrips() {
        let now = self.now
        let recording = NotchCompactStatus.RecordingStatus(startedAt: now.addingTimeInterval(-768), clientID: .zoom, microphoneState: .open)
        let session = UUID()

        // A call was detected and nothing is being recorded.
        var input = NotchClosedInput(status: .idle, prompt: .recordingOffer(sessionID: session, clientID: .zoom), now: now)
        input.detectedMeetingTitle = "Partner call"
        XCTAssertEqual(NotchClosedResolver.state(input), .callDetected(clientID: .zoom, title: "Partner call"))
        XCTAssertTrue(NotchClosedResolver.state(input).isStrip)

        // Recording: plain ears, until the call seems to end.
        XCTAssertFalse(NotchClosedResolver.state(NotchClosedInput(status: .recording(recording), now: now)).isStrip)
        let ended = NotchClosedResolver.state(NotchClosedInput(
            status: .recording(recording), prompt: .endConfirmation(sessionID: session, clientID: .zoom), now: now))
        XCTAssertEqual(ended, .recording(recording, prompt: .ended))
        XCTAssertTrue(ended.isStrip)

        let deadline = now.addingTimeInterval(MeetingSessionLifecyclePolicy.autoStopCountdown / 2)
        let autoStop = NotchClosedResolver.state(NotchClosedInput(
            status: .recording(recording), prompt: .autoStop(sessionID: session, clientID: .zoom, deadline: deadline), now: now))
        XCTAssertEqual(autoStop.fuse(now: now), CrenelNotchFuse(fraction: 0.5, tone: .red))

        // Dictation wins over everything and carries the words.
        let listening = NotchClosedResolver.state(NotchClosedInput(
            status: .dictation(.listening(startedAt: now, level: 0.4)), partialTranscript: "Let’s move", now: now))
        XCTAssertEqual(listening, .dictationListening(text: "Let’s move"))
        XCTAssertEqual(NotchClosedResolver.state(NotchClosedInput(status: .dictation(.refining), now: now)),
                       .dictationWorking(step: 1, text: ""))

        // Results.
        XCTAssertEqual(NotchClosedResolver.state(NotchClosedInput(status: .completed, now: now)), .ready(nil, actionItems: nil))
        let stored = StoredMeeting(id: UUID(), title: "Design review", startedAt: now.addingTimeInterval(-2_880),
                                   endedAt: now, sourceMeeting: nil, audioFileName: "a.m4a")
        // The strip counts the notes' action items when they are known.
        XCTAssertEqual(
            NotchClosedResolver.state(NotchClosedInput(status: .completed, completedMeeting: stored, completedActionItems: 3, now: now)),
            .ready(stored, actionItems: 3)
        )
        XCTAssertEqual(NotchClosedText.readySentence(actionItems: 3), "Notes and 3 action items")
        let network = AppFailure.network("Couldn’t reach transcription")
        XCTAssertEqual(
            NotchClosedResolver.state(NotchClosedInput(status: .failed, failure: network, lastStoredMeeting: stored, now: now)),
            .failed(network, title: "Design review", audioSaved: true)
        )
        // A failure before anything was saved must not promise saved audio.
        let permission = AppFailure.permission("Microphone access is off.", settings: true)
        XCTAssertEqual(
            NotchClosedResolver.state(NotchClosedInput(status: .failed, failure: permission, lastStoredMeeting: stored, now: now)),
            .failed(permission, title: nil, audioSaved: false)
        )

        // Plain states stay compact.
        for state in [NotchClosedState.idle, .tasks(count: 5), .processing(.transcribing)] {
            XCTAssertFalse(state.isStrip)
        }
    }

    func testStartingNowStripNeedsALinkAndCanBePutOff() {
        let now = self.now
        let call = Meeting(title: "Design review", startDate: now.addingTimeInterval(30), endDate: now.addingTimeInterval(3_630),
                           meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), kind: .onlineMeeting)
        let agenda = NotchAgendaStatus(item: call, phase: .upcoming(startsIn: 30))
        XCTAssertEqual(NotchClosedResolver.state(NotchClosedInput(status: .agenda(agenda), now: now)), .meetingStarting(call))
        // "Later" folds it back to the countdown.
        XCTAssertEqual(
            NotchClosedResolver.state(NotchClosedInput(status: .agenda(agenda), dismissedStartingMeetingID: call.id, now: now)),
            .meeting(agenda)
        )
        // Nothing to join: no strip.
        let room = Meeting(title: "Site visit", startDate: now.addingTimeInterval(30), endDate: now.addingTimeInterval(3_630),
                           kind: .meeting, location: "Warehouse")
        let roomAgenda = NotchAgendaStatus(item: room, phase: .upcoming(startsIn: 30))
        XCTAssertEqual(NotchClosedResolver.state(NotchClosedInput(status: .agenda(roomAgenda), now: now)), .meeting(roomAgenda))
        // Well into the meeting it is just a meeting in progress.
        let late = now.addingTimeInterval(600)
        let ongoing = NotchAgendaStatus(item: call, phase: .ongoing(remaining: 3_030))
        XCTAssertEqual(NotchClosedResolver.state(NotchClosedInput(status: .agenda(ongoing), now: late)), .meeting(ongoing))
    }

    func testAppStateFeedsTheClosedNotch() {
        let now = self.now
        let state = AppState(initialFlow: .recording(startedAt: now.addingTimeInterval(-60)))
        state.presentMeetingLifecyclePrompt(.endConfirmation(sessionID: UUID(), clientID: .zoom))
        guard case .recording(_, .ended) = state.closedNotchState(now: now) else {
            return XCTFail("expected the 'call seems to have ended' strip")
        }

        let dictating = AppState()
        dictating.updateDictationState(.listening(startedAt: now, level: 0.5))
        dictating.updateDictationPartialTranscript("Ship the notarized build")
        XCTAssertEqual(dictating.closedNotchState(now: now), .dictationListening(text: "Ship the notarized build"))
    }

    // MARK: Gallery — closed states

    func testEveryClosedStateRenders() throws {
        let now = self.now
        let review = Meeting(title: "Design review", startDate: now, endDate: now.addingTimeInterval(3_600),
                             meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), kind: .onlineMeeting)
        func upcoming(_ startsIn: TimeInterval) -> NotchClosedState {
            var meeting = review
            meeting.startDate = now.addingTimeInterval(startsIn)
            meeting.endDate = meeting.startDate.addingTimeInterval(3_600)
            return .meeting(NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: startsIn)))
        }
        var later = review
        later.startDate = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: now) ?? now
        later.endDate = later.startDate.addingTimeInterval(3_600)
        var live = review
        live.startDate = now.addingTimeInterval(-42 * 60)
        live.endDate = now.addingTimeInterval(18 * 60)
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: now) ?? now) ?? now
        let visit = Meeting(title: "Site visit", startDate: tomorrowStart, endDate: tomorrowStart.addingTimeInterval(3_600),
                            kind: .meeting, location: "Warehouse")

        func recording(_ mic: MeetingMicrophoneState, elapsed: TimeInterval = 768) -> NotchCompactStatus.RecordingStatus {
            .init(startedAt: now.addingTimeInterval(-elapsed), clientID: .zoom, microphoneState: mic)
        }
        let dictated = "Let’s move the design review to Thursday afternoon, and send Deniz the new onboarding copy before then"
        let stored = StoredMeeting(id: UUID(), title: "Design review", startedAt: now.addingTimeInterval(-48 * 60),
                                   endedAt: now, sourceMeeting: nil, audioFileName: "a.m4a")
        let task = TaskItem(title: "Write release notes", createdAt: now, status: .inProgress,
                            startedAt: now.addingTimeInterval(-25 * 60))

        let update = AppUpdateVersion(shortVersion: "1.2", releaseNotesURL: URL(string: "https://example.com/notes"), changeCount: 3)
        let states: [(String, NotchClosedState, Double)] = [
            ("c-idle", .idle, 0),
            ("c-standby-next", .standby(.nextEvent(visit)), 0),
            ("c-standby-dictation", .standby(.dictationKey("fn")), 0),
            ("c-meeting-later", .meeting(NotchAgendaStatus(item: later, phase: .upcoming(startsIn: later.startDate.timeIntervalSince(now)))), 0),
            ("c-meeting-hour", upcoming(33 * 60), 0),
            ("c-meeting-urgent", upcoming(8 * 60), 0),
            ("c-meeting-live", .meeting(NotchAgendaStatus(item: live, phase: .ongoing(remaining: 18 * 60))), 0),
            ("c-meeting-tomorrow", .meeting(NotchAgendaStatus(item: visit, phase: .upcoming(startsIn: tomorrowStart.timeIntervalSince(now)))), 0),
            ("c-recording", .recording(recording(.open), prompt: nil), 0.75),
            ("c-recording-micoff", .recording(recording(.closed), prompt: nil), 0.75),
            ("c-recording-unknown", .recording(recording(.unknown), prompt: nil), 0.75),
            ("c-proc-saving", .processing(.finalizing), 0),
            ("c-proc-uploading", .processing(.uploading(progress: 0.42)), 0),
            ("c-proc-transcribing", .processing(.transcribing), 0),
            ("c-proc-summarizing", .processing(.summarizing), 0),
            ("c-focus", .focus(task), 0),
            ("c-tasks", .tasks(count: 5), 0),
            ("c-update-downloading", .updating(progress: 0.42), 0),
            ("c-update-preparing", .updating(progress: nil), 0),
            ("c-update-ready", .updateReady(update), 0),
            ("c-update-pending", .updatePending(update), 0),
            ("c-update-recording", .recording(recording(.open, elapsed: 1_447), prompt: .updateWaiting), 0.75),
            ("c-update-restarting", .restarting, 0),
            ("c-update-updated", .updated(update), 0),
            ("c-meeting-now", .meetingStarting(review), 0),
            ("c-prompt-offer", .callDetected(clientID: .zoom, title: "Partner call"), 0),
            ("c-prompt-offer-meet", .callDetected(clientID: .googleMeetChrome, title: "Design review"), 0),
            ("c-prompt-ended", .recording(recording(.open, elapsed: 2_892), prompt: .ended), 0),
            ("c-prompt-autostop", .recording(recording(.open, elapsed: 2_892),
                prompt: .autoStop(deadline: now.addingTimeInterval(MeetingSessionLifecyclePolicy.autoStopCountdown * 0.8))), 0),
            ("c-dict-listening", .dictationListening(text: dictated), 0.75),
            ("c-dict-working", .dictationWorking(step: 1, text: dictated), 0),
            ("c-dict-inserted", .dictationInserted(DictationResultSummary(text: dictated + ".", delivery: .insertedViaPaste, appName: "Notes")), 0),
            ("c-dict-failed", .dictationFailed(.microphonePermissionDenied), 0),
            ("c-dict-failed-nospeech", .dictationFailed(.noSpeechDetected), 0),
            ("c-dict-failed-model", .dictationFailed(.speechAssetsMissing(localeIdentifier: "en-US")), 0),
            ("c-ready", .ready(stored, actionItems: 3), 0),
            ("c-failed", .failed(.network("Couldn’t reach transcription"), title: "Design review", audioSaved: true), 0),
            ("c-failed-permission", .failed(.permission("Microphone access is off.", settings: true), title: nil, audioSaved: false), 0)
        ]

        for (name, state, level) in states {
            let view = NotchClosedView(state: state, now: now, level: level, targetAppName: "Notes")
            let host = try render(compact: AnyView(view), name: name)
            if state.isStrip {
                // The strip is exactly 440 wide whatever its words are.
                XCTAssertEqual(NSHostingView(rootView: view.environment(\.crenelNotchMetrics, metrics)).fittingSize.width,
                               Hud.Notch.stripWidth, accuracy: 0.5, name)
            }
            _ = host
        }
    }

    /// The same states through the real path: `CrenelCompactView` reading `AppState`.
    func testCompactViewRendersFromAppState() throws {
        let now = Date()
        let agenda = AppState()
        agenda.updateCalendarAccessState(.authorized)
        agenda.updateUpcomingMeetings([
            Meeting(title: "Weekly product sync", startDate: now.addingTimeInterval(33 * 60), endDate: now.addingTimeInterval(93 * 60),
                    meetingURL: URL(string: "https://zoom.us/j/1"), kind: .onlineMeeting)
        ])
        try render(compact: AnyView(CrenelCompactView().environmentObject(agenda)), name: "live-agenda")

        let offer = AppState()
        offer.presentMeetingLifecyclePrompt(.recordingOffer(sessionID: UUID(), clientID: .googleMeetChrome))
        try render(compact: AnyView(CrenelCompactView().environmentObject(offer)), name: "live-offer")

        let recording = AppState(initialFlow: .recording(startedAt: now.addingTimeInterval(-83)))
        recording.updateMeetingMicrophoneGate(MeetingMicrophoneGate(recordingStartedAt: now.addingTimeInterval(-83)))
        recording.updateRecordingCaptureStatus(RecordingCaptureStatus(
            microphone: AudioSourceStatus(connectionState: .ready, level: 0.6),
            systemAudio: AudioSourceStatus(connectionState: .ready, level: 0.4)))
        try render(compact: AnyView(CrenelCompactView().environmentObject(recording)), name: "live-recording")

        // A screen without a notch: the ears sit side by side on the floating panel.
        let model = CrenelNotchModel()
        model.metrics = CrenelNotchMetrics(hardware: CGSize(width: 0, height: 24), hasPhysicalNotch: false)
        model.presentation = .compact
        try renderRoot(model: model, expanded: AnyView(EmptyView()),
                       compact: AnyView(CrenelCompactView().environmentObject(agenda)),
                       name: "live-agenda-no-notch", size: CGSize(width: 520, height: 120))
    }

    // MARK: Gallery — band

    func testBandRenders() throws {
        func state() -> AppState {
            let state = AppState()
            state.updateNotchPanelAvailableSize(CGSize(width: 812, height: 640))
            state.updateCalendarAccessState(.authorized)
            state.updateUpcomingMeetings([
                Meeting(title: "Design review", startDate: now.addingTimeInterval(3 * 3_600 + 48 * 60),
                        endDate: now.addingTimeInterval(4 * 3_600 + 48 * 60),
                        meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), kind: .onlineMeeting)
            ])
            state.replaceTasks((1...5).map { TaskItem(title: "Task \($0)", createdAt: now) })
            return state
        }

        let today = state()
        try render(expanded: AnyView(NotchPanelView().environmentObject(today)), name: "band-today")

        let tasks = state()
        tasks.selectedTab = .tasks
        try render(expanded: AnyView(NotchPanelView().environmentObject(tasks)), name: "band-tasks")

        let recordings = state()
        recordings.selectedTab = .recordings
        try render(expanded: AnyView(NotchPanelView().environmentObject(recordings)), name: "band-recordings")

        let pinned = state()
        _ = pinned.toggleNotchPin()
        try render(expanded: AnyView(NotchPanelView().environmentObject(pinned)), name: "band-pinned")

        // A prompt that arrives while the panel is open keeps its line under the band.
        let prompt = state()
        prompt.presentMeetingLifecyclePrompt(.recordingOffer(sessionID: UUID(), clientID: .zoom))
        try render(expanded: AnyView(NotchPanelView().environmentObject(prompt)), name: "band-prompt")

        // No camera housing: brand, tabs and tools share one row.
        let model = CrenelNotchModel()
        model.metrics = CrenelNotchMetrics(hardware: CGSize(width: 0, height: 24), hasPhysicalNotch: false)
        model.presentation = .expanded
        try renderRoot(model: model, expanded: AnyView(NotchPanelView().environmentObject(today)), compact: AnyView(EmptyView()),
                       name: "band-no-notch", size: CGSize(width: 860, height: 520))

        // The band alone, as wide as the panel: the camera row, then the tab row.
        let band = NotchBand(onTogglePin: {})
            .environmentObject(today)
            .frame(width: Hud.Notch.openWidth)
            .background(Color.black)
        let host = NSHostingView(rootView: band.environment(\.crenelNotchMetrics, metrics))
        XCTAssertEqual(host.fittingSize.height, 32 + Hud.Notch.tabRowHeight, accuracy: 0.5)
    }

    // MARK: Rendering

    @discardableResult
    private func render(compact content: AnyView, name: String) throws -> NSView {
        let model = CrenelNotchModel()
        model.metrics = metrics
        model.presentation = .compact
        return try renderRoot(model: model, expanded: AnyView(EmptyView()), compact: content, name: name,
                              size: CGSize(width: 520, height: 120))
    }

    @discardableResult
    private func render(expanded content: AnyView, name: String) throws -> NSView {
        let model = CrenelNotchModel()
        model.metrics = metrics
        model.presentation = .expanded
        return try renderRoot(model: model, expanded: content, compact: AnyView(EmptyView()), name: name,
                              size: CGSize(width: 640, height: 520))
    }

    @discardableResult
    private func renderRoot(model: CrenelNotchModel, expanded: AnyView, compact: AnyView, name: String, size: CGSize) throws -> NSView {
        let root = CrenelNotchRootView(model: model, expanded: { expanded }, compact: { compact }, onShapeFrameChange: { _ in })
            .background(Color(hud: 0x3B3B47))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        // Long enough for the shape spring and the delayed content fade to settle.
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        if FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let path = root.appending(path: "artifacts/ui-audit/notch-shell/\(name).png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
        }
        return host
    }
}
