import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    let onRequestMicrophoneAccess: () -> Void
    let onRequestSystemAudioAccess: () -> Void
    let onOpenSystemSettings: (AudioSourceKind) -> Void
    let onRefreshPermissions: () -> Void

    init(
        onRequestMicrophoneAccess: @escaping () -> Void = {},
        onRequestSystemAudioAccess: @escaping () -> Void = {},
        onOpenSystemSettings: @escaping (AudioSourceKind) -> Void = { _ in },
        onRefreshPermissions: @escaping () -> Void = {}
    ) {
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onRequestSystemAudioAccess = onRequestSystemAudioAccess
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onRefreshPermissions = onRefreshPermissions
    }

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    source: .microphone,
                    title: "Mikrofon",
                    detail: "Sizin konuşmanızı toplantı kaydına ekler.",
                    status: appState.audioCapturePermissions.microphone,
                    onRequestAccess: onRequestMicrophoneAccess,
                    onOpenSystemSettings: onOpenSystemSettings
                )

                PermissionRow(
                    source: .systemAudio,
                    title: "Sistem sesi",
                    detail: "Toplantıdaki diğer kişilerin sesini kaydeder.",
                    status: appState.audioCapturePermissions.systemAudio,
                    onRequestAccess: onRequestSystemAudioAccess,
                    onOpenSystemSettings: onOpenSystemSettings
                )
            } header: {
                Text("Kayıt İzinleri")
            } footer: {
                Text("MeetingNotch kayıt başlatmadan önce iki izni de yeniden kontrol eder.")
            }

            Section("Genel") {
                LabeledContent("Takvim") {
                    Text(calendarStatusTitle)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Sürüm") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 360)
        .onAppear(perform: onRefreshPermissions)
    }

    private var calendarStatusTitle: String {
        switch appState.calendarAccessState {
        case .authorized:
            "Bağlı"
        case .requesting:
            "İzin bekleniyor"
        case .denied, .restricted:
            "İzin verilmedi"
        case .failed:
            "Bağlantı hatası"
        case .notDetermined:
            "Henüz bağlanmadı"
        }
    }
}

private struct PermissionRow: View {
    let source: AudioSourceKind
    let title: String
    let detail: String
    let status: AudioCapturePermissionStatus
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: (AudioSourceKind) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .background(statusColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if status == .authorized {
                Label("Hazır", systemImage: "checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle) {
                    if status.requiresSystemSettings {
                        onOpenSystemSettings(source)
                    } else {
                        onRequestAccess()
                    }
                }
                .controlSize(.large)
                .frame(minHeight: 40)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusTitle)
    }

    private var actionTitle: String {
        status.requiresSystemSettings ? "Ayarları Aç" : "İzin Ver"
    }

    private var statusTitle: String {
        switch status {
        case .authorized:
            "İzin verildi"
        case .notDetermined:
            "İzin bekleniyor"
        case .denied:
            "İzin verilmedi"
        case .restricted:
            "Sistem tarafından kısıtlandı"
        }
    }

    private var statusIcon: String {
        switch status {
        case .authorized:
            "checkmark"
        case .notDetermined:
            "questionmark"
        case .denied, .restricted:
            "exclamationmark"
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized:
            .green
        case .notDetermined:
            .orange
        case .denied, .restricted:
            .red
        }
    }
}
