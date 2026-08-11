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
    let onCompleteTask: (TaskItem) -> Void
    let onRestoreTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteArchive: () -> Void
    let onRelaunchApplication: () -> Void

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
        onCompleteTask: @escaping (TaskItem) -> Void = { _ in },
        onRestoreTask: @escaping (TaskItem) -> Void = { _ in },
        onDeleteTask: @escaping (TaskItem) -> Void = { _ in },
        onDeleteArchive: @escaping () -> Void = {},
        onRelaunchApplication: @escaping () -> Void = {}
    ) {
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
        self.onCompleteTask = onCompleteTask
        self.onRestoreTask = onRestoreTask
        self.onDeleteTask = onDeleteTask
        self.onDeleteArchive = onDeleteArchive
        self.onRelaunchApplication = onRelaunchApplication
    }

    var body: some View {
        let preferredWidth = appState.presentedMeetingDetail == nil
            ? NotchPanelLayout.preferredWidth
            : NotchPanelLayout.preferredDetailWidth
        let layout = NotchPanelLayout(
            availableSize: appState.notchPanelAvailableSize,
            preferredWidth: preferredWidth
        )

        VStack(spacing: MeetingNotchTheme.sectionSpacing) {
            if let detail = appState.presentedMeetingDetail {
                MeetingDetailToolbar(
                    content: detail,
                    onBack: appState.dismissMeetingDetail,
                    onCopyText: onCopyText
                )
                .transition(panelContentTransition)
            } else {
                HStack(spacing: 6) {
                    NotchTabBar(selection: $appState.selectedTab)

                    Button(action: onTogglePin) {
                        Image(systemName: appState.isNotchPinned ? "pin.fill" : "pin")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(
                        MeetingNotchIconButtonStyle(
                            tint: appState.isNotchPinned ? MeetingNotchTheme.accent : .secondary,
                            isActive: appState.isNotchPinned
                        )
                    )
                    .help(appState.isNotchPinned ? "Paneli serbest bırak" : "Paneli açık tut")
                    .accessibilityLabel(appState.isNotchPinned ? "Panel sabitlemesini kaldır" : "Paneli açık tut")
                    .accessibilityValue(appState.isNotchPinned ? "Açık tutuluyor" : "Serbest")
                }
                .transition(panelContentTransition)
            }

            ScrollView {
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
                            onDelete: onDeleteStoredMeeting
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
                                onComplete: onCompleteTask,
                                onRestore: onRestoreTask,
                                onDelete: onDeleteTask,
                                onDeleteArchive: onDeleteArchive
                            )
                            .transition(panelContentTransition)
                        }
                    }
                }
                .id(appState.presentedMeetingDetail?.id.uuidString ?? appState.selectedTab.rawValue)
                .frame(
                    maxWidth: .infinity,
                    minHeight: min(NotchPanelLayout.minimumContentHeight, layout.maximumContentHeight),
                    alignment: .top
                )
            }
            .frame(maxHeight: layout.maximumContentHeight)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, MeetingNotchTheme.panelHorizontalPadding)
        .padding(.vertical, MeetingNotchTheme.panelVerticalPadding)
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

private struct NotchTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppState.PanelTab
    @State private var hoveredTab: AppState.PanelTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppState.PanelTab.allCases) { tab in
                let isSelected = selection == tab
                let isHovered = hoveredTab == tab

                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                isSelected
                                    ? MeetingNotchTheme.accent
                                    : tabForeground(isHovered: isHovered)
                            )
                        Text(tab.rawValue)
                            .font(MeetingNotchTheme.controlFont)
                            .foregroundStyle(
                                isSelected
                                    ? MeetingNotchTheme.activeTabForeground
                                    : tabForeground(isHovered: isHovered)
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: MeetingNotchTheme.tabHeight)
                    .contentShape(Rectangle())
                    .background {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: MeetingNotchTheme.controlRadius,
                                style: .continuous
                            )
                                .fill(MeetingNotchTheme.activeTabFill)
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: MeetingNotchTheme.controlRadius,
                                        style: .continuous
                                    )
                                    .stroke(MeetingNotchTheme.hairline, lineWidth: 1)
                                }
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(MeetingNotchTheme.accent)
                                        .frame(width: 28, height: 2)
                                        .padding(.bottom, 2)
                                }
                        } else if isHovered {
                            RoundedRectangle(
                                cornerRadius: MeetingNotchTheme.controlRadius,
                                style: .continuous
                            )
                            .fill(MeetingNotchTheme.surfaceHover)
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
        .padding(MeetingNotchTheme.tabBarPadding)
        .background(
            MeetingNotchTheme.tabTrackFill,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
                .stroke(MeetingNotchTheme.subtleHairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel sekmeleri")
    }

    private func tabForeground(isHovered: Bool) -> Color {
        isHovered
            ? MeetingNotchTheme.inactiveTabHoverForeground
            : MeetingNotchTheme.inactiveTabForeground
    }
}

private extension AppState.PanelTab {
    var symbol: String {
        switch self {
        case .meetings: "calendar.day.timeline.leading"
        case .tasks: "checkmark.circle"
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

        VStack(spacing: MeetingNotchTheme.sectionSpacing) {
            VStack(alignment: .leading, spacing: MeetingNotchTheme.contentSpacing) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: presentation.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(presentation.color)
                        .frame(width: 20, height: 24)
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .font(MeetingNotchTheme.titleFont)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(presentation.detail)
                            .font(MeetingNotchTheme.bodyFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    statusMetric
                }

                if let progress = presentation.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(presentation.color)
                        .accessibilityLabel("İşlem ilerlemesi")
                }

                if appState.meetingFlow.phase == .preparingRecording || appState.meetingFlow.isRecording {
                    CaptureSourcesView(status: appState.recordingCaptureStatus)
                    if appState.meetingFlow.isRecording,
                       let gate = appState.meetingMicrophoneGate {
                        MeetingMicrophoneGateControl(
                            gate: gate,
                            onToggle: onToggleMeetingMicrophone
                        )
                        if let warning = microphonePrivacyWarning(for: gate) {
                            Label(warning, systemImage: "exclamationmark.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Mikrofon gizlilik uyarısı: \(warning)")
                        }
                    }
                    if let message = appState.recordingCaptureStatus.microphone.connectionState.message {
                        Label(message, systemImage: microphoneNoticeSymbol)
                            .font(.caption)
                            .foregroundStyle(
                                appState.recordingCaptureStatus.microphone.isReady ? .orange : .red
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Mikrofon uyarısı: \(message)")
                    }
                    if let message = appState.recordingCaptureStatus.systemAudio.connectionState.message {
                        Label(message, systemImage: "speaker.slash.fill")
                            .font(.caption)
                            .foregroundStyle(
                                appState.recordingCaptureStatus.systemAudio.isReady ? .orange : .red
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Sistem sesi uyarısı: \(message)")
                    }
                }

                if let message = appState.recordingSafetyMessage {
                    Label(message, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Kayıt güvenliği uyarısı: \(message)")
                }

                if appState.meetingSessionDetection?.session.clientID == .googleMeetChrome,
                   !appState.meetingFlow.isRecording {
                    Label(
                        googleMeetBridgeStatusText,
                        systemImage: googleMeetBridgeStatusSymbol
                    )
                    .font(.caption)
                    .foregroundStyle(
                        appState.browserAudioConnectionStatus == .tabConnected ? .green : .orange
                    )
                    .fixedSize(horizontal: false, vertical: true)
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
                } else {
                    actionArea
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.surfaceRadius,
                    style: .continuous
                )
                    .fill(MeetingNotchTheme.surface)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.surfaceRadius,
                    style: .continuous
                )
                    .stroke(MeetingNotchTheme.hairline, lineWidth: 1)
            }
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.24),
                value: appState.meetingFlow.phase
            )

            if case .idle = appState.meetingFlow {
                if let recoverySummary = appState.recordingRecoverySummary {
                    RecordingRecoveryNoticeView(
                        summary: recoverySummary,
                        onOpenRecovery: onOpenRecovery,
                        onDismiss: appState.dismissRecordingRecoverySummary
                    )
                }
                RecentMeetingsView(
                    meetings: Array(appState.storedMeetings.prefix(3)),
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
                    .fill(.red)
                    .frame(width: 5, height: 5)
                RecordingElapsedTimeView(startedAt: startedAt)
            }
            .font(MeetingNotchTheme.dataFont.monospacedDigit())
            .foregroundStyle(.red)
        case .upcomingMeeting(let meeting):
            MeetingCountdownView(startDate: meeting.startDate)
        case .uploading(let progress):
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(MeetingNotchTheme.dataFont.monospacedDigit())
                .foregroundStyle(.blue)
        case .preparingRecording, .finalizingAudio, .transcribing, .summarizing:
            ProgressView()
                .controlSize(.mini)
                .tint(.blue)
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
                        Label(calendarButtonTitle, systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                    .disabled(appState.calendarAccessState == .requesting)
                }

                if let url = appState.nextMeeting?.meetingURL {
                    Button {
                        onOpenMeetingURL(url)
                    } label: {
                        Label("Katıl", systemImage: "video.fill")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                }

                Button {
                    onStartRecording()
                } label: {
                    Label("Kaydı Başlat", systemImage: "record.circle")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .primary))
            }

        case .upcomingMeeting(let meeting):
            HStack(spacing: 8) {
                if let url = meeting.meetingURL {
                    Button {
                        onOpenMeetingURL(url)
                    } label: {
                        Label("Katıl", systemImage: "video.fill")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                }
                Button {
                    onStartRecording()
                } label: {
                    Label("Kaydı Başlat", systemImage: "record.circle")
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
                Label("İptal", systemImage: "xmark")
            }
            .buttonStyle(NotchActionButtonStyle(tone: .danger))

        case .finalizingAudio:
            EmptyView()

        case .recording:
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    showsCancelConfirmation = true
                } label: {
                    Label("Kaydı Sil", systemImage: "trash")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .secondary))

                Button(role: .destructive) {
                    onStopRecording()
                } label: {
                    Label("Kaydı Durdur", systemImage: "stop.fill")
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
                        Label("Sistem Ayarları", systemImage: "gearshape")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .secondary))

                    Button(action: onRelaunchApplication) {
                        Label("Yeniden Başlat", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .primary))
                }
            } else {
                Button {
                    onRecoverFromFailure(failure)
                } label: {
                    Label(failure.recoveryButtonTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(NotchActionButtonStyle(tone: .primary))
            }

        case .completed:
            HStack(spacing: 8) {
                if let meeting = appState.completedMeeting {
                    Button {
                        onOpenStoredMeeting(meeting)
                    } label: {
                        Label("Detayı Aç", systemImage: "doc.text.magnifyingglass")
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
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MeetingNotchTheme.controlFont)
                    Text(detail)
                        .font(MeetingNotchTheme.bodyFont)
                        .foregroundStyle(.secondary)
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
                        Label("Kaydı Başlat", systemImage: "record.circle")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .primary))
                }
            case .endConfirmation, .autoStop:
                HStack(spacing: 8) {
                    Button("Kayda Devam Et", action: onContinueRecording)
                        .buttonStyle(NotchActionButtonStyle(tone: .secondary))
                    Button(role: .destructive, action: onConfirmEnd) {
                        Label("Şimdi Durdur", systemImage: "stop.fill")
                    }
                    .buttonStyle(NotchActionButtonStyle(tone: .danger))
                }
            }
        }
        .padding(.top, 2)
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

    private var symbol: String {
        switch prompt {
        case .recordingOffer: "video.badge.checkmark"
        case .endConfirmation: "questionmark.circle"
        case .autoStop: "stopwatch"
        }
    }

    private var tint: Color {
        switch prompt {
        case .recordingOffer: MeetingNotchTheme.accent
        case .endConfirmation: .orange
        case .autoStop: .red
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
                .foregroundStyle(.red)
                .accessibilityLabel("Kaydın durmasına \(seconds) saniye")
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
            .overlay {
                RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
                    .stroke(strokeColor, lineWidth: 1)
            }
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
        case .secondary: .primary
        case .danger: .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .primary: MeetingNotchTheme.accent
        case .secondary: MeetingNotchTheme.elevatedSurface
        case .danger: Color.red.opacity(0.12)
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .primary: Color.primary.opacity(0.18)
        case .secondary: MeetingNotchTheme.subtleHairline
        case .danger: Color.red.opacity(0.18)
        }
    }
}

private struct RecordingRecoveryNoticeView: View {
    let summary: RecordingRecoverySummary
    let onOpenRecovery: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.preservedCount > 0 ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.arrow.triangle.2.circlepath")
                .foregroundStyle(summary.preservedCount > 0 ? .orange : .green)
                .frame(width: 34, height: 34)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                if summary.recoveredCount > 0 {
                    Text("\(summary.recoveredCount) kayıt kurtarıldı")
                }
                if summary.preservedCount > 0 {
                    Text("\(summary.preservedCount) kayıt Recovery'de korundu")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            if summary.preservedCount > 0 {
                Button(action: onOpenRecovery) {
                    Image(systemName: "folder")
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recovery klasörünü göster")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kurtarma bildirimini kapat")
        }
        .padding(10)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.orange.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct RecentMeetingsView: View {
    let meetings: [StoredMeeting]
    let onOpen: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void
    let onRetry: (StoredMeeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Son toplantılar")
                    .font(MeetingNotchTheme.sectionTitleFont)
                    .foregroundStyle(.secondary)

                Spacer()

                if !meetings.isEmpty {
                    Text("\(meetings.count)")
                        .font(MeetingNotchTheme.dataFont.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 2)

            if meetings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Text("İlk kaydınız tamamlandığında burada görünecek.")
                        .font(MeetingNotchTheme.bodyFont)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 38)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        RecentMeetingRow(
                            meeting: meeting,
                            detail: detail(for: meeting),
                            statusSymbol: statusSymbol(for: meeting.processingStatus),
                            statusColor: statusColor(for: meeting.processingStatus),
                            statusText: statusText(for: meeting.processingStatus),
                            onOpen: { onOpen(meeting) },
                            onRetry: meeting.processingStatus == .failed
                                ? { onRetry(meeting) }
                                : nil,
                            onDelete: { onDelete(meeting) }
                        )

                        if index < meetings.count - 1 {
                            Divider()
                                .overlay(MeetingNotchTheme.subtleHairline)
                                .padding(.leading, 30)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func detail(for meeting: StoredMeeting) -> String {
        let duration = Int(meeting.duration)
        let minutes = duration / 60
        let seconds = duration % 60
        return "\(meeting.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(minutes):\(String(format: "%02d", seconds))"
    }

    private func statusSymbol(for status: StoredMeeting.ProcessingStatus) -> String {
        switch status {
        case .recorded: "waveform.badge.checkmark"
        case .processing: "clock.arrow.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for status: StoredMeeting.ProcessingStatus) -> Color {
        switch status {
        case .recorded: .blue
        case .processing: .orange
        case .completed: .green
        case .failed: .red
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
    let statusSymbol: String
    let statusColor: Color
    let statusText: String
    let onOpen: () -> Void
    let onRetry: (() -> Void)?
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 18, height: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(MeetingNotchTheme.rowTitleFont)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(detail.uppercased())
                        .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovering ? .secondary : .tertiary)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchRowButtonStyle())
        .accessibilityLabel("\(meeting.title), \(statusText), \(detail)")
        .background(
            isHovering ? MeetingNotchTheme.surface : .clear,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.controlRadius,
                style: .continuous
            )
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            if let onRetry {
                Button("İşlemeyi tekrar dene", systemImage: "arrow.clockwise", action: onRetry)
                Divider()
            }
            Button("Toplantıyı sil", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

private struct CaptureSourcesView: View {
    let status: RecordingCaptureStatus

    var body: some View {
        HStack(spacing: 8) {
            source("Mikrofon", symbol: "mic.fill", status: status.microphone)
            source("Sistem", symbol: "speaker.wave.2.fill", status: status.systemAudio)
        }
        .font(.caption2)
    }

    private func source(_ title: String, symbol: String, status: AudioSourceStatus) -> some View {
        HStack(spacing: 5) {
            Image(systemName: sourceSymbol(symbol, state: status.connectionState))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(sourceColor(status.connectionState))
            Text(title)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(status.level))
                .tint(sourceColor(status.connectionState))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 24)
        .accessibilityElement(children: .combine)
        .help(status.connectionState.message ?? (status.isReady ? "Hazır" : "Hazırlanıyor"))
        .accessibilityLabel(accessibilityLabel(title: title, status: status))
    }

    private func sourceSymbol(_ defaultSymbol: String, state: AudioSourceConnectionState) -> String {
        switch state {
        case .preparing: "hourglass"
        case .ready: defaultSymbol
        case .recovered, .pipelineRecovered: "arrow.triangle.2.circlepath"
        case .disconnected: "mic.slash.fill"
        case .pipelineStalled: "speaker.slash.fill"
        }
    }

    private func sourceColor(_ state: AudioSourceConnectionState) -> Color {
        switch state {
        case .preparing, .recovered, .pipelineRecovered: .orange
        case .ready: .green
        case .disconnected, .pipelineStalled: .red
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
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Toplantı mikrofonu: \(title)")
                        .font(MeetingNotchTheme.controlFont)
                    Text("Manuel değiştir: ⌥⌘M")
                        .font(MeetingNotchTheme.metadataFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(NotchActionButtonStyle(tone: gate.permitsAudio ? .primary : .secondary))
        .help("Mikrofon kaydını aç veya gizlilik için kapat (⌥⌘M)")
        .accessibilityLabel("Toplantı mikrofonu \(title). Değiştirmek için Option Command M.")
    }

    private var title: String {
        switch gate.state {
        case .open: "Açık"
        case .closed: "Kapalı"
        case .unknown: "Bilinmiyor · güvenli kapalı"
        }
    }

    private var symbol: String {
        gate.permitsAudio ? "mic.fill" : "mic.slash.fill"
    }

    private var color: Color {
        switch gate.state {
        case .open: .green
        case .closed: .secondary
        case .unknown: .orange
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
                        .fill(.red)
                        .frame(width: 5, height: 5)
                    Image(systemName: clientSymbol(recording.clientID))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(minWidth: 22, minHeight: 18)
                .accessibilityLabel(
                    NotchAccessibilityContract.recordingSessionLabel(
                        clientID: recording.clientID
                    )
                )
            default:
                Image(systemName: presentation.compactIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(presentation.color)
                    .frame(minWidth: 18, minHeight: 18)
                    .accessibilityLabel(presentation.title)
            }
        }
        .meetingNotchPanelAppearance(
            hasPhysicalNotch: appState.notchPanelHasPhysicalNotch
        )
    }

    private func clientSymbol(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "video.fill"
        case .googleMeetChrome: "globe"
        case .unsupported, nil: "waveform.badge.mic"
        }
    }

}

private struct MeetingCountdownView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(startDate.timeIntervalSince(context.date))
            Text(Self.text(seconds: seconds))
                .font(MeetingNotchTheme.dataFont)
                .foregroundStyle(seconds > 60 ? .orange : .red)
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
                    Image(systemName: recording.microphoneState == .open ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(gateColor(recording.microphoneState))
                        .accessibilityLabel(
                            NotchAccessibilityContract.microphoneGateLabel(
                                recording.microphoneState
                            )
                        )
                    RecordingElapsedTimeView(startedAt: recording.startedAt, compact: true)
                        .foregroundStyle(.red)
                }
                .accessibilityElement(children: .contain)
            case .processing(let stage):
                switch stage {
                case .uploading(let progress):
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                        .accessibilityLabel("Yükleme ilerlemesi")
                default:
                    Label(stage.shortTitle, systemImage: "ellipsis")
                        .font(MeetingNotchTheme.metadataFont)
                        .foregroundStyle(MeetingNotchTheme.accent)
                }
            case .completed:
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .accessibilityLabel("İşlem tamamlandı")
            case .failed:
                Image(systemName: "exclamationmark")
                    .foregroundStyle(.red)
                    .accessibilityLabel("İşlem hatası")
            case .upcoming(let startDate):
                CompactMeetingCountdownView(startDate: startDate)
            case .tasks(let count):
                Label("\(count)", systemImage: "checkmark.circle")
                    .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                    .foregroundStyle(.mint)
                    .accessibilityLabel("\(count) aktif görev")
            case .idle:
                Text("READY")
                    .font(MeetingNotchTheme.metadataFont)
                    .foregroundStyle(.secondary)
            }
        }
        .meetingNotchPanelAppearance(
            hasPhysicalNotch: appState.notchPanelHasPhysicalNotch
        )
    }

    private func gateColor(_ state: MeetingMicrophoneState) -> Color {
        switch state {
        case .open: .green
        case .closed: .secondary
        case .unknown: .orange
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
                .foregroundStyle(seconds > 60 ? .orange : .red)
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
                        : MeetingNotchTheme.dataFont
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
    let icon: String
    let compactIcon: String
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
                icon: "calendar.badge.clock",
                compactIcon: "waveform.badge.mic",
                color: MeetingNotchTheme.accent,
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
                icon: "calendar.badge.clock",
                compactIcon: "clock.fill",
                color: .orange,
                title: meeting.title,
                detail: detail
            )
        case .preparingRecording:
            self.init(
                icon: "mic.badge.plus",
                compactIcon: "mic.fill",
                color: .orange,
                title: "Kayıt hazırlanıyor",
                detail: "Ses kaynakları ve izinler kontrol ediliyor."
            )
        case .recording(let startedAt):
            self.init(
                icon: "record.circle.fill",
                compactIcon: "record.circle.fill",
                color: .red,
                title: "Kayıt devam ediyor",
                detail: "Başlangıç: \(startedAt.formatted(date: .omitted, time: .standard))"
            )
        case .finalizingAudio:
            self.init(
                icon: "waveform.badge.checkmark",
                compactIcon: "waveform",
                color: MeetingNotchTheme.accent,
                title: "Ses hazırlanıyor",
                detail: "Kayıt güvenli biçimde sonlandırılıyor."
            )
        case .uploading(let progress):
            self.init(
                icon: "arrow.up.circle.fill",
                compactIcon: "arrow.up.circle",
                color: MeetingNotchTheme.accent,
                title: "Kayıt yükleniyor",
                detail: "Transkripsiyon için ses dosyası gönderiliyor.",
                progress: progress
            )
        case .transcribing:
            self.init(
                icon: "text.bubble.fill",
                compactIcon: "text.bubble",
                color: MeetingNotchTheme.accent,
                title: "Transkript hazırlanıyor",
                detail: "Konuşmacılar ve konuşmalar ayrıştırılıyor."
            )
        case .summarizing:
            self.init(
                icon: "sparkles",
                compactIcon: "sparkles",
                color: .purple,
                title: "Özet hazırlanıyor",
                detail: "Kararlar ve aksiyon maddeleri çıkarılıyor."
            )
        case .completed:
            self.init(
                icon: "checkmark.circle.fill",
                compactIcon: "checkmark.circle.fill",
                color: .green,
                title: "Kayıt tamamlandı",
                detail: "Mikrofon ve sistem sesi yerel olarak kaydedildi."
            )
        case .cancelled:
            self.init(
                icon: "xmark.circle",
                compactIcon: "xmark.circle",
                color: .secondary,
                title: "İşlem iptal edildi",
                detail: "Yeni bir kayıt başlatabilirsiniz."
            )
        case .failed(let failure):
            self.init(
                icon: "exclamationmark.triangle.fill",
                compactIcon: "exclamationmark.triangle.fill",
                color: .red,
                title: failure.title,
                detail: failure.message
            )
        }
    }

    private init(
        icon: String,
        compactIcon: String,
        color: Color,
        title: String,
        detail: String,
        progress: Double? = nil
    ) {
        self.icon = icon
        self.compactIcon = compactIcon
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
