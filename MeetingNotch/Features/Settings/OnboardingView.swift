import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onRequestMicrophoneAccess: () -> Void
    let onRequestSystemAudioAccess: () -> Void
    let onRequestAccessibilityAccess: () -> Void
    let onRequestCalendarAccess: () -> Void
    let onComplete: () -> Void

    @State private var step = Step.welcome

    private enum Step: Int, CaseIterable {
        case welcome
        case microphone
        case systemAudio
        case browserAudio
        case accessibility
        case calendar
        case cloud
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, MeetingNotchTheme.MainPanel.horizontalPadding)
            .padding(.top, MeetingNotchTheme.MainPanel.verticalPadding)

            Group {
                switch step {
                case .welcome:
                    onboardingContent(
                        assetName: "FigmaVoice",
                        title: "Toplantılarınız, kaybolmadan",
                        detail: "MeetingNotch mikrofon ve sistem sesini birlikte kaydeder; konuşmacı ayrımlı transkript ve kısa sonuçları geçmişinizde tutar.",
                        callout: "Manuel kayıt her zaman menü çubuğundan ve notch panelinden erişilebilir."
                    )
                case .microphone:
                    onboardingContent(
                        assetName: "FigmaMicrophone",
                        title: "Sizin sesiniz için mikrofon",
                        detail: "Mikrofon izni, toplantıda söylediklerinizi kayda eklemek için gereklidir. MeetingNotch izni yalnızca siz kayıt başlattığınızda kullanır.",
                        status: appState.audioCapturePermissions.microphone
                    )
                case .systemAudio:
                    onboardingContent(
                        assetName: "FigmaVolume",
                        title: "Diğer katılımcılar için sistem sesi",
                        detail: "Sistem sesi izni, görüşmedeki diğer kişilerin sesini yakalar. macOS bu izni Gizlilik ve Güvenlik > Sistem Sesini Kaydetme bölümünde yönetir.",
                        status: appState.audioCapturePermissions.systemAudio
                    )
                case .browserAudio:
                    onboardingContent(
                        assetName: "FigmaVideo",
                        title: "Google Meet sekmesini siz bağlarsınız",
                        detail: "Chrome uzantısı yalnız aktif meet.google.com görüşme sekmesinde, siz araç çubuğu düğmesine bastığınızda ses yakalar. Diğer sekmeler ve uygulamalar bu kaynağa dahil edilmez.",
                        callout: browserAudioStatusText
                    )
                case .accessibility:
                    onboardingContent(
                        assetName: "FigmaWarning",
                        title: "Mute durumunu yalnız doğrulanmış kontrolden oku",
                        detail: "Accessibility izni, Zoom ve Google Meet’in görüşme kontrollerini yerel olarak okuyup toplantı mikrofonunun açık, kapalı veya bilinmiyor durumunu belirler. MeetingNotch konuşma içeriğini ya da pencere metnini saklamaz.",
                        callout: appState.accessibilityPermissionGranted
                            ? "Accessibility hazır. Her yeni kayıt yine güvenli olarak kapalı başlar."
                            : "İzin verilmezse kayıt kullanılabilir kalır; mikrofon gate’i bilinmiyor durumunda kayda kapalıdır ve ⌥⌘M ile görünür biçimde açılabilir."
                    )
                case .calendar:
                    onboardingContent(
                        assetName: "FigmaRecentCheck",
                        title: "Yaklaşan toplantıları kaçırmayın",
                        detail: "İsteğe bağlı takvim erişimi, bu Mac’e eklenmiş iCloud, Google ve Exchange takvimlerindeki çevrim içi toplantıları bulup önceden notch üzerinde hatırlatır. Gmail e-postaları okunmaz; reddederseniz manuel kayıt aynen çalışır.",
                        callout: calendarStatus
                    )
                case .cloud:
                    onboardingContent(
                        systemIcon: "lock.shield",
                        title: "Tek bulut servisi: ElevenLabs",
                        detail: "Kayıt tamamlandığında birleşik ses dosyası, konuşmacı ayrımlı transkript üretmek için yalnızca ElevenLabs Scribe v2’ye yüklenir. Canlı ses akışı veya ikinci bir yapay zekâ servisi kullanılmaz.",
                        callout: "Tek ElevenLabs API anahtarınız yalnızca macOS Keychain’de; toplantı dosyalarınız yerel Application Support klasöründe tutulur."
                    )
                }
            }
            .id(step)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .offset(x: -12))
                    )
            )

            Spacer(minLength: 12)

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
            .padding(.horizontal, MeetingNotchTheme.MainPanel.horizontalPadding)
            .padding(.bottom, MeetingNotchTheme.MainPanel.verticalPadding)
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
            .padding(18)
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
                    Image("FigmaWarning")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(MeetingNotchTheme.warning)
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
        .padding(.horizontal, MeetingNotchTheme.MainPanel.horizontalPadding)
        .padding(.top, 40)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            "Başlayalım"
        case .microphone, .systemAudio, .accessibility:
            "İzin Ver ve Devam Et"
        case .browserAudio:
            "Devam Et"
        case .calendar:
            "Takvime İzin Ver"
        case .cloud:
            "Anladım, MeetingNotch’u Aç"
        }
    }

    private func performPrimaryAction() {
        switch step {
        case .welcome:
            move(to: Step.microphone.rawValue)
        case .microphone:
            onRequestMicrophoneAccess()
            move(to: Step.systemAudio.rawValue)
        case .systemAudio:
            onRequestSystemAudioAccess()
            move(to: Step.browserAudio.rawValue)
        case .browserAudio:
            move(to: Step.accessibility.rawValue)
        case .accessibility:
            onRequestAccessibilityAccess()
            move(to: Step.calendar.rawValue)
        case .calendar:
            onRequestCalendarAccess()
            move(to: Step.cloud.rawValue)
        case .cloud:
            onComplete()
        }
    }

    private func move(to rawValue: Int) {
        guard let next = Step(rawValue: rawValue) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
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
            "Köprü hazır. Görüşme sekmesinde MeetingNotch uzantı düğmesine basın."
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
