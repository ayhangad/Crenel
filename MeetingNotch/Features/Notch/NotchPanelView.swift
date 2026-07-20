import SwiftUI

struct NotchPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabSelection
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelFlow: () -> Void
    let onRecoverFromFailure: (AppFailure) -> Void
    let onOpenStoredMeeting: (StoredMeeting) -> Void
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
        onCancelFlow: @escaping () -> Void = {},
        onRecoverFromFailure: @escaping (AppFailure) -> Void = { _ in },
        onOpenStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
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
        self.onCancelFlow = onCancelFlow
        self.onRecoverFromFailure = onRecoverFromFailure
        self.onOpenStoredMeeting = onOpenStoredMeeting
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
        let layout = NotchPanelLayout(availableSize: appState.notchPanelAvailableSize)

        VStack(spacing: 16) {
            HStack(spacing: 8) {
                NotchTabBar(
                    selection: $appState.selectedTab,
                    selectionNamespace: tabSelection
                )

                Button(action: onTogglePin) {
                    Image(systemName: appState.isNotchPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(NotchPinButtonStyle(isPinned: appState.isNotchPinned))
                .help(appState.isNotchPinned ? "Paneli serbest bırak" : "Paneli açık tut")
                .accessibilityLabel(appState.isNotchPinned ? "Panel sabitlemesini kaldır" : "Paneli açık tut")
                .accessibilityValue(appState.isNotchPinned ? "Açık tutuluyor" : "Serbest")
            }

            ScrollView {
                ZStack {
                    switch appState.selectedTab {
                    case .meetings:
                        MeetingStatusView(
                            onRequestCalendarAccess: onRequestCalendarAccess,
                            onOpenMeetingURL: onOpenMeetingURL,
                            onStartRecording: onStartRecording,
                            onStopRecording: onStopRecording,
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
                .id(appState.selectedTab)
                .frame(
                    maxWidth: .infinity,
                    minHeight: min(NotchPanelLayout.minimumContentHeight, layout.maximumContentHeight),
                    alignment: .top
                )
            }
            .frame(maxHeight: layout.maximumContentHeight)
        }
        .padding(18)
        .frame(width: layout.width)
        .environment(\.colorScheme, .dark)
        .onMoveCommand { direction in
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
    let selectionNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppState.PanelTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .contentShape(Rectangle())
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.11))
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: 28, height: 2)
                                        .offset(y: -3)
                                }
                                .matchedGeometryEffect(
                                    id: "selected-panel-tab",
                                    in: selectionNamespace
                                )
                        }
                    }
                }
                .buttonStyle(NotchTabButtonStyle())
                .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                .help("\(tab.rawValue) sekmesi (⌘\(tab.shortcutDescription))")
                .accessibilityLabel("\(tab.rawValue) sekmesi")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel sekmeleri")
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

private struct NotchPinButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPinned: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            .background(
                Circle()
                    .fill(isPinned ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.07))
            )
            .overlay {
                Circle()
                    .stroke(
                        isPinned ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: isPinned)
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

        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: presentation.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(presentation.color)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(presentation.color.opacity(0.14))
                        )
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(presentation.detail)
                            .font(.system(size: 12))
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
                    if let message = appState.recordingCaptureStatus.microphone.connectionState.message {
                        Label(message, systemImage: microphoneNoticeSymbol)
                            .font(.caption)
                            .foregroundStyle(
                                appState.recordingCaptureStatus.microphone.isReady ? .orange : .red
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Mikrofon uyarısı: \(message)")
                    }
                }

                actionArea
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
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

    private var microphoneNoticeSymbol: String {
        appState.recordingCaptureStatus.microphone.isReady
            ? "arrow.triangle.2.circlepath"
            : "mic.slash.fill"
    }

    @ViewBuilder
    private var statusMetric: some View {
        switch appState.meetingFlow {
        case .recording(let startedAt):
            RecordingElapsedTimeView(startedAt: startedAt)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.red.opacity(0.13), in: Capsule())
        case .upcomingMeeting(let meeting):
            MeetingCountdownView(startDate: meeting.startDate)
        case .uploading(let progress):
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.blue.opacity(0.13), in: Capsule())
        case .preparingRecording, .finalizingAudio, .transcribing, .summarizing:
            ProgressView()
                .controlSize(.small)
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
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 10)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
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
        case .primary: .white
        case .secondary: .primary
        case .danger: .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .primary: Color.accentColor.opacity(0.88)
        case .secondary: Color.white.opacity(0.075)
        case .danger: Color.red.opacity(0.14)
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .primary: Color.white.opacity(0.12)
        case .secondary: Color.white.opacity(0.07)
        case .danger: Color.red.opacity(0.2)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Son kayıtlar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !meetings.isEmpty {
                    Text("\(meetings.count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }

            if meetings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

                    Text("İlk kaydınız tamamlandığında burada görünecek.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
            } else {
                ForEach(meetings) { meeting in
                    HStack(spacing: 6) {
                        Button {
                            onOpen(meeting)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: statusSymbol(for: meeting.processingStatus))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(statusColor(for: meeting.processingStatus))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        statusColor(for: meeting.processingStatus).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(detail(for: meeting))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 8)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }
                        .buttonStyle(NotchRowButtonStyle())
                        .accessibilityLabel("\(meeting.title), \(statusText(for: meeting.processingStatus)), \(detail(for: meeting))")

                        if meeting.processingStatus == .failed {
                            Button {
                                onRetry(meeting)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(NotchIconButtonStyle(tint: .orange))
                            .help("İşlemeyi tekrar dene")
                            .accessibilityLabel("\(meeting.title) transkripsiyonunu tekrar dene")
                        }

                        Button(role: .destructive) {
                            onDelete(meeting)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(NotchIconButtonStyle(tint: .red))
                        .accessibilityLabel("\(meeting.title) kaydını sil")
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.055), lineWidth: 1)
                    }
                }
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
                .foregroundStyle(sourceColor(status.connectionState))
            Text(title)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(status.level))
                .tint(sourceColor(status.connectionState))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .help(status.connectionState.message ?? (status.isReady ? "Hazır" : "Hazırlanıyor"))
        .accessibilityLabel(accessibilityLabel(title: title, status: status))
    }

    private func sourceSymbol(_ defaultSymbol: String, state: AudioSourceConnectionState) -> String {
        switch state {
        case .preparing: "hourglass"
        case .ready: defaultSymbol
        case .recovered: "arrow.triangle.2.circlepath"
        case .disconnected: "mic.slash.fill"
        }
    }

    private func sourceColor(_ state: AudioSourceConnectionState) -> Color {
        switch state {
        case .preparing, .recovered: .orange
        case .ready: .green
        case .disconnected: .red
        }
    }

    private func accessibilityLabel(title: String, status: AudioSourceStatus) -> String {
        if let message = status.connectionState.message {
            return "\(title): \(message)"
        }
        return "\(title) \(status.isReady ? "hazır" : "hazırlanıyor")"
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

private struct NotchIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint.opacity(configuration.isPressed ? 1 : 0.72))
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.045), in: Circle())
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
        Image(systemName: presentation.compactIcon)
            .foregroundStyle(presentation.color)
            .frame(minWidth: 18, minHeight: 18)
            .accessibilityLabel(presentation.title)
    }
}

private struct MeetingCountdownView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(startDate.timeIntervalSince(context.date))
            Text(Self.text(seconds: seconds))
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(seconds > 60 ? .orange : .red)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    (seconds > 60 ? Color.orange : Color.red).opacity(0.13),
                    in: Capsule()
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
            activeTaskCount: appState.activeTaskCount
        )

        switch status {
        case .recording(let startedAt):
            RecordingElapsedTimeView(startedAt: startedAt, compact: true)
                .foregroundStyle(.red)
        case .processing(let stage):
            switch stage {
            case .uploading(let progress):
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit())
                    .accessibilityLabel("Yükleme ilerlemesi")
            default:
                Label(stage.shortTitle, systemImage: "ellipsis")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
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
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.mint)
                .accessibilityLabel("\(count) aktif görev")
        case .idle:
            Text("Hazır")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
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
                .font(.caption2.monospacedDigit().bold())
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
            Text(Self.format(context.date.timeIntervalSince(startedAt)))
                .font(
                    compact
                        ? .caption2.monospacedDigit().bold()
                        : .system(size: 14, weight: .bold, design: .rounded).monospacedDigit()
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
                color: .blue,
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
                color: .blue,
                title: "Ses hazırlanıyor",
                detail: "Kayıt güvenli biçimde sonlandırılıyor."
            )
        case .uploading(let progress):
            self.init(
                icon: "arrow.up.circle.fill",
                compactIcon: "arrow.up.circle",
                color: .blue,
                title: "Kayıt yükleniyor",
                detail: "Transkripsiyon için ses dosyası gönderiliyor.",
                progress: progress
            )
        case .transcribing:
            self.init(
                icon: "text.bubble.fill",
                compactIcon: "text.bubble",
                color: .blue,
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

#Preview {
    NotchPanelView()
        .environmentObject(AppState())
}
