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
    let onAddTask: (String) -> Void
    let onUpdateTask: (TaskItem, String) -> Void
    let onChangeTaskStatus: (TaskItem, TaskStatus) -> Void
    let onArchiveTask: (TaskItem) -> Void
    let onRestoreTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteArchive: () -> Void
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
        onAddTask: @escaping (String) -> Void = { _ in },
        onUpdateTask: @escaping (TaskItem, String) -> Void = { _, _ in },
        onChangeTaskStatus: @escaping (TaskItem, TaskStatus) -> Void = { _, _ in },
        onArchiveTask: @escaping (TaskItem) -> Void = { _ in },
        onRestoreTask: @escaping (TaskItem) -> Void = { _ in },
        onDeleteTask: @escaping (TaskItem) -> Void = { _ in },
        onDeleteArchive: @escaping () -> Void = {},
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
        self.onAddTask = onAddTask
        self.onUpdateTask = onUpdateTask
        self.onChangeTaskStatus = onChangeTaskStatus
        self.onArchiveTask = onArchiveTask
        self.onRestoreTask = onRestoreTask
        self.onDeleteTask = onDeleteTask
        self.onDeleteArchive = onDeleteArchive
        self.onRelaunchApplication = onRelaunchApplication
    }

    var body: some View {
        let showsDetail = appState.presentedMeetingDetail != nil
        let layout = NotchPanelLayout(
            availableSize: appState.notchPanelAvailableSize,
            preferredWidth: NotchPanelLayout.preferredWidth
        )
        let rootSpacing = showsDetail
            ? MeetingNotchTheme.sectionSpacing
            : MeetingNotchTheme.MainPanel.sectionSpacing
        let horizontalPadding = showsDetail
            ? MeetingNotchTheme.panelHorizontalPadding
            : MeetingNotchTheme.MainPanel.horizontalPadding
        let verticalPadding = showsDetail
            ? MeetingNotchTheme.panelVerticalPadding
            : MeetingNotchTheme.MainPanel.verticalPadding

        VStack(spacing: rootSpacing) {
            if let detail = appState.presentedMeetingDetail {
                MeetingDetailToolbar(
                    content: detail,
                    onBack: appState.dismissMeetingDetail,
                    onCopyText: onCopyText
                )
                .transition(panelContentTransition)
            } else {
                HStack(spacing: 0) {
                    NotchTabBar(selection: $appState.selectedTab)

                    Spacer(minLength: 20)

                    Button {
                        NotificationCenter.default.post(name: .openDesktopWorkspace, object: nil)
                    } label: {
                        Image(systemName: "macwindow").font(.system(size: 18))
                    }
                    .buttonStyle(FigmaHeaderIconButtonStyle(tint: MeetingNotchTheme.MainPanel.primaryText))
                    .help("Masaüstü çalışma alanını aç")
                    .accessibilityLabel("Masaüstü çalışma alanını aç")
                    .padding(.trailing, 8)

                    Button(action: onTogglePin) {
                        Image("FigmaPin")
                            .resizable()
                            .renderingMode(.template)
                            .frame(
                                width: MeetingNotchTheme.MainPanel.iconSize,
                                height: MeetingNotchTheme.MainPanel.iconSize
                            )
                    }
                    .buttonStyle(
                        FigmaHeaderIconButtonStyle(
                            tint: appState.isNotchPinned
                                ? MeetingNotchTheme.MainPanel.danger
                                : MeetingNotchTheme.MainPanel.primaryText
                        )
                    )
                    .help(appState.isNotchPinned ? "Paneli serbest bırak" : "Paneli açık tut")
                    .accessibilityLabel(appState.isNotchPinned ? "Panel sabitlemesini kaldır" : "Paneli açık tut")
                    .accessibilityValue(appState.isNotchPinned ? "Açık tutuluyor" : "Serbest")
                }
                .transition(panelContentTransition)
            }

            NotchPanelScrollableContent(
                maximumHeight: layout.maximumContentHeight,
                bottomContentInset: showsDetail ? MeetingNotchTheme.panelVerticalPadding : 0
            ) {
                ZStack {
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
                        .transition(panelContentTransition)
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
                            .transition(panelContentTransition)
                        case .tasks:
                            TasksView(
                                onAdd: onAddTask,
                                onUpdate: onUpdateTask,
                                onChangeStatus: onChangeTaskStatus,
                                onArchive: onArchiveTask,
                                onRestore: onRestoreTask,
                                onDelete: onDeleteTask,
                                onDeleteArchive: onDeleteArchive
                            )
                            .transition(panelContentTransition)
                        }
                    }
                }
                .id(appState.presentedMeetingDetail?.id.uuidString ?? appState.selectedTab.rawValue)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: layout.width)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: MeetingNotchTheme.MainPanel.panelRadius,
                bottomTrailingRadius: MeetingNotchTheme.MainPanel.panelRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(MeetingNotchTheme.MainPanel.panelBackground)
        }
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
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: appState.selectedTab
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: appState.presentedMeetingDetail?.id
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: layout.width
        )
    }

    private var panelContentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -5))
        )
    }
}

struct NotchPanelScrollableContent<Content: View>: View {
    let maximumHeight: CGFloat
    let bottomContentInset: CGFloat
    let content: Content

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
        }
        .frame(maxHeight: maximumHeight)
        .scrollIndicators(.hidden)
    }
}

private struct NotchTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppState.PanelTab
    @State private var hoveredTab: AppState.PanelTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppState.PanelTab.allCases) { tab in
                let isSelected = selection == tab
                let isHovered = hoveredTab == tab

                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 0) {
                        Image(tab.assetName)
                            .resizable()
                            .renderingMode(.template)
                            .frame(
                                width: MeetingNotchTheme.MainPanel.iconSize,
                                height: MeetingNotchTheme.MainPanel.iconSize
                            )
                        Text(tab.rawValue)
                            .font(MeetingNotchTheme.MainPanel.tabFont)
                            .padding(.horizontal, 4)
                    }
                    .foregroundStyle(
                        isSelected
                            ? MeetingNotchTheme.MainPanel.primaryText
                            : tabForeground(isHovered: isHovered)
                    )
                    .padding(.horizontal, 8)
                    .frame(height: MeetingNotchTheme.MainPanel.tabHeight)
                    .contentShape(Rectangle().inset(by: -4))
                    .background {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: MeetingNotchTheme.MainPanel.capsuleRadius,
                                style: .continuous
                            )
                                .fill(MeetingNotchTheme.MainPanel.surface)
                        } else if isHovered {
                            RoundedRectangle(
                                cornerRadius: MeetingNotchTheme.MainPanel.capsuleRadius,
                                style: .continuous
                            )
                            .fill(MeetingNotchTheme.MainPanel.surface.opacity(0.72))
                        }
                    }
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.16),
                        value: isSelected
                    )
                }
                .buttonStyle(NotchTabButtonStyle())
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        hoveredTab = hovering ? tab : nil
                    }
                }
                .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                .help(
                    "\(tab.rawValue) sekmesi (\(NotchAccessibilityContract.tabShortcutDescription(tab)))"
                )
                .accessibilityLabel(NotchAccessibilityContract.tabLabel(tab))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel sekmeleri")
    }

    private func tabForeground(isHovered: Bool) -> Color {
        isHovered
            ? MeetingNotchTheme.MainPanel.primaryText
            : MeetingNotchTheme.MainPanel.inactiveTabText
    }
}

private extension AppState.PanelTab {
    var assetName: String {
        switch self {
        case .meetings: "FigmaVoice"
        case .tasks: "FigmaTasks"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .meetings: "1"
        case .tasks: "2"
        }
    }

    var shortcutDescription: String {
        switch self {
        case .meetings: "1"
        case .tasks: "2"
        }
    }
}

private struct FigmaHeaderIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .frame(width: 36, height: MeetingNotchTheme.MainPanel.tabHeight)
            .background(
                MeetingNotchTheme.MainPanel.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.MainPanel.capsuleRadius,
                    style: .continuous
                )
            )
            .contentShape(Rectangle().inset(by: -4))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct FigmaCompactActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.MainPanel.smallFont)
            .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(
                MeetingNotchTheme.MainPanel.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.MainPanel.compactRadius,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct FigmaPrimaryPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.MainPanel.rowTitleFont)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 8)
            .frame(height: MeetingNotchTheme.MainPanel.tabHeight)
            .background(
                MeetingNotchTheme.MainPanel.primaryText,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.MainPanel.capsuleRadius,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct FigmaStopButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.MainPanel.rowTitleFont.monospacedDigit())
            .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
            .padding(.horizontal, 8)
            .frame(height: MeetingNotchTheme.MainPanel.tabHeight)
            .background(
                MeetingNotchTheme.MainPanel.danger,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.MainPanel.capsuleRadius,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct FigmaGateButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
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

        LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.MainPanel.sectionSpacing) {
            VStack(alignment: .leading, spacing: MeetingNotchTheme.MainPanel.contentSpacing) {
                todayHeader
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
                RecentMeetingsView(
                    meetings: Array(appState.storedMeetings.prefix(7)),
                    onOpen: onOpenStoredMeeting,
                    onDelete: onDeleteStoredMeeting,
                    onRetry: onRetryStoredMeeting
                )
            }
        }
        .alert(cancelConfirmationTitle, isPresented: $showsCancelConfirmation) {
            Button("Vazgeç", role: .cancel) {}
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
        var meetings = Array(appState.upcomingMeetings.prefix(3))
        if let nextMeeting = appState.nextMeeting,
           !meetings.contains(where: { $0.id == nextMeeting.id }) {
            meetings.insert(nextMeeting, at: 0)
        }
        return Array(meetings.prefix(3))
    }

    private var todayHeader: some View {
        HStack(spacing: 8) {
            Text("Yaklaşan")
                .font(MeetingNotchTheme.MainPanel.sectionTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if showsMeetingLists, !scheduledMeetings.isEmpty {
                Button(action: onStartRecording) {
                    HStack(spacing: 0) {
                        Image("FigmaRecord")
                            .resizable()
                            .frame(
                                width: MeetingNotchTheme.MainPanel.smallIconSize,
                                height: MeetingNotchTheme.MainPanel.smallIconSize
                            )
                        Text("Kaydı başlat")
                            .padding(.horizontal, 2)
                    }
                }
                .buttonStyle(FigmaCompactActionButtonStyle())
                .accessibilityLabel("Kaydı başlat")
            }
        }
    }

    @ViewBuilder
    private func todayContent(presentation: MeetingFlowPresentation) -> some View {
        switch appState.meetingFlow {
        case .idle, .upcomingMeeting:
            if scheduledMeetings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    FigmaEmptyMeetingRow(
                        message: CalendarEmptyPresentation.message(enabled: appState.isCalendarEnabled,
                            access: appState.calendarAccessState, snapshot: appState.calendarIntegrationSnapshot),
                        onStartRecording: onStartRecording
                    )
                    HStack {
                        DesktopSettingsLink(category: .calendar) { Label("Takvim bağlantısı ve bildirimler", systemImage: "calendar.badge.plus") }
                        if appState.calendarAccessState == .notDetermined && appState.isCalendarEnabled {
                            Button("Takvime izin ver", action: onRequestCalendarAccess)
                        }
                    }
                    .font(MeetingNotchTheme.bodyFont)
                }
            } else {
                UpcomingMeetingsView(
                    meetings: scheduledMeetings,
                    onOpen: onOpenMeetingURL
                )
            }

            if appState.meetingSessionDetection?.session.clientID == .googleMeetChrome {
                FigmaWarningRow(
                    text: googleMeetBridgeStatusText,
                    isCritical: appState.browserAudioConnectionStatus == .unavailable
                )
                .accessibilityLabel("Google Meet ses bağlantısı: \(googleMeetBridgeStatusText)")
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image("FigmaRecord")
                            .resizable()
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kayıt devam ediyor…")
                                .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                                .lineLimit(1)
                            Text("Başlangıç: \(startedAt.formatted(date: .omitted, time: .shortened))")
                                .font(MeetingNotchTheme.MainPanel.bodyFont)
                                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: onStopRecording) {
                            HStack(spacing: 0) {
                                Image("FigmaStop")
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text("Durdur")
                                    .padding(.leading, 4)
                                Text("・")
                                RecordingElapsedTimeView(startedAt: startedAt)
                            }
                        }
                        .buttonStyle(FigmaStopButtonStyle())
                        .contextMenu {
                            Button("Kaydı sil", systemImage: "trash", role: .destructive) {
                                showsCancelConfirmation = true
                            }
                        }
                        .accessibilityLabel("Kaydı durdur")
                    }

                    CaptureSourcesView(status: appState.recordingCaptureStatus)
                }
                .padding(16)
                .background(
                    MeetingNotchTheme.MainPanel.surface,
                    in: RoundedRectangle(
                        cornerRadius: MeetingNotchTheme.MainPanel.surfaceRadius,
                        style: .continuous
                    )
                )

                if let gate = appState.meetingMicrophoneGate {
                    MeetingMicrophoneGateControl(
                        gate: gate,
                        onToggle: onToggleMeetingMicrophone
                    )
                }
            }
            .background(
                MeetingNotchTheme.MainPanel.warningSurface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.MainPanel.surfaceRadius,
                    style: .continuous
                )
            )

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
                    .accessibilityLabel("İşlem ilerlemesi")
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
            "Google Meet ses köprüsü kullanılamıyor; kayıt başlamaz."
        case .waitingForMeetTab:
            "Görüşme sekmesinde MeetingNotch Chrome uzantısına basın."
        case .tabConnected:
            "Google Meet sekmesi güvenli biçimde bağlı."
        case .recording:
            "Google Meet sekme sesi kayıt hattına bağlı."
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
            "Mikrofon durumu doğrulanamıyor. Ortam sesi güvenli olarak kayda kapatıldı."
        case .processChanged:
            "Toplantı süreci değişti. Yeni süreç doğrulanana kadar mikrofon kayda kapatıldı."
        case .systemInterruption:
            "Mac uykuya geçiyor. Mikrofon güvenli kapatıldı ve kayıt sonlandırılıyor."
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
                .accessibilityLabel("İşleme devam ediyor")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch appState.meetingFlow {
        case .idle:
            HStack(spacing: 8) {
                if appState.calendarAccessState != .authorized {
                    Button {
                        onRequestCalendarAccess()
                    } label: {
                        FigmaActionLabel(calendarButtonTitle, assetName: "FigmaRecentCheck")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                    .disabled(appState.calendarAccessState == .requesting)
                }

                if let url = appState.nextMeeting?.meetingURL {
                    Button {
                        onOpenMeetingURL(url)
                    } label: {
                        FigmaActionLabel("Katıl", assetName: "FigmaVideo")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                }

                Button {
                    onStartRecording()
                } label: {
                    FigmaActionLabel("Kaydı Başlat", assetName: "FigmaRecord")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .primary))
            }

        case .upcomingMeeting(let meeting):
            HStack(spacing: 8) {
                if let url = meeting.meetingURL {
                    Button {
                        onOpenMeetingURL(url)
                    } label: {
                        FigmaActionLabel("Katıl", assetName: "FigmaVideo")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                }
                Button {
                    onStartRecording()
                } label: {
                    FigmaActionLabel("Kaydı Başlat", assetName: "FigmaRecord")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .primary))
                Button {
                    appState.dismissCurrentMeetingReminder()
                } label: {
                    Text("Geç")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .secondary))
            }

        case .preparingRecording, .uploading, .transcribing, .summarizing:
            Button(role: .destructive) {
                showsCancelConfirmation = true
            } label: {
                FigmaActionLabel("İptal", assetName: "FigmaStop")
            }
            .buttonStyle(NotchActionButtonStyle(tone: .danger))

        case .finalizingAudio:
            EmptyView()

        case .recording:
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    showsCancelConfirmation = true
                } label: {
                    FigmaActionLabel("Kaydı Sil", assetName: "FigmaArchive")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .secondary))

                Button(role: .destructive) {
                    onStopRecording()
                } label: {
                    FigmaActionLabel("Kaydı Durdur", assetName: "FigmaStop")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .danger))
            }

        case .failed(let failure):
            if failure.category == .permission,
               failure.recoveryAction == .openSystemSettings {
                HStack(spacing: 8) {
                    Button {
                        onRecoverFromFailure(failure)
                    } label: {
                        FigmaActionLabel("Sistem Ayarları", assetName: "FigmaWarning")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))

                    Button(action: onRelaunchApplication) {
                        FigmaActionLabel("Yeniden Başlat", assetName: "FigmaVoice")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .primary))
                }
            } else {
                Button {
                    onRecoverFromFailure(failure)
                } label: {
                    FigmaActionLabel(failure.recoveryButtonTitle, assetName: "FigmaWarning")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .primary))
            }

        case .completed:
            HStack(spacing: 8) {
                if let meeting = appState.completedMeeting {
                    Button {
                        onOpenStoredMeeting(meeting)
                    } label: {
                        FigmaActionLabel("Detayı Aç", assetName: "FigmaTasks")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                }
                Button("Tamam") {
                    appState.resetFlow()
                }
                .buttonStyle(NotchActionButtonStyle(tone: .primary))
            }

        case .cancelled:
            Button("Tamam") {
                appState.resetFlow()
            }
            .buttonStyle(NotchActionButtonStyle(tone: .primary))

        }
    }

    private var calendarButtonTitle: String {
        switch appState.calendarAccessState {
        case .requesting:
            "Takvim Bekleniyor…"
        case .denied, .restricted:
            "Takvim İzni"
        case .failed:
            "Tekrar Bağlan"
        default:
            "Takvimi Bağla"
        }
    }

    private var cancelConfirmationTitle: String {
        switch appState.meetingFlow.phase {
        case .recording:
            "Kayıt silinsin mi?"
        case .uploading, .transcribing, .summarizing:
            "İşleme durdurulsun mu?"
        default:
            "Kayıt hazırlığı iptal edilsin mi?"
        }
    }

    private var cancelConfirmationButtonTitle: String {
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            "İşlemeyi Durdur"
        default:
            "Kaydı Sil"
        }
    }

    private var cancelConfirmationMessage: String {
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            "Yerel ses kaydı korunur. Transkripsiyonu toplantı geçmişinden daha sonra tekrar deneyebilirsiniz."
        case .recording:
            "Bu kayıt henüz geçmişe kaydedilmedi. Mikrofon ve sistem sesi parçaları kalıcı olarak silinecek."
        default:
            "Hazırlanan geçici kayıt dosyaları silinecek."
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
                HStack(spacing: 8) {
                    Button("Şimdi Değil", action: onDismiss)
                        .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                    Button(action: onStartRecording) {
                        FigmaActionLabel("Kaydı Başlat", assetName: "FigmaRecord")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .primary))
                }
            case .endConfirmation, .autoStop:
                HStack(spacing: 8) {
                    Button("Kayda Devam Et", action: onContinueRecording)
                        .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                    Button(role: .destructive, action: onConfirmEnd) {
                        FigmaActionLabel("Şimdi Durdur", assetName: "FigmaStop")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .danger))
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
            "Toplantı algılandı"
        case .endConfirmation:
            "Toplantı bitmiş olabilir"
        case .autoStop:
            "Toplantı bitti"
        }
    }

    private var detail: String {
        switch prompt {
        case .recordingOffer(_, let clientID):
            "\(clientName(clientID)) için kayıt başlatılsın mı?"
        case .endConfirmation:
            "Sinyaller kesin değil. Kaydı siz durdurabilirsiniz."
        case .autoStop:
            "Kayıt geri sayım sonunda güvenli biçimde durdurulacak."
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
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: "Toplantı"
        }
    }
}

private struct AutoStopCountdownView: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            Text("\(seconds) sn")
                .font(MeetingNotchTheme.dataFont.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.MainPanel.danger)
                .accessibilityLabel("Kaydın durmasına \(seconds) saniye")
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

private struct NotchActionButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case danger
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.controlFont)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: MeetingNotchTheme.controlHeight)
            .padding(.horizontal, 8)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
                    .fill(backgroundColor)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary: .black
        case .secondary: MeetingNotchTheme.MainPanel.primaryText
        case .danger: MeetingNotchTheme.MainPanel.danger
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .primary: MeetingNotchTheme.MainPanel.primaryText
        case .secondary: MeetingNotchTheme.MainPanel.meterTrack
        case .danger: MeetingNotchTheme.MainPanel.danger.opacity(0.12)
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
                    Text("\(summary.recoveredCount) kayıt kurtarıldı")
                }
                if summary.preservedCount > 0 {
                    Text("\(summary.preservedCount) kayıt Recovery'de korundu")
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
                .help("Recovery klasörünü göster")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(MeetingNotchIconButtonStyle())
            .accessibilityLabel("Kurtarma bildirimini kapat")
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

private struct FigmaEmptyMeetingRow: View {
    var message = "Yaklaşan çevrim içi toplantı yok"
    let onStartRecording: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(message)
                .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onStartRecording) {
                HStack(spacing: 0) {
                    Image("FigmaRecord")
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Kaydı başlat")
                        .padding(.leading, 4)
                }
            }
            .buttonStyle(FigmaPrimaryPillButtonStyle())
            .accessibilityLabel("Kaydı başlat")
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            MeetingNotchTheme.MainPanel.surface,
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
        .accessibilityHint(isCritical ? "Kritik uyarı" : "Uyarı")
    }
}

private struct FigmaMeetingCountdownView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let seconds = Int(startDate.timeIntervalSince(context.date))
            Text(Self.text(seconds: seconds))
                .font(MeetingNotchTheme.MainPanel.bodyFont.monospacedDigit())
                .foregroundStyle(
                    seconds <= 600
                        ? MeetingNotchTheme.MainPanel.danger
                        : MeetingNotchTheme.MainPanel.secondaryText
                )
                .lineLimit(1)
                .accessibilityLabel("Toplantıya kalan süre \(Self.text(seconds: seconds))")
        }
    }

    private static func text(seconds: Int) -> String {
        guard seconds > 0 else { return "Başladı" }
        let minutes = Int(ceil(Double(seconds) / 60))
        guard minutes >= 60 else { return "\(minutes) dk kaldı" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? "\(hours) sa kaldı"
            : "\(hours) sa \(remainingMinutes) dk"
    }
}

private struct UpcomingMeetingsView: View {
    let meetings: [Meeting]
    let onOpen: (URL) -> Void

    var body: some View {
        LazyVStack(spacing: MeetingNotchTheme.MainPanel.rowSpacing) {
            ForEach(meetings) { meeting in
                HStack(alignment: .top, spacing: MeetingNotchTheme.MainPanel.itemSpacing) {
                    Button {
                        if let url = meeting.meetingURL {
                            onOpen(url)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: MeetingNotchTheme.MainPanel.itemSpacing) {
                            Image("FigmaVideo")
                                .resizable()
                                .frame(width: 20, height: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title)
                                    .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                                    .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                                    .lineLimit(1)
                                Text(meeting.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(MeetingNotchTheme.MainPanel.bodyFont.monospacedDigit())
                                    .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchRowButtonStyle())
                    .disabled(meeting.meetingURL == nil)
                    .accessibilityLabel("\(meeting.title), \(meeting.startDate.formatted(date: .abbreviated, time: .shortened)), toplantıya katıl")

                    FigmaMeetingCountdownView(startDate: meeting.startDate)

                    Menu {
                        if let url = meeting.meetingURL {
                            Button("Toplantıya katıl", systemImage: "video.fill") {
                                onOpen(url)
                            }
                        }
                    } label: {
                        Image("FigmaMore")
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20, height: 20)
                    .disabled(meeting.meetingURL == nil)
                    .accessibilityLabel("Toplantı seçenekleri")
                }
                .padding(.vertical, 8)
                .frame(
                    maxWidth: .infinity,
                    minHeight: MeetingNotchTheme.MainPanel.rowHeight,
                    alignment: .top
                )
            }
        }
    }
}

private struct RecentMeetingsView: View {
    let meetings: [StoredMeeting]
    let onOpen: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void
    let onRetry: (StoredMeeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.MainPanel.contentSpacing) {
            Text("Son")
                .font(MeetingNotchTheme.MainPanel.sectionTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)

            if meetings.isEmpty {
                HStack(spacing: 10) {
                    Image("FigmaRecentCheck")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .opacity(0.38)

                    Text("İlk kaydınız tamamlandığında burada görünecek.")
                        .font(MeetingNotchTheme.MainPanel.bodyFont)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: MeetingNotchTheme.MainPanel.rowHeight)
            } else {
                LazyVStack(spacing: MeetingNotchTheme.MainPanel.rowSpacing) {
                    ForEach(meetings) { meeting in
                        RecentMeetingRow(
                            meeting: meeting,
                            detail: detail(for: meeting),
                            duration: duration(for: meeting),
                            statusSymbol: meeting.summaryNeedsAttention == true ? "FigmaWarning" : statusSymbol(for: meeting.processingStatus),
                            statusText: meeting.summaryNeedsAttention == true ? "Transkript hazır, özet bekliyor" : statusText(for: meeting.processingStatus),
                            onOpen: { onOpen(meeting) },
                            onRetry: meeting.processingStatus == .failed
                                ? { onRetry(meeting) }
                                : nil,
                            onDelete: { onDelete(meeting) }
                        )
                    }
                }
            }
        }
    }

    private func detail(for meeting: StoredMeeting) -> String {
        let date = meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
        return meeting.summaryNeedsAttention == true ? "Özet bekliyor · \(date)" : date
    }

    private func duration(for meeting: StoredMeeting) -> String {
        let duration = Int(meeting.duration)
        let hours = duration / 3_600
        let minutes = (duration % 3_600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func statusSymbol(for status: StoredMeeting.ProcessingStatus) -> String {
        switch status {
        case .recorded: "FigmaVideo"
        case .processing: "FigmaRecord"
        case .completed: "FigmaRecentCheck"
        case .failed: "FigmaWarning"
        }
    }

    private func statusText(for status: StoredMeeting.ProcessingStatus) -> String {
        switch status {
        case .recorded: "Kayıt hazır"
        case .processing: "İşleniyor"
        case .completed: "Tamamlandı"
        case .failed: "Hata"
        }
    }
}

private struct RecentMeetingRow: View {
    let meeting: StoredMeeting
    let detail: String
    let duration: String
    let statusSymbol: String
    let statusText: String
    let onOpen: () -> Void
    let onRetry: (() -> Void)?
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: MeetingNotchTheme.MainPanel.itemSpacing) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: MeetingNotchTheme.MainPanel.itemSpacing) {
                    Image(statusSymbol)
                        .resizable()
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                            .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                            .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                            .lineLimit(1)

                        Text(detail)
                            .font(MeetingNotchTheme.MainPanel.bodyFont.monospacedDigit())
                            .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchRowButtonStyle())
            .accessibilityLabel("\(meeting.title), \(statusText), \(detail), \(duration)")

            Text(duration)
                .font(MeetingNotchTheme.MainPanel.bodyFont.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                .lineLimit(1)

            Menu {
                Button("Toplantıyı aç", systemImage: "doc.text.magnifyingglass", action: onOpen)
                if let onRetry {
                    Button("İşlemeyi tekrar dene", systemImage: "arrow.clockwise", action: onRetry)
                }
                Divider()
                Button("Toplantıyı sil", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image("FigmaMore")
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 20)
            .accessibilityLabel("Toplantı seçenekleri")
        }
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            minHeight: MeetingNotchTheme.MainPanel.rowHeight,
            alignment: .top
        )
        .padding(.horizontal, MeetingNotchTheme.MainPanel.listRowHorizontalInset)
        .background(
            isHovering ? MeetingNotchTheme.MainPanel.surface : .clear,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.MainPanel.compactRadius,
                style: .continuous
            )
        )
        .onHover { isHovering = $0 }
    }
}

private struct CaptureSourcesView: View {
    let status: RecordingCaptureStatus

    var body: some View {
        HStack(spacing: 40) {
            source("Mikrofon", assetName: "FigmaMicrophone", status: status.microphone)
            source("Sistem", assetName: "FigmaVolume", status: status.systemAudio)
        }
    }

    private func source(_ title: String, assetName: String, status: AudioSourceStatus) -> some View {
        HStack(spacing: 8) {
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(sourceColor(status.connectionState))
                .frame(width: 16, height: 16)
            Text(title)
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MeetingNotchTheme.MainPanel.meterTrack)
                    Capsule()
                        .fill(sourceColor(status.connectionState))
                        .frame(
                            width: proxy.size.width
                                * CGFloat(min(max(status.level, 0), 1))
                        )
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 16)
        .accessibilityElement(children: .combine)
        .help(status.connectionState.message ?? (status.isReady ? "Hazır" : "Hazırlanıyor"))
        .accessibilityLabel(accessibilityLabel(title: title, status: status))
    }

    private func sourceColor(_ state: AudioSourceConnectionState) -> Color {
        switch state {
        case .ready:
            MeetingNotchTheme.MainPanel.secondaryText
        case .preparing, .recovered, .pipelineRecovered:
            MeetingNotchTheme.MainPanel.warning
        case .disconnected, .pipelineStalled:
            MeetingNotchTheme.MainPanel.danger
        }
    }

    private func accessibilityLabel(title: String, status: AudioSourceStatus) -> String {
        if let message = status.connectionState.message {
            return "\(title): \(message)"
        }
        return "\(title) \(status.isReady ? "hazır" : "hazırlanıyor")"
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
                    .renderingMode(gate.permitsAudio ? .template : .original)
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Toplantı mikrofonu: \(title)")
                        .font(MeetingNotchTheme.MainPanel.smallMediumFont)
                        .foregroundStyle(color)
                    Text("Manuel değiştir: ⌥⌘M")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.warning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        }
        .buttonStyle(FigmaGateButtonStyle())
        .help("Mikrofon kaydını aç veya gizlilik için kapat (⌥⌘M)")
        .accessibilityLabel("Toplantı mikrofonu \(title). Değiştirmek için Option Command M.")
    }

    private var title: String {
        switch gate.state {
        case .open: "Açık"
        case .closed: "Kapalı"
        case .unknown: "Bilinmiyor"
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

struct CompactLeadingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let presentation = MeetingFlowPresentation(
            state: appState.meetingFlow,
            nextMeeting: appState.nextMeeting,
            reminderLevel: appState.meetingReminderLevel
        )
        let status = NotchStatusResolver.compactStatus(
            flow: appState.meetingFlow,
            nextMeeting: appState.nextMeeting,
            activeTaskCount: appState.activeTaskCount,
            meetingDetection: appState.meetingSessionDetection,
            microphoneGate: appState.meetingMicrophoneGate
        )

        Group {
            switch status {
            case .recording(let recording):
                HStack(spacing: 4) {
                    Circle()
                        .fill(MeetingNotchTheme.MainPanel.danger)
                        .frame(width: 5, height: 5)
                    Image("FigmaVideo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                .foregroundStyle(MeetingNotchTheme.MainPanel.danger)
                .frame(minWidth: 22, minHeight: 18)
                .accessibilityLabel(
                    NotchAccessibilityContract.recordingSessionLabel(
                        clientID: recording.clientID
                    )
                )
            default:
                Image(presentation.compactAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(presentation.color)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel(presentation.title)
            }
        }
        .meetingNotchPanelAppearance(
            hasPhysicalNotch: appState.notchPanelHasPhysicalNotch
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
                .accessibilityLabel("Toplantıya kalan süre \(Self.text(seconds: seconds))")
        }
    }

    private static func text(seconds: Int) -> String {
        guard seconds > 0 else { return "Toplantı başladı" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct CompactTrailingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let status = NotchStatusResolver.compactStatus(
            flow: appState.meetingFlow,
            nextMeeting: appState.nextMeeting,
            activeTaskCount: appState.activeTaskCount,
            meetingDetection: appState.meetingSessionDetection,
            microphoneGate: appState.meetingMicrophoneGate
        )

        Group {
            switch status {
            case .recording(let recording):
                HStack(spacing: 5) {
                    Image(
                        recording.microphoneState == .open
                            ? "FigmaMicrophone"
                            : "FigmaMicrophoneOff"
                    )
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(gateColor(recording.microphoneState))
                        .accessibilityLabel(
                            NotchAccessibilityContract.microphoneGateLabel(
                                recording.microphoneState
                            )
                        )
                    RecordingElapsedTimeView(startedAt: recording.startedAt, compact: true)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.danger)
                }
                .accessibilityElement(children: .contain)
            case .processing(let stage):
                switch stage {
                case .uploading(let progress):
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                        .accessibilityLabel("Yükleme ilerlemesi")
                default:
                    HStack(spacing: 4) {
                        Image("FigmaVoice")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                        Text(stage.shortTitle)
                    }
                        .font(MeetingNotchTheme.metadataFont)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.cyan)
                }
            case .completed:
                Image("FigmaRecentCheck")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.success)
                    .accessibilityLabel("İşlem tamamlandı")
            case .failed:
                Image("FigmaWarning")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.danger)
                    .accessibilityLabel("İşlem hatası")
            case .upcoming(let startDate):
                CompactMeetingCountdownView(startDate: startDate)
            case .tasks(let count):
                HStack(spacing: 4) {
                    Image("FigmaTasks")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("\(count)")
                }
                    .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                    .foregroundStyle(MeetingNotchTheme.MainPanel.success)
                    .accessibilityLabel("\(count) aktif görev")
            case .idle:
                Text("HAZIR")
                    .font(MeetingNotchTheme.metadataFont)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
            }
        }
        .meetingNotchPanelAppearance(
            hasPhysicalNotch: appState.notchPanelHasPhysicalNotch
        )
    }

    private func gateColor(_ state: MeetingMicrophoneState) -> Color {
        switch state {
        case .open: MeetingNotchTheme.MainPanel.success
        case .closed: MeetingNotchTheme.MainPanel.secondaryText
        case .unknown: MeetingNotchTheme.MainPanel.warning
        }
    }

}

private extension NotchCompactStatus.ProcessingStage {
    var shortTitle: String {
        switch self {
        case .preparing: "Hazırlanıyor"
        case .finalizing: "Kaydediliyor"
        case .uploading: "Yükleniyor"
        case .transcribing: "Yazıya çevriliyor"
        case .summarizing: "Özetleniyor"
        }
    }
}

private struct CompactMeetingCountdownView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(startDate.timeIntervalSince(context.date)))
            Text(Self.text(seconds: seconds))
                .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                .foregroundStyle(
                    seconds > 60
                        ? MeetingNotchTheme.MainPanel.warning
                        : MeetingNotchTheme.MainPanel.danger
                )
        }
    }

    private static func text(seconds: Int) -> String {
        guard seconds > 0 else { return "Şimdi" }
        if seconds < 60 { return "<1 dk" }
        return "\(Int(ceil(Double(seconds) / 60))) dk"
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
            let title = nextMeeting?.title ?? "Yaklaşan toplantı yok"
            let detail = nextMeeting.map {
                "Sonraki toplantı: \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
            } ?? "Hazır olduğunuzda manuel kayıt başlatabilirsiniz."
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
                detail = "Başlamasına 1 dakikadan az kaldı"
            case .tenMinutes:
                detail = "Başlamasına 10 dakikadan az kaldı"
            case .started:
                detail = "Toplantı başladı"
            case .none:
                detail = meeting.startDate.formatted(date: .omitted, time: .shortened)
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
                title: "Kayıt hazırlanıyor",
                detail: "Ses kaynakları ve izinler kontrol ediliyor."
            )
        case .recording(let startedAt):
            self.init(
                assetName: "FigmaRecord",
                compactAssetName: "FigmaRecord",
                color: MeetingNotchTheme.MainPanel.danger,
                title: "Kayıt devam ediyor",
                detail: "Başlangıç: \(startedAt.formatted(date: .omitted, time: .standard))"
            )
        case .finalizingAudio:
            self.init(
                assetName: "FigmaStop",
                compactAssetName: "FigmaStop",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Ses hazırlanıyor",
                detail: "Kayıt güvenli biçimde sonlandırılıyor."
            )
        case .uploading(let progress):
            self.init(
                assetName: "FigmaArrowUp",
                compactAssetName: "FigmaArrowUp",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Kayıt yükleniyor",
                detail: "Transkripsiyon için ses dosyası gönderiliyor.",
                progress: progress
            )
        case .transcribing:
            self.init(
                assetName: "FigmaVoice",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Transkript hazırlanıyor",
                detail: "Konuşmacılar ve konuşmalar ayrıştırılıyor."
            )
        case .summarizing:
            self.init(
                assetName: "FigmaTasks",
                compactAssetName: "FigmaTasks",
                color: MeetingNotchTheme.MainPanel.cyan,
                title: "Özet hazırlanıyor",
                detail: "Kararlar ve aksiyon maddeleri çıkarılıyor."
            )
        case .completed:
            self.init(
                assetName: "FigmaRecentCheck",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.success,
                title: "Kayıt tamamlandı",
                detail: "Mikrofon ve sistem sesi yerel olarak kaydedildi."
            )
        case .cancelled:
            self.init(
                assetName: "FigmaStop",
                compactAssetName: "FigmaVoice",
                color: MeetingNotchTheme.MainPanel.secondaryText,
                title: "İşlem iptal edildi",
                detail: "Yeni bir kayıt başlatabilirsiniz."
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
                    transaction.disablesAnimations = true
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
