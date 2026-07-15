import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    let onRequestMicrophoneAccess: () -> Void
    let onRequestSystemAudioAccess: () -> Void
    let onOpenSystemSettings: (AudioSourceKind) -> Void
    let onRelaunchApplication: () -> Void
    let onRefreshPermissions: () -> Void
    let onLoadGeneralSettings: () async -> GeneralSettingsSnapshot
    let onSaveGeneralSettings: (GeneralSettingsSnapshot) async -> SettingsActionResult
    let onOpenDataDirectory: () -> Void
    let onDeleteAllData: () async -> SettingsActionResult
    let onResetOnboarding: () async -> SettingsActionResult
    let onLoadTranscriptionSettings: () async -> TranscriptionSettingsSnapshot
    let onSaveTranscriptionSettings: (
        TranscriptionProviderID,
        String?,
        String?
    ) async -> TranscriptionSettingsSaveResult

    @State private var reminderLeadTime: TimeInterval = 10 * 60
    @State private var isCalendarEnabled = true
    @State private var launchAtLogin = false
    @State private var retentionDays: Int?
    @State private var isLoadingGeneralSettings = true
    @State private var isSavingGeneralSettings = false
    @State private var generalSettingsMessage: String?
    @State private var generalSettingsFailed = false
    @State private var isDeletingAllData = false
    @State private var showsDeleteAllDataConfirmation = false

    @State private var selectedProvider = TranscriptionProviderID.elevenLabs
    @State private var languageCode: String?
    @State private var apiKey = ""
    @State private var hasStoredAPIKey = false
    @State private var isLoadingTranscriptionSettings = true
    @State private var isSavingTranscriptionSettings = false
    @State private var transcriptionSettingsMessage: String?
    @State private var transcriptionSettingsFailed = false

    init(
        onRequestMicrophoneAccess: @escaping () -> Void = {},
        onRequestSystemAudioAccess: @escaping () -> Void = {},
        onOpenSystemSettings: @escaping (AudioSourceKind) -> Void = { _ in },
        onRelaunchApplication: @escaping () -> Void = {},
        onRefreshPermissions: @escaping () -> Void = {},
        onLoadGeneralSettings: @escaping () async -> GeneralSettingsSnapshot = { .default },
        onSaveGeneralSettings: @escaping (
            GeneralSettingsSnapshot
        ) async -> SettingsActionResult = { _ in .succeeded() },
        onOpenDataDirectory: @escaping () -> Void = {},
        onDeleteAllData: @escaping () async -> SettingsActionResult = { .succeeded() },
        onResetOnboarding: @escaping () async -> SettingsActionResult = { .succeeded() },
        onLoadTranscriptionSettings: @escaping () async -> TranscriptionSettingsSnapshot = {
            TranscriptionSettingsSnapshot(
                provider: .elevenLabs,
                languageCode: nil,
                hasStoredAPIKey: false
            )
        },
        onSaveTranscriptionSettings: @escaping (
            TranscriptionProviderID,
            String?,
            String?
        ) async -> TranscriptionSettingsSaveResult = { _, _, _ in .saved }
    ) {
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onRequestSystemAudioAccess = onRequestSystemAudioAccess
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onRelaunchApplication = onRelaunchApplication
        self.onRefreshPermissions = onRefreshPermissions
        self.onLoadGeneralSettings = onLoadGeneralSettings
        self.onSaveGeneralSettings = onSaveGeneralSettings
        self.onOpenDataDirectory = onOpenDataDirectory
        self.onDeleteAllData = onDeleteAllData
        self.onResetOnboarding = onResetOnboarding
        self.onLoadTranscriptionSettings = onLoadTranscriptionSettings
        self.onSaveTranscriptionSettings = onSaveTranscriptionSettings
    }

    var body: some View {
        Form {
            Section("Genel") {
                Toggle("Takvim toplantılarını göster", isOn: $isCalendarEnabled)

                Picker("Toplantı hatırlatması", selection: $reminderLeadTime) {
                    Text("5 dakika ve 1 dakika önce").tag(TimeInterval(5 * 60))
                    Text("10 dakika ve 1 dakika önce").tag(TimeInterval(10 * 60))
                    Text("15 dakika ve 1 dakika önce").tag(TimeInterval(15 * 60))
                }
                .disabled(!isCalendarEnabled)

                Toggle("Login’de otomatik aç", isOn: $launchAtLogin)

                Picker("Toplantıları sakla", selection: $retentionDays) {
                    Text("Süresiz").tag(nil as Int?)
                    Text("7 gün").tag(7 as Int?)
                    Text("30 gün").tag(30 as Int?)
                    Text("90 gün").tag(90 as Int?)
                }

                settingsActionRow(
                    message: generalSettingsMessage,
                    isFailure: generalSettingsFailed,
                    buttonTitle: "Değişiklikleri Kaydet",
                    isBusy: isSavingGeneralSettings,
                    isDisabled: isLoadingGeneralSettings,
                    action: saveGeneralSettings
                )
            }

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
                    onOpenSystemSettings: onOpenSystemSettings,
                    onRelaunchApplication: onRelaunchApplication
                )
            } header: {
                Text("Kayıt İzinleri")
            } footer: {
                Text("MeetingNotch kayıt başlatmadan önce iki izni de yeniden kontrol eder. Sistem sesi iznini yeni verdiğiniz halde durum değişmiyorsa uygulamayı bir kez yeniden başlatın.")
            }

            Section {
                Picker("Provider", selection: $selectedProvider) {
                    Text("ElevenLabs Scribe v2")
                        .tag(TranscriptionProviderID.elevenLabs)
                    Text("OpenAI (yakında)")
                        .tag(TranscriptionProviderID.openAI)
                        .disabled(true)
                }

                Picker("Transkript dili", selection: $languageCode) {
                    Text("Otomatik algıla").tag(nil as String?)
                    Text("Türkçe").tag("tr" as String?)
                    Text("İngilizce").tag("en" as String?)
                }

                SecureField(
                    hasStoredAPIKey ? "Kayıtlı anahtarı değiştirmek için yazın" : "ElevenLabs API anahtarı",
                    text: $apiKey
                )
                .textContentType(.password)

                settingsActionRow(
                    message: transcriptionSettingsMessage ?? (hasStoredAPIKey ? "API anahtarı Keychain’de kayıtlı" : nil),
                    isFailure: transcriptionSettingsFailed,
                    buttonTitle: "Doğrula ve Kaydet",
                    isBusy: isSavingTranscriptionSettings,
                    isDisabled: isLoadingTranscriptionSettings
                        || selectedProvider != .elevenLabs
                        || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !hasStoredAPIKey),
                    action: saveTranscriptionSettings
                )
            } header: {
                Text("Transkripsiyon")
            } footer: {
                Text("Ses dosyası seçili bulut provider’ına yüklenir. API anahtarı yalnızca macOS Keychain’de tutulur.")
            }

            Section {
                LabeledContent("Takvim durumu") {
                    Text(calendarStatusTitle)
                        .foregroundStyle(.secondary)
                }

                Button("Veri Klasörünü Finder’da Aç", systemImage: "folder") {
                    onOpenDataDirectory()
                }
                .controlSize(.large)

                Button("Onboarding’i Yeniden Göster", systemImage: "sparkles") {
                    resetOnboarding()
                }
                .controlSize(.large)

                Button(
                    "Tüm Verileri Sil…",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    showsDeleteAllDataConfirmation = true
                }
                .controlSize(.large)
                .disabled(appState.requiresTerminationConfirmation || isDeletingAllData)

                LabeledContent("Sürüm") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Veri ve Uygulama")
            } footer: {
                if appState.requiresTerminationConfirmation {
                    Text("Kayıt veya işleme sürerken tüm veriler silinemez.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 720)
        .onAppear {
            onRefreshPermissions()
            Task {
                async let general = onLoadGeneralSettings()
                async let transcription = onLoadTranscriptionSettings()
                apply(await general)
                apply(await transcription)
            }
        }
        .alert("Tüm veriler silinsin mi?", isPresented: $showsDeleteAllDataConfirmation) {
            Button("Vazgeç", role: .cancel) {}
            Button("Kalıcı Olarak Sil", role: .destructive) { deleteAllData() }
        } message: {
            Text("Toplantılar, ses kayıtları, transkriptler, görevler, ayarlar ve Keychain’deki provider anahtarları kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
    }

    @ViewBuilder
    private func settingsActionRow(
        message: String?,
        isFailure: Bool,
        buttonTitle: String,
        isBusy: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            if let message {
                Label(
                    message,
                    systemImage: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(isFailure ? .red : .secondary)
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("İşlem sürüyor")
            }

            Button(buttonTitle, action: action)
                .controlSize(.large)
                .disabled(isDisabled || isBusy)
        }
        .frame(minHeight: 40)
    }

    private func apply(_ snapshot: GeneralSettingsSnapshot) {
        reminderLeadTime = snapshot.reminderLeadTime
        isCalendarEnabled = snapshot.isCalendarEnabled
        launchAtLogin = snapshot.launchAtLogin
        retentionDays = snapshot.meetingRetentionPolicy.days
        isLoadingGeneralSettings = false
    }

    private func apply(_ snapshot: TranscriptionSettingsSnapshot) {
        selectedProvider = snapshot.provider
        languageCode = snapshot.languageCode
        hasStoredAPIKey = snapshot.hasStoredAPIKey
        isLoadingTranscriptionSettings = false
    }

    private func saveGeneralSettings() {
        isSavingGeneralSettings = true
        generalSettingsMessage = nil
        let policy = retentionDays.flatMap(MeetingRetentionPolicy.init(deletingAfterDays:))
            ?? .keepForever
        let snapshot = GeneralSettingsSnapshot(
            reminderLeadTime: reminderLeadTime,
            isCalendarEnabled: isCalendarEnabled,
            launchAtLogin: launchAtLogin,
            meetingRetentionPolicy: policy
        )

        Task {
            handleGeneralResult(await onSaveGeneralSettings(snapshot))
            isSavingGeneralSettings = false
        }
    }

    private func saveTranscriptionSettings() {
        isSavingTranscriptionSettings = true
        transcriptionSettingsMessage = nil
        let newAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await onSaveTranscriptionSettings(
                selectedProvider,
                languageCode,
                newAPIKey.isEmpty ? nil : newAPIKey
            )
            switch result {
            case .saved:
                hasStoredAPIKey = true
                apiKey = ""
                transcriptionSettingsMessage = "Doğrulandı ve kaydedildi"
                transcriptionSettingsFailed = false
            case .failed(let failure):
                transcriptionSettingsMessage = failure.message
                transcriptionSettingsFailed = true
            }
            isSavingTranscriptionSettings = false
        }
    }

    private func resetOnboarding() {
        Task { handleGeneralResult(await onResetOnboarding()) }
    }

    private func deleteAllData() {
        isDeletingAllData = true
        generalSettingsMessage = nil
        Task {
            handleGeneralResult(await onDeleteAllData())
            isDeletingAllData = false
            apply(await onLoadGeneralSettings())
            apply(await onLoadTranscriptionSettings())
        }
    }

    private func handleGeneralResult(_ result: SettingsActionResult) {
        switch result {
        case .succeeded(let message):
            generalSettingsMessage = message ?? "Kaydedildi"
            generalSettingsFailed = false
        case .failed(let message):
            generalSettingsMessage = message
            generalSettingsFailed = true
        }
    }

    private var calendarStatusTitle: String {
        guard isCalendarEnabled else { return "Kapalı" }
        return switch appState.calendarAccessState {
        case .authorized: "Bağlı"
        case .requesting: "İzin bekleniyor"
        case .denied, .restricted: "İzin verilmedi"
        case .failed: "Bağlantı hatası"
        case .notDetermined: "Henüz bağlanmadı"
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
    var onRelaunchApplication: () -> Void = {}

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
            } else if status == .verificationRequired {
                HStack(spacing: 8) {
                    Label("Doğrulama gerekli", systemImage: "waveform.badge.magnifyingglass")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Button("İzin Ver", action: onRequestAccess)
                        .controlSize(.large)
                }
            } else if source == .systemAudio, status.requiresSystemSettings {
                HStack(spacing: 6) {
                    Button("Tekrar İste", action: onRequestAccess)
                    Button("Ayarları Aç") { onOpenSystemSettings(source) }
                    Button(action: onRelaunchApplication) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("MeetingNotch’u yeniden başlat")
                    .accessibilityLabel("MeetingNotch’u yeniden başlat")
                }
                .controlSize(.large)
            } else {
                Button(actionTitle) {
                    status.requiresSystemSettings
                        ? onOpenSystemSettings(source)
                        : onRequestAccess()
                }
                .controlSize(.large)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusTitle)
    }

    private var actionTitle: String {
        status.requiresSystemSettings ? "Ayarları Aç" : "İzin Ver"
    }

    private var statusTitle: String {
        switch status {
        case .authorized: "İzin verildi"
        case .verificationRequired: "Sistem sesi izni doğrulanmalı"
        case .notDetermined: "İzin bekleniyor"
        case .denied: "İzin verilmedi"
        case .restricted: "Sistem tarafından kısıtlandı"
        }
    }

    private var statusIcon: String {
        switch status {
        case .authorized: "checkmark"
        case .verificationRequired: "waveform"
        case .notDetermined: "questionmark"
        case .denied, .restricted: "exclamationmark"
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized: .green
        case .verificationRequired, .notDetermined: .orange
        case .denied, .restricted: .red
        }
    }
}
