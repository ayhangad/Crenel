import AppKit
import SwiftUI
import XCTest
@testable import Crenel

final class NotchPresentationTests: XCTestCase {
    func testRecordingOutranksMeetingAndTasks() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))

        let status = NotchStatusResolver.compactStatus(
            flow: .recording(startedAt: startedAt),
            nextMeeting: meeting,
            activeTaskCount: 4
        )

        XCTAssertEqual(
            status,
            .recording(
                .init(
                    startedAt: startedAt,
                    clientID: nil,
                    microphoneState: .unknown
                )
            )
        )
    }

    func testRecordingCompactStatusCarriesSessionClientAndMicrophoneGate() {
        let startedAt = Date(timeIntervalSince1970: 100)
        var gate = MeetingMicrophoneGate(recordingStartedAt: startedAt)
        gate.setManualState(.open, at: startedAt.addingTimeInterval(1))
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(clientID: .zoom, processID: 123),
            audioProcess: nil,
            client: nil
        )

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .recording(startedAt: startedAt),
                nextMeeting: nil,
                activeTaskCount: 0,
                meetingDetection: detection,
                microphoneGate: gate
            ),
            .recording(
                .init(
                    startedAt: startedAt,
                    clientID: .zoom,
                    microphoneState: .open
                )
            )
        )
    }

    func testEveryProcessingPhaseOutranksMeetingAndTasks() {
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))
        let cases: [(MeetingFlowState, NotchCompactStatus)] = [
            (.preparingRecording, .processing(.preparing)),
            (.finalizingAudio, .processing(.finalizing)),
            (.uploading(progress: 0.42), .processing(.uploading(progress: 0.42))),
            (.transcribing, .processing(.transcribing)),
            (.summarizing, .processing(.summarizing))
        ]

        for (flow, expected) in cases {
            XCTAssertEqual(
                NotchStatusResolver.compactStatus(
                    flow: flow,
                    nextMeeting: meeting,
                    activeTaskCount: 4
                ),
                expected
            )
        }
    }

    func testFailureAndCompletionOutrankMeetingAndTasks() {
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .failed(.network("Bağlantı yok")),
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .failed
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .completed(meetingID: UUID()),
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .completed
        )
    }

    func testMeetingOutranksTasksAndTasksOutrankIdle() {
        let startDate = Date(timeIntervalSince1970: 200)
        let meeting = makeMeeting(startDate: startDate)

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: meeting,
                activeTaskCount: 4,
                now: startDate.addingTimeInterval(-300)
            ),
            .agenda(NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: 300)))
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: nil,
                activeTaskCount: 4
            ),
            .tasks(count: 4)
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: nil,
                activeTaskCount: 0
            ),
            .idle
        )
    }

    func testPanelUsesPreferredSizeOnLargeScreenAndStaysWithinSmallScreen() {
        let viewport = NotchHostViewport(windowSize: CGSize(width: 860, height: 760), topInset: 32)
        XCTAssertEqual(viewport.availableSize, CGSize(width: 812, height: 704))
        XCTAssertEqual(
            NotchPanelLayout(availableSize: viewport.availableSize),
            // C13: the tab lamp → content gap is 20 visible, so less of a 704 pt viewport is
            // left for content than the preferred 600.
            NotchPanelLayout(width: Hud.Notch.openWidth,
                             maximumContentHeight: min(NotchPanelLayout.preferredContentHeight, 704 - NotchPanelLayout.fixedVerticalSpace))
        )

        let small = NotchHostViewport(windowSize: CGSize(width: 860, height: 612), topInset: 24)
        XCTAssertEqual(small.availableSize, CGSize(width: 812, height: 564))
        XCTAssertEqual(
            NotchPanelLayout(availableSize: small.availableSize).maximumContentHeight,
            564 - NotchPanelLayout.fixedVerticalSpace
        )

        let constrained = NotchPanelLayout(availableSize: CGSize(width: 328, height: 250))
        XCTAssertEqual(constrained.width, 328)
        XCTAssertEqual(constrained.maximumContentHeight, 250 - NotchPanelLayout.fixedVerticalSpace)
        XCTAssertLessThanOrEqual(constrained.width, 328)
        XCTAssertLessThanOrEqual(
            constrained.maximumContentHeight + NotchPanelLayout.fixedVerticalSpace,
            250
        )
    }

    @MainActor
    func testPanelScrollAreaFitsShortContentAndCapsLongContent() {
        let shortContent = NSHostingView(
            rootView: NotchPanelScrollableContent(maximumHeight: 120) {
                Color.clear.frame(height: 48)
            }
            .frame(width: 300)
        )
        let longContent = NSHostingView(
            rootView: NotchPanelScrollableContent(maximumHeight: 120) {
                Color.clear.frame(height: 240)
            }
            .frame(width: 300)
        )

        XCTAssertEqual(shortContent.fittingSize.height, 48, accuracy: 0.5)
        XCTAssertEqual(longContent.fittingSize.height, 120, accuracy: 0.5)

        let detailContent = NSHostingView(
            rootView: NotchPanelScrollableContent(
                maximumHeight: 120,
                bottomContentInset: 20
            ) {
                Color.clear.frame(height: 48)
            }
            .frame(width: 300)
        )
        XCTAssertEqual(detailContent.fittingSize.height, 68, accuracy: 0.5)
    }


    func testOnlyCompletionResetsAfterTransientPresentation() {
        let completed = MeetingFlowState.completed(meetingID: UUID())
        let failed = MeetingFlowState.failed(.network("Bağlantı yok"))

        XCTAssertTrue(NotchTransientStatusPolicy.shouldPresent(completed))
        XCTAssertTrue(NotchTransientStatusPolicy.shouldResetAfterTimeout(completed))
        XCTAssertTrue(NotchTransientStatusPolicy.shouldPresent(failed))
        XCTAssertFalse(NotchTransientStatusPolicy.shouldResetAfterTimeout(failed))
        XCTAssertFalse(NotchTransientStatusPolicy.shouldPresent(.transcribing))
    }

    func testReducedMotionProfileRemovesPerceptibleTransitionDurations() {
        let standard = NotchMotionProfile.resolved(reducesMotion: false)
        let reduced = NotchMotionProfile.resolved(reducesMotion: true)

        XCTAssertEqual(standard.openingDuration, 0.28)
        XCTAssertEqual(standard.closingDuration, 0.2)
        XCTAssertEqual(standard.conversionDuration, 0.3)
        XCTAssertTrue(reduced.reducesMotion)
        XCTAssertLessThanOrEqual(reduced.openingDuration, 0.01)
        XCTAssertLessThanOrEqual(reduced.closingDuration, 0.01)
        XCTAssertLessThanOrEqual(reduced.conversionDuration, 0.01)
    }

    func testPreviewAuditMatrixCoversAppearanceMotionKeyboardAndVoiceOver() {
        let matrix = NotchPreviewProfile.requiredMatrix

        XCTAssertEqual(Set(matrix.map(\.colorScheme)), Set(NotchPreviewColorScheme.allCases))
        XCTAssertTrue(matrix.contains(where: \.increasedContrast))
        XCTAssertTrue(matrix.contains(where: \.reducesMotion))
        XCTAssertEqual(Set(matrix.map(\.auditFocus)), Set(NotchPreviewAuditFocus.allCases))
        XCTAssertEqual(Set(matrix.map(\.name)).count, matrix.count)
    }

    func testPanelTokensKeepTheCompactInstrumentGeometry() {
        XCTAssertEqual(NotchPanelLayout.preferredWidth, Hud.Notch.openWidth)
        XCTAssertEqual(NotchPanelLayout.preferredDetailWidth, Hud.Notch.openWidth)
        // Hover fills bleed `rowInset` past the text and still clear the notch wall.
        XCTAssertGreaterThan(Hud.Size.panelInset - Hud.Size.rowInset, 12)
        XCTAssertGreaterThanOrEqual(Hud.Size.row, 44)
    }

    func testInkIsOneWarmBacklitScale() {
        // "Gece sürüşü": ink is a hair warm (never pure grey) and steps down evenly.
        var previous = 2.0
        for ink in [Hud.Ink.text1, Hud.Ink.text2, Hud.Ink.text3, Hud.Ink.text4, Hud.Ink.ink5] {
            let color = NSColor(ink).usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(color.redComponent, color.greenComponent)
            XCTAssertGreaterThan(color.greenComponent, color.blueComponent)
            XCTAssertLessThan(color.redComponent - color.blueComponent, 0.04)
            XCTAssertLessThan(Double(color.redComponent), previous)
            previous = Double(color.redComponent)
        }
    }

    @MainActor
    func testRedesignedAuxiliarySurfacesRender() throws {
        let settingsState = AppState()
        let onboardingState = AppState()
        let compactState = AppState(initialFlow: .completed(meetingID: UUID()))
        let detailState = AppState()
        detailState.updateNotchPanelPresentation(
            availableSize: CGSize(width: 660, height: 405),
            hasPhysicalNotch: true
        )
        let detailMeeting = StoredMeeting(
            id: UUID(),
            title: "Ürün tasarım değerlendirmesi",
            startedAt: Date().addingTimeInterval(-2_400),
            endedAt: Date(),
            sourceMeeting: nil,
            audioFileName: "ui-audit.m4a",
            processingStatus: .completed
        )
        detailState.presentMeetingDetail(
            MeetingDetailContent(
                meeting: detailMeeting,
                storedTranscription: StoredTranscription(
                    transcript: Transcript(
                        text: "",
                        languageCode: "tr",
                        segments: [
                            TranscriptSegment(
                                speakerID: "speaker_0",
                                speakerName: "Ayhan",
                                startTime: 12,
                                endTime: 24,
                                text: "Tüm yüzeyler ortak Figma token sistemini kullanacak."
                            ),
                            TranscriptSegment(
                                speakerID: "speaker_1",
                                speakerName: "Deniz",
                                startTime: 28,
                                endTime: 42,
                                text: "Kompakt durumlar ve ayarlar da aynı ikon diline taşınacak."
                            )
                        ]
                    ),
                    summary: MeetingSummary(
                        overview: "Crenel arayüzü tek ve tutarlı bir koyu tasarım sisteminde birleştirildi.",
                        decisions: ["20 piksel ikon ızgarası kullanılacak."],
                        actionItems: [ActionItem(title: "Görsel regresyon matrisini çalıştır.")]
                    )
                ),
                markdown: "# Ürün tasarım değerlendirmesi",
                audioURL: URL(fileURLWithPath: "/tmp/ui-audit.m4a")
            )
        )

        let cases: [(name: String, view: AnyView, size: CGSize)] = [
            (
                "settings",
                AnyView(SettingsView().environmentObject(settingsState)),
                CGSize(width: 600, height: 760)
            ),
            (
                "onboarding",
                AnyView(
                    OnboardingView(setup: .preview(), onComplete: {})
                    .environmentObject(onboardingState)
                ),
                CGSize(width: 560, height: 680)
            ),
            (
                "compact",
                AnyView(
                    CrenelCompactView()
                    .padding(12)
                    .background(Color.black)
                    .environmentObject(compactState)
                ),
                CGSize(width: 240, height: 48)
            ),
            (
                "detail",
                AnyView(NotchPanelView().environmentObject(detailState)),
                CGSize(width: 600, height: 405)
            )
        ]

        for item in cases {
            let hostingView = NSHostingView(rootView: item.view)
            hostingView.appearance = NSAppearance(named: .aqua)
            hostingView.frame = CGRect(origin: .zero, size: item.size)
            hostingView.layoutSubtreeIfNeeded()

            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                return XCTFail("\(item.name) bitmap'i üretilemedi")
            }
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

            if FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") {
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    return XCTFail("\(item.name) PNG verisi üretilemedi")
                }
                let projectRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let outputURL = projectRoot
                    .appendingPathComponent("artifacts/ui-audit/figma-\(item.name).png")
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: outputURL, options: .atomic)
            }
        }
    }

    @MainActor
    func testPhysicalNotchPanelRendersWhenSystemAppearanceIsLight() throws {
        let state = AppState()
        state.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )

        let rootView = ZStack(alignment: .top) {
            Color.black
            NotchPanelView()
                .environmentObject(state)
        }
        .frame(width: Hud.Size.panelWidth, height: 560, alignment: .top)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: Hud.Size.panelWidth, height: 560)
        )
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return XCTFail("Notch panel bitmap'i üretilemedi")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

        if FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") {
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                return XCTFail("Notch panel PNG verisi üretilemedi")
            }
            let projectRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let outputURL = projectRoot
                .appendingPathComponent("artifacts/ui-audit/after.png")
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: outputURL, options: .atomic)
        }
    }

    @MainActor
    func testMainPanelStatesRender() throws {
        let now = Date()
        let upcomingState = AppState()
        upcomingState.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )
        upcomingState.updateUpcomingMeetings([
            Meeting(
                title: "Ürün haftalık toplantısı",
                startDate: now.addingTimeInterval(420),
                endDate: now.addingTimeInterval(2_220),
                meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
            ),
            Meeting(
                title: "Tasarım değerlendirmesi",
                startDate: now.addingTimeInterval(4_200),
                endDate: now.addingTimeInterval(6_000)
            )
        ])
        let recentTitles = [
            "Yol haritası planlama",
            "Mobil ekip senkronizasyonu",
            "Müşteri görüşmesi",
            "Sprint değerlendirmesi"
        ]
        var recentMeetings: [StoredMeeting] = []
        for index in recentTitles.indices {
            let startedAt = now.addingTimeInterval(TimeInterval(-7_200 * (index + 1)))
            let endedAt = startedAt.addingTimeInterval(1_840)
            let status: StoredMeeting.ProcessingStatus = index == 3 ? .processing : .completed
            recentMeetings.append(
                StoredMeeting(
                    id: UUID(),
                    title: recentTitles[index],
                    startedAt: startedAt,
                    endedAt: endedAt,
                    sourceMeeting: nil,
                    audioFileName: "audit-\(index).m4a",
                    processingStatus: status
                )
            )
        }
        upcomingState.replaceStoredMeetings(recentMeetings)

        let emptyState = AppState()
        emptyState.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )

        let recordingStartedAt = now.addingTimeInterval(-83)
        let recordingState = AppState(initialFlow: .recording(startedAt: recordingStartedAt))
        recordingState.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )
        recordingState.updateMeetingMicrophoneGate(
            MeetingMicrophoneGate(recordingStartedAt: recordingStartedAt)
        )
        recordingState.updateRecordingCaptureStatus(
            RecordingCaptureStatus(
                microphone: AudioSourceStatus(connectionState: .ready, level: 0.72),
                systemAudio: AudioSourceStatus(connectionState: .ready, level: 0.46)
            )
        )

        let tasksState = AppState()
        tasksState.selectedTab = .tasks
        tasksState.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )
        tasksState.replaceTasks([
            TaskItem(title: "Araştırma notlarını toparla", createdAt: now),
            TaskItem(title: "Toplantı gündemini paylaş", createdAt: now, dueDate: now, dueHasTime: false),
            TaskItem(title: "Kayıt akışını gözden geçir", createdAt: now, status: .inProgress),
            TaskItem(title: "Erişilebilirlik kontrolünü tamamla", createdAt: now, priority: .high)
        ])

        let cases: [(name: String, state: AppState, height: CGFloat)] = [
            ("meetings", upcomingState, 482),
            ("empty", emptyState, 650),
            ("recording", recordingState, 304),
            ("tasks", tasksState, 550)
        ]

        for item in cases {
            let rootView = ZStack(alignment: .top) {
                Color.black
                NotchPanelView()
                    .environmentObject(item.state)
            }
            .frame(width: Hud.Size.panelWidth, height: item.height, alignment: .top)

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.appearance = NSAppearance(named: .aqua)
            hostingView.frame = CGRect(
                origin: .zero,
                size: CGSize(width: Hud.Size.panelWidth, height: item.height)
            )
            hostingView.layoutSubtreeIfNeeded()

            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                return XCTFail("\(item.name) panel bitmap'i üretilemedi")
            }
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

            if FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") {
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    return XCTFail("\(item.name) panel PNG verisi üretilemedi")
                }
                let projectRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let outputURL = projectRoot
                    .appendingPathComponent("artifacts/ui-audit/figma-\(item.name).png")
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: outputURL, options: .atomic)
            }
        }
    }

    func testKeyboardAndVoiceOverContractsAreCompleteAndUnambiguous() {
        let tabLabels = AppState.PanelTab.allCases.map(NotchAccessibilityContract.tabLabel)
        let shortcuts = AppState.PanelTab.allCases.map(
            NotchAccessibilityContract.tabShortcutDescription
        )

        XCTAssertEqual(Set(tabLabels).count, AppState.PanelTab.allCases.count)
        XCTAssertEqual(Set(shortcuts).count, AppState.PanelTab.allCases.count)
        XCTAssertTrue(shortcuts.allSatisfy { $0.hasPrefix("Command ") })

        XCTAssertEqual(
            NotchAccessibilityContract.recordingSessionLabel(clientID: .zoom),
            "Recording Zoom session"
        )
        XCTAssertEqual(
            NotchAccessibilityContract.recordingSessionLabel(clientID: .googleMeetChrome),
            "Recording Google Meet session"
        )
        XCTAssertEqual(
            NotchAccessibilityContract.microphoneGateLabel(.unknown),
            "Meeting microphone unknown, kept off"
        )
        XCTAssertEqual(
            NotchAccessibilityContract.recordingDurationLabel("01:23"),
            "Recording time 01:23"
        )
    }

    private func makeMeeting(startDate: Date) -> Meeting {
        Meeting(
            title: "Planlama",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            externalIdentifier: "planlama"
        )
    }
}

// Synthetic fixtures exercise layout only. No microphone, calendar account or remote API is used.
extension NotchPresentationTests {
    @MainActor
    func testCompleteNotchLifecycleAtStandardAndConstrainedWidths() throws {
        let now = Date()
        let upcoming = Meeting(title: "Ürün stratejisi ve tasarım kararları için haftalık değerlendirme",
            startDate: now.addingTimeInterval(420), endDate: now.addingTimeInterval(2220),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        let flows: [(String, MeetingFlowState)] = [
            ("idle", .idle), ("upcoming", .upcomingMeeting(upcoming)),
            ("preparing", .preparingRecording), ("recording", .recording(startedAt: now.addingTimeInterval(-3783))),
            ("finalizing", .finalizingAudio), ("uploading", .uploading(progress: 0.42)),
            ("transcribing", .transcribing), ("summarizing", .summarizing),
            ("completed", .completed(meetingID: UUID())), ("cancelled", .cancelled),
            ("network-error", .failed(.network("Bağlantı kurulamadı. Ses kaydı bu Mac’te korunuyor.")))
        ]
        for (name, flow) in flows {
            for width: CGFloat in [600, 360] {
                let state = AppState(initialFlow: flow)
                state.updateNotchPanelPresentation(availableSize: CGSize(width: width, height: 640), hasPhysicalNotch: width == 600)
                if case .upcomingMeeting = flow {
                    state.updateUpcomingMeetings([upcoming])
                    state.updateCalendarAccessState(.authorized)
                }
                if flow.isRecording {
                    state.updateMeetingMicrophoneGate(MeetingMicrophoneGate(recordingStartedAt: now.addingTimeInterval(-3783)))
                }
                try auditRender(AnyView(NotchPanelView().environmentObject(state)),
                    name: "notch-\(name)-\(Int(width))", size: CGSize(width: width, height: 640))
            }
            let compact = AppState(initialFlow: flow)
            try auditRender(AnyView(CrenelCompactView()
                .padding(12).background(.black).environmentObject(compact)),
                name: "compact-\(name)", size: CGSize(width: 300, height: 48))
        }
        for mic in [MeetingMicrophoneState.open, .closed, .unknown] {
            let state = AppState(initialFlow: .recording(startedAt: now.addingTimeInterval(-83)))
            var gate = MeetingMicrophoneGate(recordingStartedAt: now.addingTimeInterval(-83))
            gate.observeClientState(mic, confidence: .confirmed, at: now)
            state.updateMeetingMicrophoneGate(gate)
            state.updateRecordingCaptureStatus(RecordingCaptureStatus(
                microphone: AudioSourceStatus(connectionState: .ready, level: 0.6),
                systemAudio: AudioSourceStatus(connectionState: .ready, level: 0.4)))
            try auditRender(AnyView(NotchPanelView().environmentObject(state)),
                name: "gate-\(mic.rawValue)", size: CGSize(width: 600, height: 480))
        }
        let prompts: [(String, MeetingLifecyclePrompt)] = [
            ("offer", .recordingOffer(sessionID: UUID(), clientID: .zoom)),
            ("uncertain-end", .endConfirmation(sessionID: UUID(), clientID: .googleMeetChrome)),
            ("auto-stop", .autoStop(sessionID: UUID(), clientID: .zoom, deadline: now.addingTimeInterval(5)))
        ]
        for (name, prompt) in prompts {
            let state = AppState(initialFlow: name == "offer" ? .idle : .recording(startedAt: now))
            state.presentMeetingLifecyclePrompt(prompt)
            try auditRender(AnyView(NotchPanelView().environmentObject(state)),
                name: "prompt-\(name)", size: CGSize(width: 600, height: 640))
        }
    }

    @MainActor
    func testEveryOnboardingStepAndLightSystemAppearanceRenders() throws {
        for step in OnboardingView.Step.allCases {
            let state = AppState()
            let view = OnboardingView(setup: .preview(), onComplete: {}, initialStep: step)
                .environmentObject(state)
            try auditRender(AnyView(view), name: "onboarding-\(step.rawValue)", size: CGSize(width: 560, height: 680))
        }
        let state = AppState(initialFlow: .uploading(progress: 0.72))
        try auditRender(AnyView(NotchPanelView().environmentObject(state)
            .environment(\.colorScheme, .light)), name: "light-system-appearance", size: CGSize(width: 600, height: 420))
    }

    @MainActor
    func testTaskArchivePermissionAndMeetingDetailVariantsRender() throws {
        for archived in [false, true] {
            for populated in [false, true] {
                let state = AppState()
                if populated {
                    state.replaceTasks([
                        TaskItem(title: "Müşteri görüşmesindeki tasarım kararlarını ve takip adımlarını ekip ile paylaş", dueDate: Date(), assignee: "Deniz"),
                        TaskItem(title: "İzin ve mikrofon senaryolarını doğrula", status: .inProgress),
                        TaskItem(title: "Görsel kontrol matrisi tamamlandı", status: .completed)
                    ])
                }
                let view = TasksView(initiallyShowsHistory: archived).environmentObject(state)
                try auditRender(AnyView(ScrollView { view.padding(12) }.background(.black)),
                    name: "tasks-\(archived ? "archive" : "active")-\(populated ? "populated" : "empty")", size: CGSize(width: 600, height: 500))
            }
        }
        for status in [AudioCapturePermissionStatus.authorized, .denied, .verificationRequired, .restricted] {
            let state = AppState()
            state.updateAudioCapturePermissions(AudioCapturePermissionSnapshot(microphone: status, systemAudio: status))
            state.updateAccessibilityPermission(granted: status == .authorized)
            try auditRender(AnyView(SettingsView(initialCategory: .recording).environmentObject(state)),
                name: "permissions-\(status.rawValue)", size: CGSize(width: 600, height: 1100))
        }
        for status in [StoredMeeting.ProcessingStatus.recorded, .processing, .failed, .completed] {
            let meeting = StoredMeeting(id: UUID(), title: "Ürün stratejisi ve sonraki adımlar", startedAt: Date().addingTimeInterval(-3800),
                endedAt: Date(), sourceMeeting: nil, audioFileName: "fixture.m4a", processingStatus: status)
            let transcript = Transcript(text: "", languageCode: "tr", segments: [
                TranscriptSegment(speakerID: "speaker_0", speakerName: "Deniz", startTime: 12, endTime: 22,
                    text: "Yeni tasarımda kullanıcı kayıt durumunu ve mikrofon gizliliğini tek bakışta anlayabilmeli."),
                TranscriptSegment(speakerID: "speaker_1", speakerName: "Ayşe", startTime: 25, endTime: 37,
                    text: "Toplantı sonunda görevleri sorumluları ve kaynaklarıyla birlikte kontrol edeceğiz.")
            ])
            let content = MeetingDetailContent(meeting: meeting,
                storedTranscription: status == .completed ? StoredTranscription(transcript: transcript,
                    summary: MeetingSummary(overview: "Kayıt deneyimi ve görev takibi birlikte değerlendirildi.",
                        decisions: ["Tüm ekranlarda ortak bir tasarım dili kullanılacak."],
                        actionItems: (1...9).map { ActionItem(title: "\($0). arayüz adımını gerçek toplantıda değerlendir.", assignee: "Deniz", sourceTime: 12) })) : nil,
                markdown: "# Toplantı notları", audioURL: URL(fileURLWithPath: "/tmp/ui-audit.m4a"))
            try auditRender(AnyView(VStack(spacing: 20) {
                MeetingDetailToolbar(content: content, onBack: {}, onCopyText: { _ in })
                ScrollView {
                    MeetingDetailView(content: content, onCopyText: { _ in }, onExportMarkdown: { _ in },
                        onRevealAudio: { _ in }, onRetry: { _ in }, onDelete: { _ in })
                }
            }.padding(20).background(Color(white: 0.06))),
                name: "detail-\(status.rawValue)", size: CGSize(width: 680, height: 1050))
        }
    }

    @MainActor
    func testInitialPanelLayoutIncludesSelectedRecordingsBeforeAppearAndStaysAtContentHeight() {
        let state = AppState()
        state.selectedTab = .recordings
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = (0..<24).map { row in
            StoredMeeting(id: UUID(), title: "Fixture meeting \(row)", startedAt: start.addingTimeInterval(Double(row * 120)),
                endedAt: start.addingTimeInterval(Double(row * 120 + 60)), sourceMeeting: nil, audioFileName: "fixture.m4a")
        }
        state.replaceStoredMeetings([fixture[0]])
        let host = NSHostingView(rootView: NotchPanelView().environmentObject(state).fixedSize())
        let first = host.fittingSize
        let container = NSView(frame: CGRect(origin: .zero, size: first))
        host.frame = container.bounds
        container.addSubview(host)
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let settled = host.fittingSize
        XCTAssertGreaterThan(settled.height, 100)
        XCTAssertEqual(first.height, settled.height, accuracy: 1)

        state.replaceStoredMeetings(fixture)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let tall = host.fittingSize
        XCTAssertGreaterThan(tall.height, settled.height + 150)
        state.replaceStoredMeetings([fixture[0]])
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(host.fittingSize.height, settled.height, accuracy: 1)
    }

    @MainActor
    func testTabChangesKeepScrollContainerAndHideIndicators() throws {
        let state = AppState()
        let host = NSHostingView(rootView: NotchPanelView().environmentObject(state))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        let container = NSView(frame: host.frame)
        container.addSubview(host)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        defer { window.contentView = nil }
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let original = try XCTUnwrap(scrollViews(host).first)
        for tab in [AppState.PanelTab.tasks, .meetings, .tasks, .meetings] {
            state.selectedTab = tab
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            let current = try XCTUnwrap(scrollViews(host).first)
            XCTAssertTrue(original === current, "Tab changes must preserve the scroll container")
            XCTAssertTrue(current.verticalScroller?.isHidden != false || current.verticalScroller?.alphaValue == 0)
            XCTAssertFalse(current.hasHorizontalScroller)
        }
    }

    @MainActor
    private func auditRender(_ view: AnyView, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view)
        // The audit owns the viewport; prevent hosting-view ideal sizing from resizing the window.
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let container = NSView(frame: host.frame)
        container.addSubview(host)
        host.autoresizingMask = [.width, .height]
        window.contentView = container
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, size.width + 1, "\(name): horizontal overflow")
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let path = root.appending(path: "artifacts/ui-audit/matrix/\(name).png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
        }
    }
}
