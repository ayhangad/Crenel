import SwiftUI

struct NotchPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onToggleMeetingMicrophone: () -> Void
    let onDismissMeetingPrompt: () -> Void
    let onContinueRecording: () -> Void
    let onConfirmMeetingEnded: () -> Void
    let onCancelFlow: () -> Void
    let onRecoverFromFailure: (AppFailure) -> Void
    let onOpenStoredMeeting: (StoredMeeting) -> Void
    let onCopyText: (String) -> Void
    let onExportMarkdown: (String, StoredMeeting) -> Void
    let onRevealAudio: (URL) -> Void
    let onDeleteStoredMeeting: (StoredMeeting) -> Void
    let onRetryStoredMeeting: (StoredMeeting) -> Void
    let onOpenRecovery: () -> Void
    let onTogglePin: () -> Void
    let onRelaunchApplication: () -> Void
    let analysisActions: MeetingAnalysisActions

    init(
        onRequestCalendarAccess: @escaping () -> Void = {},
        onOpenMeetingURL: @escaping (URL) -> Void = { _ in },
        onStartRecording: @escaping () -> Void = {},
        onStopRecording: @escaping () -> Void = {},
        onToggleMeetingMicrophone: @escaping () -> Void = {},
        onDismissMeetingPrompt: @escaping () -> Void = {},
        onContinueRecording: @escaping () -> Void = {},
        onConfirmMeetingEnded: @escaping () -> Void = {},
        onCancelFlow: @escaping () -> Void = {},
        onRecoverFromFailure: @escaping (AppFailure) -> Void = { _ in },
        onOpenStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
        onCopyText: @escaping (String) -> Void = { _ in },
        onExportMarkdown: @escaping (String, StoredMeeting) -> Void = { _, _ in },
        onRevealAudio: @escaping (URL) -> Void = { _ in },
        onDeleteStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
        onRetryStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
        onOpenRecovery: @escaping () -> Void = {},
        onTogglePin: @escaping () -> Void = {},
        onRelaunchApplication: @escaping () -> Void = {},
        analysisActions: MeetingAnalysisActions = MeetingAnalysisActions()
    ) {
        self.analysisActions = analysisActions
        self.onRequestCalendarAccess = onRequestCalendarAccess
        self.onOpenMeetingURL = onOpenMeetingURL
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onToggleMeetingMicrophone = onToggleMeetingMicrophone
        self.onDismissMeetingPrompt = onDismissMeetingPrompt
        self.onContinueRecording = onContinueRecording
        self.onConfirmMeetingEnded = onConfirmMeetingEnded
        self.onCancelFlow = onCancelFlow
        self.onRecoverFromFailure = onRecoverFromFailure
        self.onOpenStoredMeeting = onOpenStoredMeeting
        self.onCopyText = onCopyText
        self.onExportMarkdown = onExportMarkdown
        self.onRevealAudio = onRevealAudio
        self.onDeleteStoredMeeting = onDeleteStoredMeeting
        self.onRetryStoredMeeting = onRetryStoredMeeting
        self.onOpenRecovery = onOpenRecovery
        self.onTogglePin = onTogglePin
        self.onRelaunchApplication = onRelaunchApplication
    }

    @Environment(\.crenelNotchMetrics) private var notchMetrics

    var body: some View {
        let showsDetail = appState.presentedMeetingDetail != nil
        let layout = NotchPanelLayout(
            availableSize: appState.notchPanelAvailableSize,
            preferredWidth: NotchPanelLayout.preferredWidth
        )

        VStack(alignment: .leading, spacing: Crenel.Space.l) {
            if let detail = appState.presentedMeetingDetail {
                MeetingDetailToolbar(
                    content: detail,
                    onBack: appState.dismissMeetingDetail,
                    onCopyText: onCopyText
                )
                .transition(.crenelMorph())
            } else {
                NotchPanelHeader(
                    compact: layout.width < 460,
                    onTogglePin: onTogglePin
                )
                .transition(.crenelMorph())
            }

            NotchPanelScrollableContent(
                maximumHeight: layout.maximumContentHeight,
                bottomContentInset: showsDetail ? Crenel.Space.l : 0
            ) {
                ZStack(alignment: .top) {
                    if let detail = appState.presentedMeetingDetail {
                        MeetingDetailView(
                            content: detail,
                            onCopyText: onCopyText,
                            onExportMarkdown: { markdown in
                                onExportMarkdown(markdown, detail.meeting)
                            },
                            onRevealAudio: onRevealAudio,
                            onRetry: onRetryStoredMeeting,
                            onDelete: onDeleteStoredMeeting,
                            analysisActions: analysisActions,
                            isProcessing: appState.processingJobs.contains { $0.meetingID == detail.id && $0.state != .failed },
                            importedActionIDs: Set(appState.tasks.filter { $0.sourceMeetingID == detail.id }.compactMap(\.sourceActionID))
                        )
                        .id(detail.id)
                        .transition(.crenelMorph())
                    } else {
                        switch appState.selectedTab {
                        case .meetings:
                            MeetingStatusView(
                                onRequestCalendarAccess: onRequestCalendarAccess,
                                onOpenMeetingURL: onOpenMeetingURL,
                                onStartRecording: onStartRecording,
                                onStopRecording: onStopRecording,
                                onToggleMeetingMicrophone: onToggleMeetingMicrophone,
                                onDismissMeetingPrompt: onDismissMeetingPrompt,
                                onContinueRecording: onContinueRecording,
                                onConfirmMeetingEnded: onConfirmMeetingEnded,
                                onCancelFlow: onCancelFlow,
                                onRecoverFromFailure: onRecoverFromFailure,
                                onOpenStoredMeeting: onOpenStoredMeeting,
                                onDeleteStoredMeeting: onDeleteStoredMeeting,
                                onRetryStoredMeeting: onRetryStoredMeeting,
                                onOpenRecovery: onOpenRecovery,
                                onRelaunchApplication: onRelaunchApplication
                            )
                            .transition(tabTransition(for: .meetings))
                        case .tasks:
                            TasksView()
                                .transition(tabTransition(for: .tasks))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        // Clear the menu-bar band (and camera housing) the notch starts under, and keep
        // content inside the flared walls of the shape.
        .padding(.top, notchMetrics.topInset + Crenel.Space.s)
        .padding(.horizontal, Crenel.Space.xxl)
        .padding(.bottom, Crenel.Space.xl)
        .frame(width: layout.width)
        .meetingNotchPanelAppearance(
            hasPhysicalNotch: appState.notchPanelHasPhysicalNotch
        )
        .onMoveCommand { direction in
            guard appState.presentedMeetingDetail == nil else { return }
            switch direction {
            case .left:
                appState.selectPanelTab(offset: -1)
            case .right:
                appState.selectPanelTab(offset: 1)
            default:
                break
            }
        }
        .animation(motion(Crenel.Motion.morph), value: appState.presentedMeetingDetail?.id)
        .animation(motion(Crenel.Motion.morph), value: appState.selectedTab)
        .animation(motion(Crenel.Motion.morph), value: layout.width)
    }

    private func motion(_ animation: Animation) -> Animation {
        Crenel.Motion.resolve(animation, reduceMotion: reduceMotion)
    }

    /// Tabs slide in from the side they sit on in the header.
    private func tabTransition(for tab: AppState.PanelTab) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let edge: CGFloat = tab == .meetings ? -24 : 24
        return .asymmetric(
            insertion: .crenelMorph().combined(with: .offset(x: edge)),
            removal: .opacity.combined(with: .offset(x: edge * 0.5))
        )
    }
}

/// Shows short content at its natural height and scrolls content taller than the cap.
/// One scroll container for all content, so view state (an open task card, a typed
/// draft) survives content growing past the cap.
struct NotchPanelScrollableContent<Content: View>: View {
    let maximumHeight: CGFloat
    let bottomContentInset: CGFloat
    let content: Content
    @State private var contentHeight: CGFloat?

    init(
        maximumHeight: CGFloat,
        bottomContentInset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.maximumHeight = maximumHeight
        self.bottomContentInset = bottomContentInset
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, bottomContentInset)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    contentHeight = height
                }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight.map { min($0, maximumHeight) })
        .frame(maxHeight: maximumHeight)
    }
}

/// Header of the open notch: the crenel mark, the two surfaces, and window controls.
private struct NotchPanelHeader: View {
    @EnvironmentObject private var appState: AppState
    let compact: Bool
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: Crenel.Space.m) {
            CrenelIcon(.logo, size: 20)
                .foregroundStyle(Crenel.Palette.textPrimary)
                .accessibilityLabel("Crenel")

            CrenelSegmented(
                selection: $appState.selectedTab,
                items: [
                    .init(value: AppState.PanelTab.meetings, title: AppState.PanelTab.meetings.rawValue, glyph: .sun),
                    .init(value: .tasks, title: AppState.PanelTab.tasks.rawValue, glyph: .tasks, badge: appState.activeTaskCount)
                ],
                compact: compact
            )
            .background {
                // ⌘1 / ⌘2 switch surfaces.
                ForEach(AppState.PanelTab.allCases) { tab in
                    Button("") { appState.selectedTab = tab }
                        .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Panel tabs")

            Spacer(minLength: Crenel.Space.s)

            Button {
                NotificationCenter.default.post(name: .openDesktopWorkspace, object: nil)
            } label: {
                CrenelIcon(.window, size: 15)
            }
            .buttonStyle(CrenelIconButtonStyle())
            .help("Open in window")
            .accessibilityLabel("Open in window")

            Button(action: onTogglePin) {
                CrenelIcon(.pin, size: 15)
                    .rotationEffect(.degrees(appState.isNotchPinned ? 0 : 35))
            }
            .buttonStyle(CrenelIconButtonStyle(tint: appState.isNotchPinned ? Crenel.Palette.focus : Crenel.Palette.textSecondary, isActive: appState.isNotchPinned))
            .animation(Crenel.Motion.bouncy, value: appState.isNotchPinned)
            .help(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
            .accessibilityLabel(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
            .accessibilityValue(appState.isNotchPinned ? "Pinned" : "Not pinned")
        }
    }
}

private extension AppState.PanelTab {
    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .meetings: "1"
        case .tasks: "2"
        }
    }
}

private struct FigmaGateButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .meetingControlFeedback(radius: 16, restingBorder: false)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct NotchTabButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private extension MeetingFlowState {
    var isRecordingPhase: Bool {
        if case .recording = self { return true }
        return false
    }
}

private struct MeetingStatusView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCancelConfirmation = false
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onToggleMeetingMicrophone: () -> Void
    let onDismissMeetingPrompt: () -> Void
    let onContinueRecording: () -> Void
    let onConfirmMeetingEnded: () -> Void
    let onCancelFlow: () -> Void
    let onRecoverFromFailure: (AppFailure) -> Void
    let onOpenStoredMeeting: (StoredMeeting) -> Void
    let onDeleteStoredMeeting: (StoredMeeting) -> Void
    let onRetryStoredMeeting: (StoredMeeting) -> Void
    let onOpenRecovery: () -> Void
    let onRelaunchApplication: () -> Void

    var body: some View {
        let presentation = MeetingFlowPresentation(
            state: appState.meetingFlow,
            nextMeeting: appState.nextMeeting,
            reminderLevel: appState.meetingReminderLevel
        )

        VStack(alignment: .leading, spacing: Crenel.Space.xl) {
            VStack(alignment: .leading, spacing: Crenel.Space.m) {
                if !showsMeetingLists, !appState.meetingFlow.isRecordingPhase {
                    todayHeader
                }
                todayContent(presentation: presentation)
            }

            if showsMeetingLists {
                if let recoverySummary = appState.recordingRecoverySummary {
                    RecordingRecoveryNoticeView(
                        summary: recoverySummary,
                        onOpenRecovery: onOpenRecovery,
                        onDismiss: appState.dismissRecordingRecoverySummary
                    )
                }
                RecentMeetingsList(
                    meetings: Array(appState.storedMeetings.prefix(5)),
                    onOpen: onOpenStoredMeeting,
                    onDelete: onDeleteStoredMeeting,
                    onRetry: onRetryStoredMeeting
                )
            }
        }
        .alert(cancelConfirmationTitle, isPresented: $showsCancelConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(cancelConfirmationButtonTitle, role: .destructive) {
                onCancelFlow()
            }
        } message: {
            Text(cancelConfirmationMessage)
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: appState.meetingFlow.phase
        )
    }

    private var showsMeetingLists: Bool {
        switch appState.meetingFlow {
        case .idle, .upcomingMeeting:
            true
        default:
            false
        }
    }

    private var scheduledMeetings: [Meeting] {
        var timed = Array(appState.upcomingMeetings.filter { !$0.isAllDay }.prefix(3))
        if let nextMeeting = appState.nextMeeting,
           !timed.contains(where: { $0.id == nextMeeting.id }) {
            timed.insert(nextMeeting, at: 0)
        }
        let allDay = appState.upcomingMeetings
            .filter { $0.isAllDay && Calendar.current.isDateInToday($0.startDate) }
            .prefix(2)
        return Array(timed.prefix(3)) + allDay
    }

    private var sectionTitle: String {
        switch appState.meetingFlow {
        case .idle, .upcomingMeeting: "Upcoming"
        case .preparingRecording: "Preparing"
        case .recording: "Recording"
        case .finalizingAudio: "Finishing"
        case .uploading, .transcribing, .summarizing: "Processing"
        case .completed: "Ready"
        case .failed: "Couldn’t finish"
        case .cancelled: "Stopped"
        }
    }

    private var todayHeader: some View {
        Text(sectionTitle).eyebrow(color: Crenel.Palette.textSecondary)
            .padding(.horizontal, Crenel.Space.xs)
    }

    @ViewBuilder
    private func todayContent(presentation: MeetingFlowPresentation) -> some View {
        switch appState.meetingFlow {
        case .idle, .upcomingMeeting:
            TodaySurface(
                events: scheduledMeetings,
                emptyMessage: CalendarEmptyPresentation.message(enabled: appState.isCalendarEnabled,
                    access: appState.calendarAccessState, snapshot: appState.calendarIntegrationSnapshot),
                canRequestCalendarAccess: appState.isCalendarEnabled && appState.calendarAccessState != .authorized,
                onRequestCalendarAccess: onRequestCalendarAccess,
                onOpenMeetingURL: onOpenMeetingURL,
                onStartRecording: onStartRecording
            )

            if appState.meetingSessionDetection?.session.clientID == .googleMeetChrome,
               appState.browserAudioConnectionStatus == .unavailable || appState.browserAudioConnectionStatus == .waitingForMeetTab {
                FigmaWarningRow(
                    text: googleMeetBridgeStatusText,
                    isCritical: appState.browserAudioConnectionStatus == .unavailable
                )
                .accessibilityLabel("Google Meet audio: \(googleMeetBridgeStatusText)")
            }

            if let prompt = appState.meetingLifecyclePrompt {
                MeetingLifecyclePromptView(
                    prompt: prompt,
                    onStartRecording: onStartRecording,
                    onDismiss: onDismissMeetingPrompt,
                    onContinueRecording: onContinueRecording,
                    onConfirmEnd: onConfirmMeetingEnded
                )
            }

        case .recording(let startedAt):
            recordingSurface(startedAt: startedAt)

        default:
            fallbackFlowSurface(presentation: presentation)
        }
    }

    private func recordingSurface(startedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: Crenel.Space.m) {
            VStack(alignment: .leading, spacing: Crenel.Space.l) {
                HStack(alignment: .center, spacing: Crenel.Space.l) {
                    CrenelOrb(
                        top: .white,
                        bottom: Crenel.Palette.record,
                        level: Double(max(appState.recordingCaptureStatus.microphone.level, appState.recordingCaptureStatus.systemAudio.level)),
                        density: 14
                    )
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            CrenelPulseDot(color: Crenel.Palette.record, size: 6)
                            Text("Recording").eyebrow(color: Crenel.Palette.record)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(CrenelCompactView.elapsed(context.date.timeIntervalSince(startedAt)))
                                .crenelText(.display)
                                .contentTransition(.numericText())
                                .accessibilityLabel(NotchAccessibilityContract.recordingDurationLabel(CrenelCompactView.elapsed(context.date.timeIntervalSince(startedAt))))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let gate = appState.meetingMicrophoneGate {
                        Button(action: onToggleMeetingMicrophone) {
                            CrenelIcon(gate.permitsAudio ? .mic : .micOff, size: 17)
                        }
                        .buttonStyle(CrenelIconButtonStyle(
                            diameter: 44,
                            tint: gate.state == .open ? Crenel.Palette.textPrimary : (gate.state == .unknown ? Crenel.Palette.warning : Crenel.Palette.textTertiary),
                            fill: Crenel.Palette.layer2
                        ))
                        .help("Turn meeting mic on, or off for privacy (⌥⌘M)")
                        .accessibilityLabel(NotchAccessibilityContract.microphoneGateLabel(gate.state))
                    }

                    Button(action: onStopRecording) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Crenel.Palette.record)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(CrenelIconButtonStyle(diameter: 44, tint: Crenel.Palette.record, fill: Crenel.Palette.record.opacity(0.18)))
                    .contextMenu {
                        Button("Delete recording", role: .destructive) { showsCancelConfirmation = true }
                    }
                    .help("Stop recording")
                    .accessibilityLabel("Stop recording")
                }

                CaptureSourcesView(status: appState.recordingCaptureStatus)

                if let gate = appState.meetingMicrophoneGate {
                    HStack(spacing: 6) {
                        Text(gate.state == .open ? "Your voice is being recorded" : (gate.state == .unknown ? "Mic state unknown; kept off" : "Your voice isn’t being recorded"))
                        Spacer(minLength: 4)
                        CrenelKeyCap(label: "⌥⌘M")
                    }
                    .crenelText(.caption, color: gate.state == .unknown ? Crenel.Palette.warning : Crenel.Palette.textTertiary)
                }
            }
            .padding(Crenel.Space.l)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Crenel.Radius.l, style: .continuous).fill(Crenel.Palette.layer1)
                    CrenelAura(tint: Crenel.Palette.record, intensity: 0.5)
                        .clipShape(RoundedRectangle(cornerRadius: Crenel.Radius.l, style: .continuous))
                }
            }
            .crenelSurface(.clear)

            ForEach(recordingWarnings, id: \.self) { warning in
                FigmaWarningRow(text: warning, isCritical: true)
            }

            if let prompt = appState.meetingLifecyclePrompt {
                MeetingLifecyclePromptView(
                    prompt: prompt,
                    onStartRecording: onStartRecording,
                    onDismiss: onDismissMeetingPrompt,
                    onContinueRecording: onContinueRecording,
                    onConfirmEnd: onConfirmMeetingEnded
                )
            }
        }
    }

    private var recordingWarnings: [String] {
        var warnings: [String] = []
        if let gate = appState.meetingMicrophoneGate,
           let warning = microphonePrivacyWarning(for: gate) {
            warnings.append(warning)
        }
        if let message = appState.recordingCaptureStatus.microphone.connectionState.message {
            warnings.append(message)
        }
        if let message = appState.recordingCaptureStatus.systemAudio.connectionState.message {
            warnings.append(message)
        }
        if let message = appState.recordingSafetyMessage {
            warnings.append(message)
        }
        return warnings
    }

    private func fallbackFlowSurface(
        presentation: MeetingFlowPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(presentation.assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(presentation.color)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                    Text(presentation.detail)
                        .font(MeetingNotchTheme.MainPanel.bodyFont)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusMetric
            }

            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(presentation.color)
                    .accessibilityLabel("Progress")
            }

            if appState.meetingLifecyclePrompt == nil {
                actionArea
            }
        }
        .padding(16)
        .background(
            MeetingNotchTheme.MainPanel.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.MainPanel.surfaceRadius,
                style: .continuous
            )
        )
    }

    private var googleMeetBridgeStatusText: String {
        switch appState.browserAudioConnectionStatus {
        case .unavailable:
            "Google Meet audio bridge unavailable; recording won’t start."
        case .waitingForMeetTab:
            "Click the Crenel Chrome extension in the call tab."
        case .tabConnected:
            "Google Meet tab connected."
        case .recording:
            "Recording Google Meet tab audio."
        }
    }

    private var googleMeetBridgeStatusSymbol: String {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: "exclamationmark.shield.fill"
        case .waitingForMeetTab: "puzzlepiece.extension"
        case .tabConnected: "checkmark.shield.fill"
        case .recording: "record.circle.fill"
        }
    }

    private var microphoneNoticeSymbol: String {
        appState.recordingCaptureStatus.microphone.isReady
            ? "arrow.triangle.2.circlepath"
            : "mic.slash.fill"
    }

    private func microphonePrivacyWarning(
        for gate: MeetingMicrophoneGate
    ) -> String? {
        switch gate.events.last?.source {
        case .adapterUnavailable:
            "Can’t verify mic state. Your mic is kept out of the recording."
        case .processChanged:
            "Meeting app changed. Your mic is off until it’s verified."
        case .systemInterruption:
            "Mac is going to sleep. Mic is off and the recording is ending."
        default:
            nil
        }
    }

    @ViewBuilder
    private var statusMetric: some View {
        switch appState.meetingFlow {
        case .recording(let startedAt):
            HStack(spacing: 5) {
                Circle()
                    .fill(MeetingNotchTheme.MainPanel.danger)
                    .frame(width: 5, height: 5)
                RecordingElapsedTimeView(startedAt: startedAt)
            }
            .font(MeetingNotchTheme.dataFont.monospacedDigit())
            .foregroundStyle(MeetingNotchTheme.MainPanel.danger)
        case .upcomingMeeting(let meeting):
            MeetingCountdownView(startDate: meeting.startDate)
        case .uploading(let progress):
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(MeetingNotchTheme.dataFont.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.MainPanel.cyan)
        case .preparingRecording, .finalizingAudio, .transcribing, .summarizing:
            ProgressView()
                .controlSize(.mini)
                .tint(MeetingNotchTheme.MainPanel.cyan)
                .accessibilityLabel("Processing")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch appState.meetingFlow {
        case .idle:
            MeetingNotchActionGroup {
                if appState.calendarAccessState != .authorized {
                    Button {
                        onRequestCalendarAccess()
                    } label: {
                        FigmaActionLabel(calendarButtonTitle, assetName: "FigmaRecentCheck")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
                    .disabled(appState.calendarAccessState == .requesting)
                }

                if let url = appState.nextMeeting?.meetingURL {
                    Button {
                        onOpenMeetingURL(url)
                    } label: {
                        FigmaActionLabel("Join", assetName: "FigmaVideo")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
                }

                Button {
                    onStartRecording()
                } label: {
                    FigmaActionLabel("Start recording", assetName: "FigmaRecord")
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
            }

        case .upcomingMeeting(let meeting):
            MeetingNotchActionGroup {
                if let url = meeting.meetingURL {
                    Button {
                        onOpenMeetingURL(url)
                    } label: {
                        FigmaActionLabel("Join", assetName: "FigmaVideo")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
                }
                Button {
                    onStartRecording()
                } label: {
                    FigmaActionLabel("Start recording", assetName: "FigmaRecord")
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                Button {
                    appState.dismissCurrentMeetingReminder()
                } label: {
                    Text("Skip")
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
            }

        case .preparingRecording, .uploading, .transcribing, .summarizing:
            Button(role: .destructive) {
                showsCancelConfirmation = true
            } label: {
                FigmaActionLabel("Cancel", assetName: "FigmaStop")
            }
            .buttonStyle(MeetingNotchActionButtonStyle(kind: .danger))

        case .finalizingAudio:
            EmptyView()

        case .recording:
            MeetingNotchActionGroup {
                Button(role: .destructive) {
                    showsCancelConfirmation = true
                } label: {
                    FigmaActionLabel("Delete recording", assetName: "FigmaArchive")
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))

                Button(role: .destructive) {
                    onStopRecording()
                } label: {
                    FigmaActionLabel("Stop recording", assetName: "FigmaStop")
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .danger))
            }

        case .failed(let failure):
            if failure.category == .permission,
               failure.recoveryAction == .openSystemSettings {
                MeetingNotchActionGroup {
                    Button {
                        onRecoverFromFailure(failure)
                    } label: {
                        FigmaActionLabel("System Settings", assetName: "FigmaWarning")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))

                    Button(action: onRelaunchApplication) {
                        FigmaActionLabel("Relaunch", assetName: "FigmaVoice")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                }
            } else {
                Button {
                    onRecoverFromFailure(failure)
                } label: {
                    FigmaActionLabel(failure.recoveryButtonTitle, assetName: "FigmaWarning")
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
            }

        case .completed:
            MeetingNotchActionGroup {
                if let meeting = appState.completedMeeting {
                    Button {
                        onOpenStoredMeeting(meeting)
                    } label: {
                        FigmaActionLabel("Open details", assetName: "FigmaTasks")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
                }
                Button("OK") {
                    appState.resetFlow()
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
            }

        case .cancelled:
            Button("OK") {
                appState.resetFlow()
            }
            .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))

        }
    }

    private var calendarButtonTitle: String {
        switch appState.calendarAccessState {
        case .requesting:
            "Waiting for calendar…"
        case .denied, .restricted:
            "Calendar access"
        case .failed:
            "Reconnect"
        default:
            "Connect calendar"
        }
    }

    private var cancelConfirmationTitle: String {
        switch appState.meetingFlow.phase {
        case .recording:
            "Delete recording?"
        case .uploading, .transcribing, .summarizing:
            "Stop processing?"
        default:
            "Cancel recording setup?"
        }
    }

    private var cancelConfirmationButtonTitle: String {
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            "Stop processing"
        default:
            "Delete recording"
        }
    }

    private var cancelConfirmationMessage: String {
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            "The local audio is kept. You can retry transcription later from History."
        case .recording:
            "This recording isn’t saved to History yet. Mic and system audio will be deleted permanently."
        default:
            "Temporary recording files will be deleted."
        }
    }
}

private struct MeetingLifecyclePromptView: View {
    let prompt: MeetingLifecyclePrompt
    let onStartRecording: () -> Void
    let onDismiss: () -> Void
    let onContinueRecording: () -> Void
    let onConfirmEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MeetingNotchTheme.controlFont)
                    Text(detail)
                        .font(MeetingNotchTheme.bodyFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if case .autoStop(_, _, let deadline) = prompt {
                    AutoStopCountdownView(deadline: deadline)
                }
            }

            switch prompt {
            case .recordingOffer:
                MeetingNotchActionGroup {
                    Button("Not now", action: onDismiss)
                        .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
                    Button(action: onStartRecording) {
                        FigmaActionLabel("Start recording", assetName: "FigmaRecord")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                }
            case .endConfirmation, .autoStop:
                MeetingNotchActionGroup {
                    Button("Keep recording", action: onContinueRecording)
                        .buttonStyle(MeetingNotchActionButtonStyle(kind: .secondary))
                    Button(role: .destructive, action: onConfirmEnd) {
                        FigmaActionLabel("Stop now", assetName: "FigmaStop")
                    }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .danger))
                }
            }
        }
        .padding(16)
        .background(
            MeetingNotchTheme.MainPanel.warningSurface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.MainPanel.surfaceRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var title: String {
        switch prompt {
        case .recordingOffer:
            "Meeting detected"
        case .endConfirmation:
            "Meeting may have ended"
        case .autoStop:
            "Meeting ended"
        }
    }

    private var detail: String {
        switch prompt {
        case .recordingOffer(_, let clientID):
            "Record this \(clientName(clientID))?"
        case .endConfirmation:
            "Not sure it’s over. You can stop the recording yourself."
        case .autoStop:
            "Recording stops when the countdown ends."
        }
    }

    private var assetName: String {
        switch prompt {
        case .recordingOffer: "FigmaVideo"
        case .endConfirmation: "FigmaWarning"
        case .autoStop: "FigmaStop"
        }
    }

    private var tint: Color {
        switch prompt {
        case .recordingOffer: MeetingNotchTheme.MainPanel.cyan
        case .endConfirmation: MeetingNotchTheme.MainPanel.warning
        case .autoStop: MeetingNotchTheme.MainPanel.danger
        }
    }

    private func clientName(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "Zoom call"
        case .googleMeetChrome: "Google Meet call"
        case .unsupported, nil: "meeting"
        }
    }
}

private struct AutoStopCountdownView: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            Text("\(seconds) s")
                .font(MeetingNotchTheme.dataFont.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.MainPanel.danger)
                .accessibilityLabel("Recording stops in \(seconds) seconds")
        }
    }
}

private struct FigmaActionLabel: View {
    let title: String
    let assetName: String

    init(_ title: String, assetName: String) {
        self.title = title
        self.assetName = assetName
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(title)
        }
    }
}

private struct RecordingRecoveryNoticeView: View {
    let summary: RecordingRecoverySummary
    let onOpenRecovery: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(summary.preservedCount > 0 ? "FigmaWarning" : "FigmaRecentCheck")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    summary.preservedCount > 0
                        ? MeetingNotchTheme.MainPanel.warning
                        : MeetingNotchTheme.MainPanel.success
                )
                .frame(width: 20, height: 20)
                .padding(10)
                .background(
                    MeetingNotchTheme.MainPanel.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                if summary.recoveredCount > 0 {
                    Text("\(summary.recoveredCount) recordings recovered")
                }
                if summary.preservedCount > 0 {
                    Text("\(summary.preservedCount) recordings kept in Recovery")
                }
            }
            .font(MeetingNotchTheme.MainPanel.smallFont)
            .frame(maxWidth: .infinity, alignment: .leading)

            if summary.preservedCount > 0 {
                Button(action: onOpenRecovery) {
                    Image("FigmaArchive")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(MeetingNotchIconButtonStyle())
                .help("Show Recovery folder")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(MeetingNotchIconButtonStyle())
            .accessibilityLabel("Dismiss recovery notice")
        }
        .padding(16)
        .background(
            MeetingNotchTheme.MainPanel.warningSurface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.MainPanel.surfaceRadius,
                style: .continuous
            )
        )
    }
}

private struct FigmaWarningRow: View {
    let text: String
    let isCritical: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image("FigmaWarning")
                .resizable()
                .frame(width: 16, height: 16)

            Text(text)
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.warning)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .accessibilityHint(isCritical ? "Critical warning" : "Warning")
    }
}

private struct FigmaMeetingCountdownView: View {
    let startDate: Date
    var endDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let seconds = Int(startDate.timeIntervalSince(context.date))
            Text(Self.text(seconds: seconds, remaining: endDate.map { $0.timeIntervalSince(context.date) }))
                .font(MeetingNotchTheme.MainPanel.bodyFont.monospacedDigit())
                .foregroundStyle(
                    seconds <= 600
                        ? MeetingNotchTheme.MainPanel.danger
                        : MeetingNotchTheme.MainPanel.secondaryText
                )
                .lineLimit(1)
                .accessibilityLabel("Time left \(Self.text(seconds: seconds, remaining: endDate.map { $0.timeIntervalSince(context.date) }))")
        }
    }

    private static func text(seconds: Int, remaining: TimeInterval?) -> String {
        guard seconds > 0 else {
            guard let remaining, remaining > 0 else { return "Started" }
            return "Now · \(NotchAgendaFormatter.durationText(remaining)) left"
        }
        let minutes = Int(ceil(Double(seconds) / 60))
        guard minutes >= 60 else { return "\(minutes) min left" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? "\(hours) h left"
            : "\(hours) h \(remainingMinutes) min"
    }
}

private struct CaptureSourcesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: RecordingCaptureStatus

    var body: some View {
        HStack(spacing: Crenel.Space.xl) {
            source("Microphone", glyph: .mic, status: status.microphone)
            source("System audio", glyph: .speaker, status: status.systemAudio)
        }
    }

    private func source(_ title: String, glyph: CrenelGlyph, status: AudioSourceStatus) -> some View {
        HStack(spacing: Crenel.Space.s) {
            CrenelIcon(glyph, size: 13)
                .foregroundStyle(sourceColor(status.connectionState))
            Text(title)
                .crenelText(.caption, color: Crenel.Palette.textSecondary)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Crenel.Palette.layer3)
                    Capsule()
                        .fill(sourceColor(status.connectionState) == Crenel.Palette.textSecondary ? Crenel.Palette.record : sourceColor(status.connectionState))
                        .frame(width: proxy.size.width * CGFloat(min(max(status.level, 0), 1)))
                }
            }
            .frame(height: 4)
            .animation(Crenel.Motion.resolve(.smooth(duration: 0.12), reduceMotion: reduceMotion), value: status.level)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 16)
        .accessibilityElement(children: .combine)
        .help(status.connectionState.message ?? (status.isReady ? "Ready" : "Preparing"))
        .accessibilityLabel(accessibilityLabel(title: title, status: status))
    }

    private func sourceColor(_ state: AudioSourceConnectionState) -> Color {
        switch state {
        case .ready: Crenel.Palette.textSecondary
        case .preparing, .recovered, .pipelineRecovered: Crenel.Palette.warning
        case .disconnected, .pipelineStalled: Crenel.Palette.danger
        }
    }

    private func accessibilityLabel(title: String, status: AudioSourceStatus) -> String {
        if let message = status.connectionState.message {
            return "\(title): \(message)"
        }
        return "\(title) \(status.isReady ? "ready" : "preparing")"
    }
}

private struct MeetingMicrophoneGateControl: View {
    let gate: MeetingMicrophoneGate
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(gate.permitsAudio ? "FigmaMicrophone" : "FigmaMicrophoneOff")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Meeting mic: \(title)")
                        .font(MeetingNotchTheme.MainPanel.smallMediumFont)
                        .foregroundStyle(color)
                    Text(gate.state == .open ? "Your voice is being recorded" : "Your voice isn’t being recorded")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("⌥⌘M").font(MeetingNotchTheme.metadataFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .padding(6).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        }
        .buttonStyle(FigmaGateButtonStyle())
        .help("Turn mic recording on, or off for privacy (⌥⌘M)")
        .accessibilityLabel("Meeting mic \(title). Press Option Command M to change.")
    }

    private var title: String {
        switch gate.state {
        case .open: "On"
        case .closed: "Off"
        case .unknown: "Unknown"
        }
    }

    private var color: Color {
        switch gate.state {
        case .open: MeetingNotchTheme.MainPanel.success
        case .closed: MeetingNotchTheme.MainPanel.secondaryText
        case .unknown: MeetingNotchTheme.MainPanel.warning
        }
    }
}

private struct NotchRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct MeetingCountdownView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(startDate.timeIntervalSince(context.date))
            Text(Self.text(seconds: seconds))
                .font(MeetingNotchTheme.dataFont)
                .foregroundStyle(
                    seconds > 60
                        ? MeetingNotchTheme.MainPanel.warning
                        : MeetingNotchTheme.MainPanel.danger
                )
                .accessibilityLabel("Meeting starts in \(Self.text(seconds: seconds))")
        }
    }

    private static func text(seconds: Int) -> String {
        guard seconds > 0 else { return "Meeting started" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

enum DictationStatusText {
    static func title(for state: DictationState) -> String {
        switch state {
        case .idle: "Dictation ready"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .refining: "Refining"
        case .inserting: "Inserting"
        case .inserted(let summary): summary.message
        case .failed(let failure): failure.message
        }
    }

    static func short(for failure: DictationFailure) -> String {
        switch failure {
        case .noFocusedTextField: "Copied"
        case .speechAssetsDownloading, .speechAssetsMissing: "Downloading"
        case .accessibilityPermissionMissing, .inputMonitoringPermissionMissing, .microphonePermissionDenied: "Needs access"
        case .tooShort, .noSpeechDetected: "No speech"
        default: "Failed"
        }
    }
}

private struct RecordingElapsedTimeView: View {
    let startedAt: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = Self.format(context.date.timeIntervalSince(startedAt))
            Text(duration)
                .font(
                    compact
                        ? MeetingNotchTheme.metadataFont.monospacedDigit()
                        : MeetingNotchTheme.MainPanel.bodyFont.monospacedDigit()
                )
                .accessibilityLabel(
                    NotchAccessibilityContract.recordingDurationLabel(duration)
                )
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct MeetingFlowPresentation {
    let assetName: String
    let compactAssetName: String
    let color: Color
    let title: String
    let detail: String
    let progress: Double?

    init(
        state: MeetingFlowState,
        nextMeeting: Meeting?,
        reminderLevel: MeetingReminderLevel
    ) {
        switch state {
        case .idle:
            let title = nextMeeting?.title ?? "No upcoming meetings"
            let detail = nextMeeting.map {
                "Next: \($0.startDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.locale)))"
            } ?? "Start a recording whenever you’re ready."
            self.init(
                assetName: "FigmaRecord",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.primaryText,
                title: title,
                detail: detail
            )
        case .upcomingMeeting(let meeting):
            let detail: String
            switch reminderLevel {
            case .oneMinute:
                detail = "Starts in under a minute"
            case .tenMinutes:
                detail = "Starts in under 10 minutes"
            case .started:
                detail = "Meeting started"
            case .none:
                detail = meeting.startDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale))
            }
            self.init(
                assetName: "FigmaVideo",
                compactAssetName: "FigmaVideo",
                color: MeetingNotchTheme.MainPanel.warning,
                title: meeting.title,
                detail: detail
            )
        case .preparingRecording:
            self.init(
                assetName: "FigmaMicrophone",
                compactAssetName: "FigmaMicrophone",
                color: MeetingNotchTheme.MainPanel.warning,
                title: "Preparing recording",
                detail: "Checking audio sources and permissions."
            )
        case .recording(let startedAt):
            self.init(
                assetName: "FigmaRecord",
                compactAssetName: "FigmaRecord",
                color: MeetingNotchTheme.MainPanel.danger,
                title: "Recording",
                detail: "Started at \(startedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: AppLanguage.locale)))"
            )
        case .finalizingAudio:
            self.init(
                assetName: "FigmaStop",
                compactAssetName: "FigmaStop",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Finishing audio",
                detail: "Wrapping up the recording."
            )
        case .uploading(let progress):
            self.init(
                assetName: "FigmaArrowUp",
                compactAssetName: "FigmaArrowUp",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Uploading",
                detail: "Sending audio for transcription.",
                progress: progress
            )
        case .transcribing:
            self.init(
                assetName: "FigmaVoice",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Transcribing",
                detail: "Separating speakers."
            )
        case .summarizing:
            self.init(
                assetName: "FigmaTasks",
                compactAssetName: "FigmaTasks",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Summarizing",
                detail: "Pulling out decisions and action items."
            )
        case .completed:
            self.init(
                assetName: "FigmaRecentCheck",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.success,
                title: "Recording saved",
                detail: "Mic and system audio saved on this Mac."
            )
        case .cancelled:
            self.init(
                assetName: "FigmaStop",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.secondaryText,
                title: "Cancelled",
                detail: "You can start a new recording."
            )
        case .failed(let failure):
            self.init(
                assetName: "FigmaWarning",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.danger,
                title: failure.title,
                detail: failure.message
            )
        }
    }

    private init(
        assetName: String,
        compactAssetName: String,
        color: Color,
        title: String,
        detail: String,
        progress: Double? = nil
    ) {
        self.assetName = assetName
        self.compactAssetName = compactAssetName
        self.color = color
        self.title = title
        self.detail = detail
        self.progress = progress
    }
}

#if DEBUG
private struct NotchPanelAuditPreview: View {
    @StateObject private var appState: AppState
    let profile: NotchPreviewProfile

    init(profile: NotchPreviewProfile) {
        self.profile = profile
        let startedAt = Date().addingTimeInterval(-83)
        let initialFlow: MeetingFlowState = profile.auditFocus == .voiceOver
            ? .recording(startedAt: startedAt)
            : .idle
        let state = AppState(initialFlow: initialFlow)
        if profile.auditFocus == .keyboard {
            state.selectedTab = .tasks
        }
        if profile.auditFocus == .voiceOver {
            state.updateMeetingMicrophoneGate(
                MeetingMicrophoneGate(recordingStartedAt: startedAt)
            )
        }
        _appState = StateObject(wrappedValue: state)
    }

    var body: some View {
        NotchPanelView()
            .environmentObject(appState)
            .environment(
                \.colorScheme,
                profile.colorScheme == .light ? .light : .dark
            )
            .contrast(profile.increasedContrast ? 1.35 : 1)
            .transaction { transaction in
                if profile.reducesMotion {
                    }
            }
    }
}

#Preview("Light · Standard") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[0])
}

#Preview("Dark · Standard") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[1])
}

#Preview("Light · Increase Contrast") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[2])
}

#Preview("Dark · Reduce Motion") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[3])
}

#Preview("Keyboard · Tasks") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[4])
}

#Preview("VoiceOver · Recording") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[5])
}
#endif
