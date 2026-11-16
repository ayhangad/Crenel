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
    @State private var showsHistory = false

    var body: some View {
        let showsDetail = appState.presentedMeetingDetail != nil
        let layout = NotchPanelLayout(
            availableSize: appState.notchPanelAvailableSize,
            preferredWidth: Hud.Size.panelWidth
        )

        VStack(alignment: .leading, spacing: Hud.Space.x4) {
            Group {
                if let detail = appState.presentedMeetingDetail {
                    MeetingDetailToolbar(
                        content: detail,
                        onBack: appState.dismissMeetingDetail,
                        onCopyText: onCopyText
                    )
                } else {
                    NotchToolbar(showsHistory: $showsHistory, onTogglePin: onTogglePin)
                }
            }
            .transition(.opacity)

            NotchPanelScrollableContent(
                maximumHeight: layout.maximumContentHeight,
                bottomContentInset: showsDetail ? Hud.Space.x4 : 0
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
                        .transition(.opacity.combined(with: .offset(x: 14)))
                    } else if showsHistory {
                        VStack(alignment: .leading, spacing: Hud.Space.x3) {
                            if let recoverySummary = appState.recordingRecoverySummary {
                                RecordingRecoveryNoticeView(
                                    summary: recoverySummary,
                                    onOpenRecovery: onOpenRecovery,
                                    onDismiss: appState.dismissRecordingRecoverySummary
                                )
                            }
                            RecentMeetingsList(
                                meetings: Array(appState.storedMeetings.prefix(30)),
                                onOpen: onOpenStoredMeeting,
                                onDelete: onDeleteStoredMeeting,
                                onRetry: onRetryStoredMeeting
                            )
                        }
                        .transition(.opacity.combined(with: .offset(x: -14)))
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
        // Clear the menu-bar band (and camera housing) the notch starts under. Text sits
        // `panelInset` from the walls; hover fills reach `rowInset` beyond the text.
        .padding(.top, notchMetrics.topInset + Hud.Space.x2)
        .padding(.horizontal, Hud.Size.panelInset - Hud.Size.rowInset)
        .padding(.bottom, Hud.Space.x3)
        .frame(width: layout.width)
        .environment(\.colorScheme, .dark)
        .onMoveCommand { direction in
            guard appState.presentedMeetingDetail == nil else { return }
            switch direction {
            case .left:
                showsHistory = false
                appState.selectPanelTab(offset: -1)
            case .right:
                showsHistory = false
                appState.selectPanelTab(offset: 1)
            default:
                break
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in showsHistory = false }
        .animation(motion(Hud.Motion.change), value: appState.presentedMeetingDetail?.id)
        .animation(motion(Hud.Motion.change), value: appState.selectedTab)
        .animation(motion(Hud.Motion.change), value: showsHistory)
    }

    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : animation
    }

    /// Tabs slide in from the side they sit on.
    private func tabTransition(for tab: AppState.PanelTab) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(x: tab == .meetings ? -14 : 14))
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

/// One toolbar: the two surfaces centred under the camera, history on the left, window
/// controls on the right.
private struct NotchToolbar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showsHistory: Bool
    let onTogglePin: () -> Void

    var body: some View {
        ZStack {
            HudTabs(
                items: [
                    .init(tab: AppState.PanelTab.meetings, glyph: .calendar, title: AppState.PanelTab.meetings.title),
                    .init(tab: .tasks, glyph: .queue, title: AppState.PanelTab.tasks.title,
                          badge: appState.activeTaskCount > 0 ? appState.activeTaskCount : nil)
                ],
                selection: Binding(
                    get: { appState.selectedTab },
                    set: { tab in
                        showsHistory = false
                        appState.selectedTab = tab
                    }
                )
            )
            .background {
                // ⌘1 / ⌘2 switch surfaces.
                ForEach(AppState.PanelTab.allCases) { tab in
                    Button("") {
                        showsHistory = false
                        appState.selectedTab = tab
                    }
                    .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Panel tabs")

            HStack(spacing: 2) {
                Button {
                    showsHistory.toggle()
                } label: {
                    HudIcon(.history)
                }
                .buttonStyle(HudButtonStyle(kind: showsHistory ? .iconFilled : .icon))
                .help("Recordings")
                .accessibilityLabel("Recordings")
                .accessibilityAddTraits(showsHistory ? .isSelected : [])

                Spacer(minLength: Hud.Space.x2)

                Button {
                    NotificationCenter.default.post(name: .openDesktopWorkspace, object: nil)
                } label: {
                    HudIcon(.window)
                }
                .buttonStyle(HudButtonStyle(kind: .icon))
                .help("Open in window")
                .accessibilityLabel("Open in window")

                Button(action: onTogglePin) {
                    HudIcon(.pin)
                        .rotationEffect(.degrees(appState.isNotchPinned ? 0 : 30))
                }
                .buttonStyle(HudButtonStyle(kind: appState.isNotchPinned ? .iconFilled : .icon))
                .animation(Hud.Motion.glide, value: appState.isNotchPinned)
                .help(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
                .accessibilityLabel(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
                .accessibilityValue(appState.isNotchPinned ? "Pinned" : "Not pinned")
            }
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

    var title: String {
        switch self {
        case .meetings: String(localized: "Today")
        case .tasks: String(localized: "Tasks")
        }
    }
}

// MARK: - Today tab

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
    let onRelaunchApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Hud.Space.x3) {
            if let prompt = appState.meetingLifecyclePrompt {
                MeetingLifecyclePromptView(
                    prompt: prompt,
                    onStartRecording: onStartRecording,
                    onDismiss: onDismissMeetingPrompt,
                    onContinueRecording: onContinueRecording,
                    onConfirmEnd: onConfirmMeetingEnded
                )
                .transition(.opacity.combined(with: .offset(y: -6)))
            }

            switch appState.meetingFlow {
            case .idle, .upcomingMeeting:
                if appState.meetingSessionDetection?.session.clientID == .googleMeetChrome,
                   appState.browserAudioConnectionStatus == .unavailable || appState.browserAudioConnectionStatus == .waitingForMeetTab {
                    NotchNoticeRow(
                        text: googleMeetBridgeStatusText,
                        tint: appState.browserAudioConnectionStatus == .unavailable ? Hud.Ink.live : Hud.Ink.signal
                    )
                    .accessibilityLabel("Google Meet audio: \(googleMeetBridgeStatusText)")
                }
                TodaySurface(
                    events: agenda,
                    emptyMessage: CalendarEmptyPresentation.message(enabled: appState.isCalendarEnabled,
                        access: appState.calendarAccessState, snapshot: appState.calendarIntegrationSnapshot),
                    canRequestCalendarAccess: appState.isCalendarEnabled && appState.calendarAccessState != .authorized,
                    onRequestCalendarAccess: onRequestCalendarAccess,
                    onOpenMeetingURL: onOpenMeetingURL,
                    onStartRecording: onStartRecording
                )

            case .recording(let startedAt):
                recordingSurface(startedAt: startedAt)

            default:
                FlowSurface(
                    flow: appState.meetingFlow,
                    completedMeeting: appState.completedMeeting,
                    onCancel: { showsCancelConfirmation = true },
                    onOpenMeeting: onOpenStoredMeeting,
                    onDone: appState.resetFlow,
                    onRecover: onRecoverFromFailure,
                    onRelaunch: onRelaunchApplication
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
        .animation(reduceMotion ? nil : Hud.Motion.change, value: appState.meetingFlow.phase)
        .animation(reduceMotion ? nil : Hud.Motion.change, value: appState.meetingLifecyclePrompt != nil)
    }

    /// Today and the next few days, the next meeting first even if it starts later.
    private var agenda: [Meeting] {
        var items = appState.upcomingMeetings
        if let nextMeeting = appState.nextMeeting, !items.contains(where: { $0.id == nextMeeting.id }) {
            items.append(nextMeeting)
        }
        let sorted = items.sorted { lhs, rhs in
            (lhs.isAllDay ? 1 : 0, lhs.startDate) < (rhs.isAllDay ? 1 : 0, rhs.startDate)
        }
        return Array(sorted.prefix(8))
    }

    // MARK: Recording

    private func recordingSurface(startedAt: Date) -> some View {
        let gate = appState.meetingMicrophoneGate
        return VStack(alignment: .leading, spacing: Hud.Space.x3) {
            HStack(alignment: .center, spacing: Hud.Space.x3) {
                HudPulse(color: Hud.Ink.live)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = HudFormat.elapsed(context.date.timeIntervalSince(startedAt))
                    Text(elapsed)
                        .hud(.display)
                        .contentTransition(.numericText())
                        .accessibilityLabel(NotchAccessibilityContract.recordingDurationLabel(elapsed))
                }
                Spacer(minLength: Hud.Space.x2)

                if let gate {
                    Button(action: onToggleMeetingMicrophone) {
                        CrenelIcon(gate.permitsAudio ? .mic : .micOff, size: Hud.Size.icon)
                            .foregroundStyle(gate.state == .unknown ? Hud.Ink.signal : (gate.permitsAudio ? Hud.Ink.text1 : Hud.Ink.text3))
                    }
                    .buttonStyle(HudButtonStyle(kind: .iconFilled))
                    .help("Turn meeting mic on, or off for privacy (⌥⌘M)")
                    .accessibilityLabel(NotchAccessibilityContract.microphoneGateLabel(gate.state))
                }

                Button(action: onStopRecording) {
                    HudIcon(.stop, size: Hud.Size.icon).foregroundStyle(Hud.Ink.live)
                }
                .buttonStyle(HudButtonStyle(kind: .iconFilled))
                .contextMenu {
                    Button("Delete recording", role: .destructive) { showsCancelConfirmation = true }
                }
                .help("Stop recording")
                .accessibilityLabel("Stop recording")
            }
            .padding(.horizontal, Hud.Size.rowInset)

            VStack(alignment: .leading, spacing: 0) {
                CaptureSourceRow(
                    glyph: gate?.permitsAudio == false ? .micOff : .mic,
                    title: "Microphone",
                    status: appState.recordingCaptureStatus.microphone,
                    isMuted: gate.map { !$0.permitsAudio } ?? false
                )
                CaptureSourceRow(
                    glyph: .speaker,
                    title: "System audio",
                    status: appState.recordingCaptureStatus.systemAudio,
                    isMuted: false
                )
            }

            ForEach(recordingWarnings, id: \.self) { warning in
                NotchNoticeRow(text: warning, tint: Hud.Ink.live)
            }
        }
    }

    private var recordingWarnings: [String] {
        var warnings: [String] = []
        if let gate = appState.meetingMicrophoneGate {
            if let warning = microphonePrivacyWarning(for: gate) {
                warnings.append(warning)
            } else if gate.state == .unknown {
                warnings.append(String(localized: "Mic state unknown; kept off"))
            }
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

// MARK: - Recording pieces

/// One audio source: icon, name, and a segmented level that lives with the signal.
/// A muted source dims instead of disappearing, so the layout never moves.
private struct CaptureSourceRow: View {
    let glyph: CrenelGlyph
    let title: LocalizedStringKey
    let status: AudioSourceStatus
    let isMuted: Bool

    var body: some View {
        HStack(spacing: Hud.Space.x3) {
            CrenelIcon(glyph, size: Hud.Size.icon)
                .foregroundStyle(iconColor)
            Text(title).hud(.label, Hud.Ink.text2).lineLimit(1)
                .frame(width: 110, alignment: .leading)
            HudSegmentMeter(segments: 24, progress: isMuted ? 0 : Double(min(max(status.level, 0), 1)), tint: Hud.Ink.text1, height: 4)
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: 34)
        .opacity(isMuted ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .help(status.connectionState.message ?? (status.isReady ? "Ready" : "Preparing"))
        .accessibilityLabel(accessibilityText)
    }

    private var iconColor: Color {
        switch status.connectionState {
        case .ready: Hud.Ink.text2
        case .preparing, .recovered, .pipelineRecovered: Hud.Ink.signal
        case .disconnected, .pipelineStalled: Hud.Ink.live
        }
    }

    private var accessibilityText: Text {
        if let message = status.connectionState.message {
            return Text(title) + Text(": \(message)")
        }
        return Text(title) + Text(status.isReady ? " ready" : " preparing")
    }
}

/// A one-line notice: a small mark and a sentence, coloured by what it means.
private struct NotchNoticeRow: View {
    let text: String
    var tint: Color = Hud.Ink.signal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
            Circle().fill(tint).frame(width: 6, height: 6)
                .frame(width: Hud.Size.icon)
            Text(text)
                .hud(.meta, Hud.Ink.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x1)
    }
}

// MARK: - After recording

/// Saving, uploading, transcribing and summarizing as four steps; then the result.
private struct FlowSurface: View {
    let flow: MeetingFlowState
    let completedMeeting: StoredMeeting?
    let onCancel: () -> Void
    let onOpenMeeting: (StoredMeeting) -> Void
    let onDone: () -> Void
    let onRecover: (AppFailure) -> Void
    let onRelaunch: () -> Void

    private static let steps: [LocalizedStringKey] = ["Saving audio", "Uploading", "Transcribing", "Summarizing"]

    var body: some View {
        switch flow {
        case .preparingRecording, .finalizingAudio, .uploading, .transcribing, .summarizing:
            VStack(alignment: .leading, spacing: Hud.Space.x3) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, title in
                        stepRow(index: index, title: title)
                    }
                }
                if case .finalizingAudio = flow {
                    EmptyView()
                } else {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                }
            }

        case .completed:
            resultRow(glyph: .transcript, tint: Hud.Ink.text1, title: "Ready", detail: completedMeeting?.title) {
                if let completedMeeting {
                    Button("Open") { onOpenMeeting(completedMeeting) }
                        .buttonStyle(HudButtonStyle(kind: .primary))
                }
                Button("Done", action: onDone)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }

        case .failed(let failure):
            resultRow(glyph: .transcript, tint: Hud.Ink.live, title: LocalizedStringKey(failure.title), detail: failure.message) {
                if failure.category == .permission, failure.recoveryAction == .openSystemSettings {
                    Button("System Settings") { onRecover(failure) }
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                    Button("Relaunch", action: onRelaunch)
                        .buttonStyle(HudButtonStyle(kind: .primary))
                } else {
                    Button(failure.recoveryButtonTitle) { onRecover(failure) }
                        .buttonStyle(HudButtonStyle(kind: .primary))
                }
            }

        case .cancelled:
            resultRow(glyph: .stop, tint: Hud.Ink.text3, title: "Stopped", detail: nil) {
                Button("Done", action: onDone)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }

        case .idle, .upcomingMeeting, .recording:
            EmptyView()
        }
    }

    private var currentStep: Int {
        switch flow {
        case .preparingRecording, .finalizingAudio: 0
        case .uploading: 1
        case .transcribing: 2
        case .summarizing: 3
        default: 0
        }
    }

    private var uploadProgress: Double? {
        if case .uploading(let progress) = flow { return progress }
        return nil
    }

    private func stepRow(index: Int, title: LocalizedStringKey) -> some View {
        let isDone = index < currentStep
        let isCurrent = index == currentStep
        return HStack(spacing: Hud.Space.x3) {
            Text(title)
                .hud(.body, isCurrent ? Hud.Ink.text1 : (isDone ? Hud.Ink.text3 : Hud.Ink.text4))
                .frame(width: 130, alignment: .leading)
            if isCurrent {
                Group {
                    if let uploadProgress {
                        HudSegmentMeter(segments: 20, progress: uploadProgress, tint: Hud.Ink.text1)
                    } else {
                        HudSegmentMeter(segments: 20, progress: 1, tint: Hud.Ink.text2)
                            .modifier(HudBreathing())
                    }
                }
                .transition(.opacity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: 34)
        .animation(Hud.Motion.change, value: currentStep)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : (isCurrent ? "In progress" : "Waiting"))
    }

    private func resultRow<Actions: View>(
        glyph: HudGlyph,
        tint: Color,
        title: LocalizedStringKey,
        detail: String?,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: Hud.Space.x3) {
            HStack(alignment: .top, spacing: Hud.Space.x3) {
                HudIcon(glyph).foregroundStyle(tint).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).hud(.title)
                    if let detail, !detail.isEmpty {
                        Text(detail).hud(.meta, Hud.Ink.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Hud.Size.rowInset)
            HStack(spacing: Hud.Space.x1) {
                actions()
            }
            .padding(.leading, Hud.Size.rowInset + Hud.Size.icon + Hud.Space.x3 - 12)
        }
        .padding(.vertical, Hud.Space.x2)
    }
}

// MARK: - Prompts

/// A detected meeting or an ending one: one row on a faint surface, the answer on the
/// right. No separate window.
private struct MeetingLifecyclePromptView: View {
    let prompt: MeetingLifecyclePrompt
    let onStartRecording: () -> Void
    let onDismiss: () -> Void
    let onContinueRecording: () -> Void
    let onConfirmEnd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Hud.Space.x3) {
            HudIcon(glyph).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).hud(.body)
                Text(detail).hud(.meta, Hud.Ink.text3).lineLimit(1)
            }
            Spacer(minLength: Hud.Space.x2)

            if case .autoStop(_, _, let deadline) = prompt {
                AutoStopCountdownView(deadline: deadline)
            }

            switch prompt {
            case .recordingOffer:
                Button("Not now", action: onDismiss)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                Button(action: onStartRecording) {
                    HStack(spacing: 6) {
                        Circle().fill(Hud.Ink.live).frame(width: 7, height: 7)
                        Text("Record")
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .primary))
            case .endConfirmation, .autoStop:
                Button("Keep", action: onContinueRecording)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                Button("Stop", action: onConfirmEnd)
                    .buttonStyle(HudButtonStyle(kind: .primary))
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(minHeight: Hud.Size.row + 4)
        .background(RoundedRectangle(cornerRadius: Hud.Size.corner + 2, style: .continuous).fill(Hud.Ink.hover))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var title: String {
        switch prompt {
        case .recordingOffer(_, let clientID): clientName(clientID)
        case .endConfirmation: String(localized: "Meeting may have ended")
        case .autoStop: String(localized: "Meeting ended")
        }
    }

    private var detail: String {
        switch prompt {
        case .recordingOffer: String(localized: "Record this meeting?")
        case .endConfirmation: String(localized: "Stop the recording?")
        case .autoStop: String(localized: "Recording stops soon")
        }
    }

    private var glyph: HudGlyph {
        switch prompt {
        case .recordingOffer: .video
        case .endConfirmation, .autoStop: .stop
        }
    }

    private var tint: Color {
        switch prompt {
        case .recordingOffer: Hud.Ink.signal
        case .endConfirmation: Hud.Ink.text2
        case .autoStop: Hud.Ink.live
        }
    }

    private func clientName(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: String(localized: "Meeting detected")
        }
    }
}

private struct AutoStopCountdownView: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            Text("\(seconds) s")
                .hud(.value, Hud.Ink.live)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Recording stops in \(seconds) seconds")
        }
    }
}

private struct RecordingRecoveryNoticeView: View {
    let summary: RecordingRecoverySummary
    let onOpenRecovery: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Hud.Space.x3) {
            HudIcon(.history).foregroundStyle(summary.preservedCount > 0 ? Hud.Ink.signal : Hud.Ink.text2)
            VStack(alignment: .leading, spacing: 2) {
                if summary.recoveredCount > 0 {
                    Text("\(summary.recoveredCount) recordings recovered").hud(.body)
                }
                if summary.preservedCount > 0 {
                    Text("\(summary.preservedCount) kept in Recovery").hud(.meta, Hud.Ink.text3)
                }
            }
            Spacer(minLength: Hud.Space.x2)
            if summary.preservedCount > 0 {
                Button("Show", action: onOpenRecovery)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .help("Show Recovery folder")
            }
            Button(action: onDismiss) {
                HudIcon(.close, size: Hud.Size.smallIcon)
            }
            .buttonStyle(HudButtonStyle(kind: .icon))
            .accessibilityLabel("Dismiss recovery notice")
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(minHeight: Hud.Size.row)
        .background(RoundedRectangle(cornerRadius: Hud.Size.corner + 2, style: .continuous).fill(Hud.Ink.hover))
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
