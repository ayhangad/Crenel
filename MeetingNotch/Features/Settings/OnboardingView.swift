import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.crenelActions) private var crenelActions

    let onRequestMicrophoneAccess: () -> Void
    let onRequestSystemAudioAccess: () -> Void
    let onRequestAccessibilityAccess: () -> Void
    let onRequestCalendarAccess: () -> Void
    let onComplete: () -> Void

    @State private var step = Step.welcome

    enum Step: Int, CaseIterable {
        case welcome
        case microphone
        case systemAudio
        case browserAudio
        case accessibility
        case calendar
        case reminders
        case dictation
        case cloud
    }

    init(
        onRequestMicrophoneAccess: @escaping () -> Void,
        onRequestSystemAudioAccess: @escaping () -> Void,
        onRequestAccessibilityAccess: @escaping () -> Void,
        onRequestCalendarAccess: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        initialStep: Step = .welcome
    ) {
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onRequestSystemAudioAccess = onRequestSystemAudioAccess
        self.onRequestAccessibilityAccess = onRequestAccessibilityAccess
        self.onRequestCalendarAccess = onRequestCalendarAccess
        self.onComplete = onComplete
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CRENEL").tracking(1.6)
                Spacer()
                Text("\(step.rawValue + 1) / \(Step.allCases.count)").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MeetingNotchTheme.secondaryText)
            .padding(.horizontal, 28).padding(.top, 24)
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(
                            item.rawValue <= step.rawValue
                                ? MeetingNotchTheme.primaryText
                                : MeetingNotchTheme.elevatedSurface
                        )
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding ilerlemesi")
            .accessibilityValue("\(step.rawValue + 1) / \(Step.allCases.count)")
            .padding(.horizontal, 28)
            .padding(.top, MeetingNotchTheme.MainPanel.verticalPadding)

            ScrollView {
            Group {
                switch step {
                case .welcome:
                    onboardingContent(
                        assetName: "FigmaVoice",
                        title: "Notch’unuzdaki yardımcı",
                        detail: "Takviminiz, görevleriniz, dikte ve toplantı kayıtlarınız notch’ta. Her izin isteğe bağlıdır; vermediğiniz özellik sessizce kapalı kalır.",
                        callout: "İstediğiniz zaman Ayarlar’dan değiştirebilirsiniz."
                    )
                case .microphone:
                    onboardingContent(
                        assetName: "FigmaMicrophone",
                        title: "Sizin sesiniz için mikrofon",
                        detail: "Sesinizi kayda eklemek için mikrofon erişimi gerekir.",
                        status: appState.audioCapturePermissions.microphone
                    )
                case .systemAudio:
                    onboardingContent(
                        assetName: "FigmaVolume",
                        title: "Diğer katılımcılar için sistem sesi",
                        detail: "Diğer katılımcıları kaydetmek için sistem sesi erişimi gerekir.",
                        status: appState.audioCapturePermissions.systemAudio
                    )
                case .browserAudio:
                    onboardingContent(
                        assetName: "FigmaVideo",
                        title: "Google Meet’i bağlayın",
                        detail: "Chrome uzantısından görüşme sekmesini bağlayın. Yalnız bağladığınız sekmenin sesi kaydedilir.",
                        callout: browserAudioStatusText
                    )
                case .accessibility:
                    onboardingContent(
                        systemIcon: "switch.2",
                        title: "Toplantı mikrofonunu takip edin",
                        detail: "Zoom ve Meet mikrofonunuzun durumunu takip etmek için erişilebilirlik izni gerekir.",
                        callout: appState.accessibilityPermissionGranted
                            ? "Erişim hazır. Her yeni kayıtta mikrofon güvenli olarak kapalı başlar."
                            : "İzin olmadan mikrofon kayda kapalı kalır. İsterseniz notch üzerinden veya ⌥⌘M ile açabilirsiniz."
                    )
                case .calendar:
                    onboardingContent(
                        assetName: "FigmaRecentCheck",
                        title: "Sıradaki etkinlik, bir bakışta",
                        detail: "Apple Takvim’deki toplantı ve etkinlikleriniz notch’ta; kapalıyken bile kalan süre görünür. Google takvimleri için hesabı Sistem Ayarları › İnternet Hesapları’na ekleyin.",
                        callout: calendarStatus
                    )
                case .reminders:
                    onboardingContent(
                        systemIcon: "checklist",
                        title: "Görevler her cihazınızda",
                        detail: "Görevler Apple Hatırlatıcılar’daki “Crenel” listesinde saklanır; iPhone ve Watch’ta da görünür, saatli görevlerin bildirimini Apple gönderir.",
                        callout: appState.taskStorageStatus.isReminders
                            ? "Hatırlatıcılar bağlı."
                            : "İzin vermezseniz görevler yalnız bu Mac’te tutulur."
                    )
                case .dictation:
                    onboardingContent(
                        systemIcon: "waveform",
                        title: "Fn’ye basılı tutun, konuşun",
                        detail: "Konuşmanız cihazda yazıya çevrilir ve imlecin olduğu yere yazılır. Kısayolu dinlemek için Girdi İzleme izni gerekir.",
                        callout: appState.dictationAvailability == .ready
                            ? "Dikte hazır."
                            : "Fn bundan sonra yalnızca dikte için çalışır. Klavye dilini ⌃Boşluk ile değiştirebilirsiniz."
                    )
                case .cloud:
                    onboardingContent(
                        systemIcon: "lock.shield",
                        title: "Ne cihazda kalır, ne gider",
                        detail: "Dikte ve agent varsayılan olarak cihazda çalışır. Toplantı kaydı tamamlandığında ses, konuşmacı ayrımlı transkript için ElevenLabs’e yüklenir; OpenAI veya Anthropic anahtarı bağlarsanız metin onlara gönderilir.",
                        callout: "Anahtarlarınızı Ayarlar › Yapay zekâ’dan bağlayın."
                    )
                }
            }
            .id(step)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 12)),
                        removal: .opacity.combined(with: .offset(x: -12))
                    )
            )

            .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(MeetingNotchTheme.hairline).frame(height: 1)
                .padding(.horizontal, 28)
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Geri") { move(to: step.rawValue - 1) }
                        .buttonStyle(MeetingNotchActionButtonStyle())
                }

                Spacer()

                if step == .calendar {
                    Button("Şimdi Değil") { move(to: Step.cloud.rawValue) }
                        .buttonStyle(MeetingNotchActionButtonStyle())
                }

                Button(primaryButtonTitle) { performPrimaryAction() }
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: MeetingNotchTheme.panelWidth, height: 500)
        .background(MeetingNotchTheme.panelBackground)
        .foregroundStyle(MeetingNotchTheme.primaryText)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    private func onboardingContent(
        assetName: String? = nil,
        systemIcon: String? = nil,
        title: String,
        detail: String,
        callout: String? = nil,
        status: AudioCapturePermissionStatus? = nil
    ) -> some View {
        VStack(spacing: 20) {
            Group {
                if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                } else if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 32, weight: .medium))
                }
            }
            .foregroundStyle(MeetingNotchTheme.primaryText)
            .frame(width: 40, height: 40)
            .padding(16)
            .background(
                MeetingNotchTheme.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.surfaceRadius,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .medium))
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(MeetingNotchTheme.MainPanel.bodyFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 480)
            }

            if let status {
                MeetingNotchStatusBadge(
                    title: permissionTitle(status),
                    assetName: permissionAsset(status),
                    tint: permissionColor(status)
                )
            } else if let callout {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                    Text(callout)
                        .font(MeetingNotchTheme.MainPanel.bodyFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                }
                    .padding(16)
                    .frame(maxWidth: 480, alignment: .leading)
                    .background(
                        MeetingNotchTheme.surface,
                        in: RoundedRectangle(
                            cornerRadius: MeetingNotchTheme.surfaceRadius,
                            style: .continuous
                        )
                    )
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            "Başlayalım"
        case .microphone:
            appState.audioCapturePermissions.microphone == .authorized ? "Devam et" : "İzin ver ve devam et"
        case .systemAudio:
            appState.audioCapturePermissions.systemAudio == .authorized ? "Devam et" : "İzin ver ve devam et"
        case .accessibility:
            appState.accessibilityPermissionGranted ? "Devam et" : "İzin ver ve devam et"
        case .browserAudio:
            "Devam Et"
        case .calendar:
            "Takvime İzin Ver"
        case .reminders:
            appState.taskStorageStatus.isReminders ? "Devam et" : "Hatırlatıcılar’a bağla"
        case .dictation:
            appState.dictationAvailability == .ready ? "Devam et" : "İzin ver ve devam et"
        case .cloud:
            "Anladım, Crenel’i Aç"
        }
    }

    private func performPrimaryAction() {
        switch step {
        case .welcome:
            move(to: Step.microphone.rawValue)
        case .microphone:
            if appState.audioCapturePermissions.microphone != .authorized { onRequestMicrophoneAccess() }
            move(to: Step.systemAudio.rawValue)
        case .systemAudio:
            if appState.audioCapturePermissions.systemAudio != .authorized { onRequestSystemAudioAccess() }
            move(to: Step.browserAudio.rawValue)
        case .browserAudio:
            move(to: Step.accessibility.rawValue)
        case .accessibility:
            if !appState.accessibilityPermissionGranted { onRequestAccessibilityAccess() }
            move(to: Step.calendar.rawValue)
        case .calendar:
            onRequestCalendarAccess()
            move(to: Step.reminders.rawValue)
        case .reminders:
            if !appState.taskStorageStatus.isReminders { crenelActions.tasks.connectReminders() }
            move(to: Step.dictation.rawValue)
        case .dictation:
            if appState.dictationAvailability != .ready { crenelActions.dictation.requestInputMonitoring() }
            move(to: Step.cloud.rawValue)
        case .cloud:
            onComplete()
        }
    }

    private func move(to rawValue: Int) {
        guard let next = Step(rawValue: rawValue) else { return }
        withAnimation(MeetingNotchMotion.navigation(reduceMotion: reduceMotion)) {
            step = next
        }
    }

    private var calendarStatus: String {
        switch appState.calendarAccessState {
        case .authorized:
            "Takvim erişimi hazır."
        case .requesting:
            "Takvim izni bekleniyor."
        case .denied, .restricted:
            "Takvim izni verilmedi; manuel kayıt kullanılabilir."
        case .failed:
            "Takvim durumu okunamadı; daha sonra Ayarlar’dan deneyebilirsiniz."
        case .notDetermined:
            "Bu izin isteğe bağlıdır ve Ayarlar’dan kapatılabilir."
        }
    }

    private var browserAudioStatusText: String {
        switch appState.browserAudioConnectionStatus {
        case .unavailable:
            "Tarayıcı ses köprüsü kullanılamıyor; Google Meet kaydı güvenli olarak başlamaz."
        case .waitingForMeetTab:
            "Köprü hazır. Görüşme sekmesinde Crenel uzantı düğmesine basın."
        case .tabConnected:
            "Google Meet sekmesi bağlı; kayıt başlatılabilir."
        case .recording:
            "Google Meet sekmesinin sesi güvenli kayıt hattına bağlı."
        }
    }

    private func permissionTitle(_ status: AudioCapturePermissionStatus) -> String {
        switch status {
        case .authorized: "İzin hazır"
        case .verificationRequired: "İzin kayıt başlarken doğrulanacak"
        case .notDetermined: "Henüz izin istenmedi"
        case .denied: "İzin verilmedi"
        case .restricted: "Sistem tarafından kısıtlandı"
        }
    }

    private func permissionAsset(_ status: AudioCapturePermissionStatus) -> String {
        switch status {
        case .authorized: "FigmaRecentCheck"
        case .verificationRequired: "FigmaVoice"
        case .notDetermined, .denied, .restricted: "FigmaWarning"
        }
    }

    private func permissionColor(_ status: AudioCapturePermissionStatus) -> Color {
        status == .authorized ? MeetingNotchTheme.success : MeetingNotchTheme.warning
    }
}
