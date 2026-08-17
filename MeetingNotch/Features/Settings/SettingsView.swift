import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    let onRequestMicrophoneAccess: () -> Void
    let onRequestSystemAudioAccess: () -> Void
    let onRequestAccessibilityAccess: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onOpenSystemSettings: (AudioSourceKind) -> Void
    let onRelaunchApplication: () -> Void
    let onRefreshPermissions: () -> Void
    let onRequestCalendarAccess: () -> Void
    let onRefreshCalendar: () -> Void
    let onOpenCalendarSettings: () -> Void
    let onOpenInternetAccounts: () -> Void
    let onLoadGeneralSettings: () async -> GeneralSettingsSnapshot
    let onSaveGeneralSettings: (GeneralSettingsSnapshot) async -> SettingsActionResult
    let onLoadMicrophoneSettings: () async -> MicrophoneSettingsSnapshot
    let onSaveMicrophoneSelection: (String?) async -> SettingsActionResult
    let onOpenDataDirectory: () -> Void
    let onDeleteAllData: () async -> SettingsActionResult
    let onResetOnboarding: () async -> SettingsActionResult
    let onLoadTranscriptionSettings: () async -> TranscriptionSettingsSnapshot
    let onSaveTranscriptionSettings: (
        String?,
        String?
    ) async -> TranscriptionSettingsSaveResult
    let onDeleteTranscriptionAPIKey: () async -> SettingsActionResult

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

    @State private var availableMicrophones: [MicrophoneDevice] = []
    @State private var selectedMicrophoneID: String?
    @State private var isLoadingMicrophones = true
    @State private var isSavingMicrophone = false
    @State private var microphoneSettingsMessage: String?
    @State private var microphoneSettingsFailed = false

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
        onRequestAccessibilityAccess: @escaping () -> Void = {},
        onOpenAccessibilitySettings: @escaping () -> Void = {},
        onOpenSystemSettings: @escaping (AudioSourceKind) -> Void = { _ in },
        onRelaunchApplication: @escaping () -> Void = {},
        onRefreshPermissions: @escaping () -> Void = {},
        onRequestCalendarAccess: @escaping () -> Void = {},
        onRefreshCalendar: @escaping () -> Void = {},
        onOpenCalendarSettings: @escaping () -> Void = {},
        onOpenInternetAccounts: @escaping () -> Void = {},
        onLoadGeneralSettings: @escaping () async -> GeneralSettingsSnapshot = { .default },
        onSaveGeneralSettings: @escaping (
            GeneralSettingsSnapshot
        ) async -> SettingsActionResult = { _ in .succeeded() },
        onLoadMicrophoneSettings: @escaping () async -> MicrophoneSettingsSnapshot = {
            MicrophoneSettingsSnapshot(devices: [], selectedDeviceID: nil)
        },
        onSaveMicrophoneSelection: @escaping (String?) async -> SettingsActionResult = {
            _ in .succeeded()
        },
        onOpenDataDirectory: @escaping () -> Void = {},
        onDeleteAllData: @escaping () async -> SettingsActionResult = { .succeeded() },
        onResetOnboarding: @escaping () async -> SettingsActionResult = { .succeeded() },
        onLoadTranscriptionSettings: @escaping () async -> TranscriptionSettingsSnapshot = {
            TranscriptionSettingsSnapshot(
                languageCode: nil,
                hasStoredAPIKey: false
            )
        },
        onSaveTranscriptionSettings: @escaping (
            String?,
            String?
        ) async -> TranscriptionSettingsSaveResult = { _, _ in .saved(retriedJobCount: 0) },
        onDeleteTranscriptionAPIKey: @escaping () async -> SettingsActionResult = {
            .succeeded()
        }
    ) {
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onRequestSystemAudioAccess = onRequestSystemAudioAccess
        self.onRequestAccessibilityAccess = onRequestAccessibilityAccess
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onRelaunchApplication = onRelaunchApplication
        self.onRefreshPermissions = onRefreshPermissions
        self.onRequestCalendarAccess = onRequestCalendarAccess
        self.onRefreshCalendar = onRefreshCalendar
        self.onOpenCalendarSettings = onOpenCalendarSettings
        self.onOpenInternetAccounts = onOpenInternetAccounts
        self.onLoadGeneralSettings = onLoadGeneralSettings
        self.onSaveGeneralSettings = onSaveGeneralSettings
        self.onLoadMicrophoneSettings = onLoadMicrophoneSettings
        self.onSaveMicrophoneSelection = onSaveMicrophoneSelection
        self.onOpenDataDirectory = onOpenDataDirectory
        self.onDeleteAllData = onDeleteAllData
        self.onResetOnboarding = onResetOnboarding
        self.onLoadTranscriptionSettings = onLoadTranscriptionSettings
        self.onSaveTranscriptionSettings = onSaveTranscriptionSettings
        self.onDeleteTranscriptionAPIKey = onDeleteTranscriptionAPIKey
    }

    var body: some View {
        Form {
            Section("Genel") {
                Toggle("Login’de otomatik aç", isOn: $launchAtLogin)

                Picker("Toplantıları sakla", selection: $retentionDays) {
                    Text("Süresiz").tag(nil as Int?)
                    Text("7 gün").tag(7 as Int?)
                    Text("30 gün").tag(30 as Int?)
                    Text("90 gün").tag(90 as Int?)
                }

            }

            calendarSettingsSection

            Section {
                Picker("Kayıt mikrofonu", selection: $selectedMicrophoneID) {
                    Text("Sistem varsayılanı")
                        .tag(nil as String?)
                    ForEach(availableMicrophones) { microphone in
                        Text(microphone.isSystemDefault ? "\(microphone.name) — varsayılan" : microphone.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(microphone.name)
                            .tag(microphone.id as String?)
                    }
                    if let selectedMicrophoneID,
                       !availableMicrophones.contains(where: { $0.id == selectedMicrophoneID }) {
                        Text("Seçili mikrofon bağlı değil")
                            .tag(selectedMicrophoneID as String?)
                    }
                }
                .controlSize(.large)
                .disabled(isLoadingMicrophones || availableMicrophones.isEmpty)

                LabeledContent("Bağlı mikrofonlar") {
                    Text(availableMicrophones.isEmpty ? "Bulunamadı" : "\(availableMicrophones.count)")
                        .monospacedDigit()
                        .foregroundStyle(availableMicrophones.isEmpty ? .red : .secondary)
                }

                settingsActionRow(
                    message: microphoneSettingsMessage,
                    isFailure: microphoneSettingsFailed,
                    buttonTitle: "Mikrofonu Kaydet",
                    isBusy: isSavingMicrophone,
                    isDisabled: isLoadingMicrophones,
                    action: saveMicrophoneSelection
                )
            } header: {
                Text("Kayıt Kaynağı")
            } footer: {
                Text(microphoneFooterText)
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

                AccessibilityPermissionRow(
                    isGranted: appState.accessibilityPermissionGranted,
                    onRequestAccess: onRequestAccessibilityAccess,
                    onOpenSystemSettings: onOpenAccessibilitySettings
                )
            } header: {
                Text("Kayıt İzinleri")
            } footer: {
                Text("Mikrofon ve sistem sesi kayıt başlarken yeniden doğrulanır. Accessibility yalnız Zoom/Meet görüşme ve mute durumunu yerel okumak içindir; izin yoksa manuel kayıt gizlenmez ve mikrofon güvenli kapalı kalır.")
            }

            Section("Gizlilik Sınırı") {
                LabeledContent("Toplantı mikrofonu") {
                    Text("Her kayıtta kapalı başlar")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Belirsiz mute durumu") {
                    Text("Ses kayda alınmaz")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Manuel kontrol") {
                    Text("Notch veya ⌥⌘M")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Google Meet") {
                    Text("Sekme izolasyonu yoksa fail-closed")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Meet sekme bağlantısı") {
                    Label(
                        browserAudioStatusText,
                        systemImage: browserAudioStatusSymbol
                    )
                    .foregroundStyle(browserAudioStatusColor)
                }
            }

            Section {
                LabeledContent("Model") {
                    Text("ElevenLabs Scribe v2")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Nerede çalışır?") {
                    Text("Yalnız ElevenLabs bulutu")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Ne zaman işlenir?") {
                    Text("Kayıt durdurulduktan sonra")
                        .foregroundStyle(.secondary)
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

                Link(
                    "ElevenLabs’te API anahtarı oluştur",
                    destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
                )

                settingsActionRow(
                    message: transcriptionSettingsMessage ?? (hasStoredAPIKey ? "API anahtarı Keychain’de kayıtlı" : nil),
                    isFailure: transcriptionSettingsFailed,
                    buttonTitle: "Doğrula ve Kaydet",
                    isBusy: isSavingTranscriptionSettings,
                    isDisabled: isLoadingTranscriptionSettings
                        || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !hasStoredAPIKey),
                    action: saveTranscriptionSettings
                )

                if hasStoredAPIKey {
                    Button("Bağlantıyı Kaldır", role: .destructive) {
                        deleteTranscriptionAPIKey()
                    }
                    .disabled(isSavingTranscriptionSettings)
                }
            } header: {
                Text("Transkripsiyon")
            } footer: {
                Text("MeetingNotch canlı transkript üretmez ve ikinci bir uzak servis kullanmaz. Kaydı durdurduğunuzda mikrofon ve sistem sesi tek M4A dosyasında güvenceye alınır, ardından konuşmacı ayrımı ve zaman damgaları için ElevenLabs Scribe v2’ye yüklenir. Tek anahtar önce doğrulanır ve yalnızca bu Mac’in Keychain’inde tutulur. Ağ ya da servis hatasında ses kaydı silinmez; tekrar deneyebilirsiniz.")
            }

            Section {
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
        .frame(width: 600, height: 760)
        .onAppear {
            onRefreshPermissions()
            Task {
                async let general = onLoadGeneralSettings()
                async let microphone = onLoadMicrophoneSettings()
                async let transcription = onLoadTranscriptionSettings()
                apply(await general)
                apply(await microphone)
                apply(await transcription)
            }
        }
        .onChange(of: appState.availableMicrophones) { _, devices in
            availableMicrophones = devices
            if let selectedMicrophoneID,
               !devices.contains(where: { $0.id == selectedMicrophoneID }) {
                microphoneSettingsMessage = "Seçili mikrofon bağlı değil; kayıtta sistem varsayılanı kullanılacak."
                microphoneSettingsFailed = true
            }
        }
        .alert("Tüm veriler silinsin mi?", isPresented: $showsDeleteAllDataConfirmation) {
            Button("Vazgeç", role: .cancel) {}
            Button("Kalıcı Olarak Sil", role: .destructive) { deleteAllData() }
        } message: {
            Text("Toplantılar, ses kayıtları, transkriptler, görevler, ayarlar ve Keychain’deki ElevenLabs anahtarı kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
    }

    private var browserAudioStatusText: String {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: "Kullanılamıyor"
        case .waitingForMeetTab: "Meet sekmesi bekleniyor"
        case .tabConnected: "Sekme bağlı"
        case .recording: "Kayıt hattına bağlı"
        }
    }

    private var browserAudioStatusSymbol: String {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: "exclamationmark.shield.fill"
        case .waitingForMeetTab: "puzzlepiece.extension"
        case .tabConnected: "checkmark.shield.fill"
        case .recording: "record.circle.fill"
        }
    }

    private var browserAudioStatusColor: Color {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: .red
        case .waitingForMeetTab: .secondary
        case .tabConnected: .green
        case .recording: .red
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
        languageCode = snapshot.languageCode
        hasStoredAPIKey = snapshot.hasStoredAPIKey
        isLoadingTranscriptionSettings = false
    }

    private func apply(_ snapshot: MicrophoneSettingsSnapshot) {
        availableMicrophones = snapshot.devices
        selectedMicrophoneID = snapshot.selectedDeviceID
        isLoadingMicrophones = false
        if !snapshot.selectedDeviceIsAvailable {
            microphoneSettingsMessage = "Seçili mikrofon bağlı değil; kayıtta sistem varsayılanı kullanılacak."
            microphoneSettingsFailed = true
        }
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

    private func saveMicrophoneSelection() {
        isSavingMicrophone = true
        microphoneSettingsMessage = nil
        Task {
            let result = await onSaveMicrophoneSelection(selectedMicrophoneID)
            switch result {
            case .succeeded(let message):
                microphoneSettingsMessage = message ?? "Mikrofon seçimi kaydedildi."
                microphoneSettingsFailed = false
            case .failed(let message):
                microphoneSettingsMessage = message
                microphoneSettingsFailed = true
            }
            isSavingMicrophone = false
        }
    }

    private func saveTranscriptionSettings() {
        isSavingTranscriptionSettings = true
        transcriptionSettingsMessage = nil
        let newAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await onSaveTranscriptionSettings(
                languageCode,
                newAPIKey.isEmpty ? nil : newAPIKey
            )
            switch result {
            case .saved(let retriedJobCount):
                hasStoredAPIKey = true
                apiKey = ""
                transcriptionSettingsMessage = retriedJobCount > 0
                    ? "Doğrulandı; bekleyen \(retriedJobCount) kayıt yeniden işleniyor"
                    : "Speech-to-Text yetkisi doğrulandı ve kaydedildi"
                transcriptionSettingsFailed = false
            case .failed(let failure):
                transcriptionSettingsMessage = failure.message
                transcriptionSettingsFailed = true
            }
            isSavingTranscriptionSettings = false
        }
    }

    private func deleteTranscriptionAPIKey() {
        isSavingTranscriptionSettings = true
        transcriptionSettingsMessage = nil
        Task {
            switch await onDeleteTranscriptionAPIKey() {
            case .succeeded(let message):
                hasStoredAPIKey = false
                apiKey = ""
                transcriptionSettingsMessage = message ?? "ElevenLabs bağlantısı kaldırıldı"
                transcriptionSettingsFailed = false
            case .failed(let message):
                transcriptionSettingsMessage = message
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
            apply(await onLoadMicrophoneSettings())
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

    private var calendarSettingsSection: some View {
        Section {
            Toggle("Takvim toplantılarını göster", isOn: $isCalendarEnabled)

            Picker("Toplantı hatırlatması", selection: $reminderLeadTime) {
                Text("5 dakika ve 1 dakika önce").tag(TimeInterval(5 * 60))
                Text("10 dakika ve 1 dakika önce").tag(TimeInterval(10 * 60))
                Text("15 dakika ve 1 dakika önce").tag(TimeInterval(15 * 60))
            }
            .disabled(!isCalendarEnabled)

            LabeledContent("Bağlantı") {
                Label(calendarStatusTitle, systemImage: calendarStatusSymbol)
                    .foregroundStyle(calendarStatusColor)
            }

            if let snapshot = appState.calendarIntegrationSnapshot,
               appState.calendarAccessState == .authorized {
                CalendarIntegrationDetails(snapshot: snapshot)
            }

            HStack(spacing: 8) {
                calendarPrimaryAction

                Button("Hesapları Aç", systemImage: "person.crop.circle.badge.plus") {
                    onOpenInternetAccounts()
                }
                .disabled(!isCalendarEnabled)
            }
            .controlSize(.large)

            settingsActionRow(
                message: generalSettingsMessage,
                isFailure: generalSettingsFailed,
                buttonTitle: "Genel ve Takvim Ayarlarını Kaydet",
                isBusy: isSavingGeneralSettings,
                isDisabled: isLoadingGeneralSettings,
                action: saveGeneralSettings
            )
        } header: {
            Text("Takvim Bağlantısı")
        } footer: {
            Text("Google toplantıları Gmail gelen kutusu okunarak değil, bu Mac’e eklenmiş Google Calendar hesabından alınır. Etkinliğin URL, konum veya not alanındaki Zoom, Google Meet ve Microsoft Teams bağlantıları eşleştirilir; e-posta içeriği MeetingNotch’a verilmez.")
        }
    }

    private var calendarStatusTitle: String {
        guard isCalendarEnabled else { return "Kapalı" }
        if appState.isCalendarRefreshing { return "Yenileniyor" }
        return switch appState.calendarAccessState {
        case .authorized: "Bağlı"
        case .requesting: "İzin bekleniyor"
        case .denied, .restricted: "İzin verilmedi"
        case .failed: "Bağlantı hatası"
        case .notDetermined: "Henüz bağlanmadı"
        }
    }

    private var calendarStatusSymbol: String {
        guard isCalendarEnabled else { return "calendar.badge.minus" }
        if appState.isCalendarRefreshing { return "arrow.triangle.2.circlepath" }
        return switch appState.calendarAccessState {
        case .authorized: "checkmark.circle.fill"
        case .requesting: "clock.fill"
        case .denied, .restricted: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .notDetermined: "calendar.badge.plus"
        }
    }

    private var calendarStatusColor: Color {
        guard isCalendarEnabled else { return .secondary }
        return switch appState.calendarAccessState {
        case .authorized: .green
        case .requesting, .notDetermined: .secondary
        case .denied, .restricted: .orange
        case .failed: .red
        }
    }

    @ViewBuilder
    private var calendarPrimaryAction: some View {
        switch appState.calendarAccessState {
        case .authorized:
            Button("Şimdi Yenile", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .denied, .restricted:
            Button("Takvim İznini Aç", systemImage: "gearshape") {
                onOpenCalendarSettings()
            }
            .disabled(!isCalendarEnabled)
        case .requesting:
            Button("İzin Bekleniyor…", systemImage: "clock") {}
                .disabled(true)
        case .failed:
            Button("Tekrar Dene", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .notDetermined:
            Button("Takvime İzin Ver", systemImage: "calendar.badge.plus") {
                onRequestCalendarAccess()
            }
            .disabled(!isCalendarEnabled)
        }
    }

    private var microphoneFooterText: String {
        if availableMicrophones.isEmpty {
            return "Bağlı mikrofon bulunamadı. Bir mikrofon bağladıktan sonra liste otomatik yenilenir."
        }
        return "Seçili cihaz kayıt başlarken yeniden doğrulanır. Bağlı değilse sistem varsayılanına geçilir; kayıt sırasında bağlantı değişirse notch üzerinde uyarı gösterilir."
    }
}

private struct CalendarIntegrationDetails: View {
    let snapshot: CalendarIntegrationSnapshot

    var body: some View {
        LabeledContent("Hesap kaynakları") {
            Text(sourceDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }

        LabeledContent("Okunabilir içerik") {
            Text(readableContentDescription)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }

        LabeledContent("Çevrim içi toplantı") {
            Text(snapshot.matchedMeetingCount, format: .number)
                .font(.body.monospacedDigit())
                .foregroundStyle(snapshot.matchedMeetingCount == 0 ? Color.gray : Color.green)
        }

        LabeledContent("Son yenileme") {
            Text(snapshot.refreshedAt, style: .relative)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }

        if !snapshot.hasGoogleAccount {
            Label {
                Text("Google Calendar görünmüyor. Google hesabını macOS İnternet Hesapları’na ekleyip Takvim’i açın.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private var sourceDescription: String {
        let description = snapshot.sources
            .map { "\($0.kind.title) (\($0.calendarCount))" }
            .joined(separator: " · ")
        return description.isEmpty ? "Takvim kaynağı bulunamadı" : description
    }

    private var readableContentDescription: String {
        "\(snapshot.readableCalendarCount) takvim · \(snapshot.scannedEventCount) etkinlik"
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
        .accessibilityElement(children: .contain)
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

private struct AccessibilityPermissionRow: View {
    let isGranted: Bool
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark" : "exclamationmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28, height: 28)
                .background(
                    (isGranted ? Color.green : Color.orange).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility")
                    .font(.body.weight(.medium))
                Text("Zoom/Meet call controls ve mute durumunu yerel okur; UI metni saklanmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if isGranted {
                Label("Hazır", systemImage: "checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 8) {
                    Button("İzin Ver", action: onRequestAccess)
                    Button("Ayarları Aç", action: onOpenSystemSettings)
                }
                .controlSize(.large)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isGranted ? "İzin verildi" : "İzin verilmedi; mikrofon güvenli kapalı"
        )
    }
}
