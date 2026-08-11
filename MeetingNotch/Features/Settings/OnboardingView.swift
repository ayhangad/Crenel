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
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.18))
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding ilerlemesi")
            .accessibilityValue("\(step.rawValue + 1) / \(Step.allCases.count)")
            .padding(.horizontal, 40)
            .padding(.top, 26)

            Group {
                switch step {
                case .welcome:
                    onboardingContent(
                        icon: "waveform.badge.mic",
                        title: "Toplantılarınız, kaybolmadan",
                        detail: "MeetingNotch mikrofon ve sistem sesini birlikte kaydeder; konuşmacı ayrımlı transkript ve kısa sonuçları geçmişinizde tutar.",
                        callout: "Manuel kayıt her zaman menü çubuğundan ve notch panelinden erişilebilir."
                    )
                case .microphone:
                    onboardingContent(
                        icon: "mic.fill",
                        title: "Sizin sesiniz için mikrofon",
                        detail: "Mikrofon izni, toplantıda söylediklerinizi kayda eklemek için gereklidir. MeetingNotch izni yalnızca siz kayıt başlattığınızda kullanır.",
                        status: appState.audioCapturePermissions.microphone
                    )
                case .systemAudio:
                    onboardingContent(
                        icon: "speaker.wave.2.fill",
                        title: "Diğer katılımcılar için sistem sesi",
                        detail: "Sistem sesi izni, görüşmedeki diğer kişilerin sesini yakalar. macOS bu izni Gizlilik ve Güvenlik > Sistem Sesini Kaydetme bölümünde yönetir.",
                        status: appState.audioCapturePermissions.systemAudio
                    )
                case .browserAudio:
                    onboardingContent(
                        icon: "globe.badge.chevron.backward",
                        title: "Google Meet sekmesini siz bağlarsınız",
                        detail: "Chrome uzantısı yalnız aktif meet.google.com görüşme sekmesinde, siz araç çubuğu düğmesine bastığınızda ses yakalar. Diğer sekmeler ve uygulamalar bu kaynağa dahil edilmez.",
                        callout: browserAudioStatusText
                    )
                case .accessibility:
                    onboardingContent(
                        icon: "accessibility",
                        title: "Mute durumunu yalnız doğrulanmış kontrolden oku",
                        detail: "Accessibility izni, Zoom ve Google Meet’in görüşme kontrollerini yerel olarak okuyup toplantı mikrofonunun açık, kapalı veya bilinmiyor durumunu belirler. MeetingNotch konuşma içeriğini ya da pencere metnini saklamaz.",
                        callout: appState.accessibilityPermissionGranted
                            ? "Accessibility hazır. Her yeni kayıt yine güvenli olarak kapalı başlar."
                            : "İzin verilmezse kayıt kullanılabilir kalır; mikrofon gate’i bilinmiyor durumunda kayda kapalıdır ve ⌥⌘M ile görünür biçimde açılabilir."
                    )
                case .calendar:
                    onboardingContent(
                        icon: "calendar.badge.clock",
                        title: "Yaklaşan toplantıları kaçırmayın",
                        detail: "İsteğe bağlı takvim erişimi çevrim içi toplantıları bulup önceden notch üzerinde hatırlatır. Reddederseniz manuel kayıt aynen çalışır.",
                        callout: calendarStatus
                    )
                case .cloud:
                    onboardingContent(
                        icon: "lock.shield.fill",
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
                        .controlSize(.large)
                        .frame(minHeight: 40)
                }

                Spacer()

                if step == .calendar {
                    Button("Şimdi Değil") { move(to: Step.cloud.rawValue) }
                        .controlSize(.large)
                        .frame(minHeight: 40)
                }

                Button(primaryButtonTitle) { performPrimaryAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minHeight: 40)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(minWidth: 600, minHeight: 460)
        .background(.background)
    }

    private func onboardingContent(
        icon: String,
        title: String,
        detail: String,
        callout: String? = nil,
        status: AudioCapturePermissionStatus? = nil
    ) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 76, height: 76)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 480)
            }

            if let status {
                Label(permissionTitle(status), systemImage: permissionIcon(status))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(permissionColor(status))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(permissionColor(status).opacity(0.1), in: Capsule())
            } else if let callout {
                Label(callout, systemImage: "info.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: 480, alignment: .leading)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 52)
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

    private func permissionIcon(_ status: AudioCapturePermissionStatus) -> String {
        switch status {
        case .authorized: "checkmark.circle.fill"
        case .verificationRequired: "waveform.badge.magnifyingglass"
        case .notDetermined, .denied, .restricted: "exclamationmark.circle.fill"
        }
    }

    private func permissionColor(_ status: AudioCapturePermissionStatus) -> Color {
        status == .authorized ? .green : .orange
    }
}
