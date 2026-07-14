import SwiftUI

struct NotchPanelView: View {
    @EnvironmentObject private var appState: AppState
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelFlow: () -> Void

    init(
        onRequestCalendarAccess: @escaping () -> Void = {},
        onOpenMeetingURL: @escaping (URL) -> Void = { _ in },
        onStartRecording: @escaping () -> Void = {},
        onStopRecording: @escaping () -> Void = {},
        onCancelFlow: @escaping () -> Void = {}
    ) {
        self.onRequestCalendarAccess = onRequestCalendarAccess
        self.onOpenMeetingURL = onOpenMeetingURL
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onCancelFlow = onCancelFlow
    }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Bölüm", selection: $appState.selectedTab) {
                ForEach(AppState.PanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch appState.selectedTab {
                case .meetings:
                    MeetingStatusView(
                        onRequestCalendarAccess: onRequestCalendarAccess,
                        onOpenMeetingURL: onOpenMeetingURL,
                        onStartRecording: onStartRecording,
                        onStopRecording: onStopRecording,
                        onCancelFlow: onCancelFlow
                    )
                case .tasks:
                    TasksPlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170)
        }
        .padding(16)
        .frame(width: 390)
    }
}

private struct MeetingStatusView: View {
    @EnvironmentObject private var appState: AppState
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelFlow: () -> Void

    var body: some View {
        let presentation = MeetingFlowPresentation(
            state: appState.meetingFlow,
            nextMeeting: appState.nextMeeting,
            reminderLevel: appState.meetingReminderLevel
        )

        VStack(spacing: 10) {
            Image(systemName: presentation.icon)
                .font(.system(size: 28))
                .foregroundStyle(presentation.color)

            Text(presentation.title)
                .font(.headline)

            if case .recording(let startedAt) = appState.meetingFlow {
                RecordingElapsedTimeView(startedAt: startedAt)
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.red)
            } else if case .upcomingMeeting(let meeting) = appState.meetingFlow {
                MeetingCountdownView(startDate: meeting.startDate)
            } else {
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            }

            if appState.meetingFlow.phase == .preparingRecording || appState.meetingFlow.isRecording {
                CaptureSourcesView(status: appState.recordingCaptureStatus)
            }

            actionArea
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch appState.meetingFlow {
        case .idle:
            HStack {
                if appState.calendarAccessState != .authorized {
                    Button(calendarButtonTitle) {
                        onRequestCalendarAccess()
                    }
                    .disabled(appState.calendarAccessState == .requesting)
                }

                if let url = appState.nextMeeting?.meetingURL {
                    Button("Toplantıya Katıl") {
                        onOpenMeetingURL(url)
                    }
                }

                Button("Kaydı Başlat") {
                    onStartRecording()
                }
                .buttonStyle(.borderedProminent)
            }

        case .upcomingMeeting(let meeting):
            HStack {
                if let url = meeting.meetingURL {
                    Button("Katıl") {
                        onOpenMeetingURL(url)
                    }
                }
                Button("Kaydı Başlat") {
                    onStartRecording()
                }
                .buttonStyle(.borderedProminent)
                Button("Geç") {
                    appState.dismissCurrentMeetingReminder()
                }
            }

        case .preparingRecording, .finalizingAudio, .uploading, .transcribing, .summarizing:
            Button("İptal", role: .destructive) {
                onCancelFlow()
            }

        case .recording:
            Button("Kaydı Durdur", role: .destructive) {
                onStopRecording()
            }
            .buttonStyle(.borderedProminent)

        case .failed(let failure):
            Button(failure.recoveryButtonTitle) {
                appState.recoverFromFailure()
            }
            .buttonStyle(.borderedProminent)

        case .completed, .cancelled:
            Button("Tamam") {
                appState.resetFlow()
            }

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
}

private struct CaptureSourcesView: View {
    let status: RecordingCaptureStatus

    var body: some View {
        HStack(spacing: 18) {
            source("Mikrofon", symbol: "mic.fill", status: status.microphone)
            source("Sistem", symbol: "speaker.wave.2.fill", status: status.systemAudio)
        }
        .font(.caption2)
    }

    private func source(_ title: String, symbol: String, status: AudioSourceStatus) -> some View {
        HStack(spacing: 5) {
            Image(systemName: status.isReady ? symbol : "hourglass")
                .foregroundStyle(status.isReady ? .green : .orange)
            Text(title)
            ProgressView(value: Double(status.level))
                .frame(width: 42)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(status.isReady ? "hazır" : "hazırlanıyor")")
    }
}

private struct TasksPlaceholderView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 28))
            Text("Henüz aktif görev yok")
                .font(.headline)
            Text("Görev deposu sonraki adımda bu ekrana bağlanacak.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
    }
}

private struct MeetingCountdownView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(startDate.timeIntervalSince(context.date))
            Text(Self.text(seconds: seconds))
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(seconds > 60 ? .orange : .red)
        }
    }

    private static func text(seconds: Int) -> String {
        guard seconds > 0 else { return "Toplantı başladı" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d kaldı", minutes, remainingSeconds)
    }
}

struct CompactTrailingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.meetingFlow {
        case .recording(let startedAt):
            RecordingElapsedTimeView(startedAt: startedAt, compact: true)
                .foregroundStyle(.red)
        case .uploading(let progress):
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.monospacedDigit())
        case .upcomingMeeting:
            Image(systemName: "clock")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark")
                .foregroundStyle(.red)
        default:
            if let meeting = appState.nextMeeting {
                Text(meeting.startDate, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecordingElapsedTimeView: View {
    let startedAt: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.format(context.date.timeIntervalSince(startedAt)))
                .font(compact ? .caption2.monospacedDigit().bold() : .title3.monospacedDigit().bold())
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
                compactIcon: "calendar",
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
