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

    var googleCalendarActions = GoogleCalendarSettingsActions()
    @State private var calendarConnection = CalendarConnectionKind.macOS
    var notificationService: MeetingNotificationService?
    var openAISettings = OpenAISettingsActions()

    @State private var reminderLeadTime: TimeInterval = 10 * 60
    @State private var isCalendarEnabled = true
    @State private var selectedCalendarIDs: [String]?
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
        },
        openAISettings: OpenAISettingsActions = OpenAISettingsActions(),
        notificationService: MeetingNotificationService? = nil,
        googleCalendarActions: GoogleCalendarSettingsActions = GoogleCalendarSettingsActions(),
        initialCategory: SettingsCategory = .general
    ) {
        _category = State(initialValue: initialCategory)
        self.googleCalendarActions = googleCalendarActions
        self.notificationService = notificationService
        self.openAISettings = openAISettings
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

    @State private var category = SettingsCategory.general

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ayarlar").font(.system(size: 28, weight: .bold))
                Text("MeetingNotch’u çalışma şeklinize göre düzenleyin.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker("Ayar kategorisi", selection: $category) {
                ForEach(SettingsCategory.allCases) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
            LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.sectionSpacing) {
                switch category {
                case .general: generalContent
                case .ai: aiContent
                case .calendar: calendarContent
                case .recording: recordingContent
                case .data: dataContent
                }
            }
            .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(MeetingNotchTheme.primaryText)
        .font(MeetingNotchTheme.bodyFont)
        .tint(MeetingNotchTheme.cyan)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
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
            Text("Toplantılar, ses kayıtları, transkriptler, görevler, ayarlar ve Keychain’deki ElevenLabs ve OpenAI anahtarları kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
    }

    @ViewBuilder private var generalContent: some View {
                settingsSection(title: "Genel", assetName: "FigmaMore") {
                    Toggle("Oturum açıldığında başlat", isOn: $launchAtLogin)

                    settingsDivider

                    Picker("Toplantıları sakla", selection: $retentionDays) {
                        Text("Süresiz").tag(nil as Int?)
                        Text("7 gün").tag(7 as Int?)
                        Text("30 gün").tag(30 as Int?)
                        Text("90 gün").tag(90 as Int?)
                    }
                }

                settingsActionRow(message: generalSettingsMessage, isFailure: generalSettingsFailed,
                    buttonTitle: "Değişiklikleri Kaydet", isBusy: isSavingGeneralSettings,
                    isDisabled: isLoadingGeneralSettings, action: saveGeneralSettings)
    }

    @ViewBuilder private var aiContent: some View {
                OpenAISettingsView(actions: openAISettings)

                settingsSection(
                    title: "Transkripsiyon",
                    assetName: "FigmaVoice",
                    footer: "MeetingNotch kayıt bittikten sonra çalışır. OpenAI bağlantısı açıksa transkript ayrıca özet ve görevler için OpenAI’ye gönderilir. Kayıt durduktan sonra güvenceye alınan tek M4A dosyası konuşmacı ayrımı ve zaman damgaları için ElevenLabs Scribe v2’ye yüklenir. Anahtar yalnızca bu Mac’in Keychain’inde tutulur."
                ) {
                    Text("ElevenLabs Scribe v2 · Ses kaydını konuşmacı ayrımlı metne dönüştürür.")
                        .font(.callout).foregroundStyle(.secondary)
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
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        MeetingNotchTheme.elevatedSurface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    Link(
                        "ElevenLabs’te API anahtarı oluştur",
                        destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
                    )
                    .foregroundStyle(MeetingNotchTheme.cyan)
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
                        .buttonStyle(.bordered)
                        .disabled(isSavingTranscriptionSettings)
                    }
                }

    }

    @ViewBuilder private var calendarContent: some View {
                if let notificationService {
                    MeetingNotificationSettingsView(service: notificationService)
                }
                GoogleCalendarSettingsView(actions: googleCalendarActions)
                    .onChange(of: appState.calendarConnection) { _, kind in
                        calendarConnection = kind
                        selectedCalendarIDs = nil
                        isCalendarEnabled = appState.isCalendarEnabled
                    }
                Picker("Takvim kaynağı", selection: Binding(
                    get: { calendarConnection },
                    set: { calendarConnection = $0; selectedCalendarIDs = nil }
                )) {
                    Text("Bu Mac’in takvimleri").tag(CalendarConnectionKind.macOS)
                    if googleCalendarActions.configured {
                        Text("Google Calendar").tag(CalendarConnectionKind.google)
                    }
                }
                calendarSettingsSection
                if let calendars = appState.calendarIntegrationSnapshot?.calendars, !calendars.isEmpty {
                    settingsSection(title: "İzlenecek Takvimler", assetName: "FigmaVideo") {
                        Toggle("Tüm takvimler", isOn: Binding(
                            get: { selectedCalendarIDs == nil },
                            set: { selectedCalendarIDs = $0 ? nil : calendars.map(\.id) }
                        ))
                        if selectedCalendarIDs != nil {
                            ForEach(calendars) { calendar in
                                Toggle(calendar.title, isOn: Binding(
                                    get: { selectedCalendarIDs?.contains(calendar.id) ?? true },
                                    set: { selected in
                                        var ids = Set(selectedCalendarIDs ?? [])
                                        if selected { ids.insert(calendar.id) } else { ids.remove(calendar.id) }
                                        selectedCalendarIDs = ids.sorted()
                                    }
                                ))
                            }
                        }
                        Button("Takvim Seçimini Kaydet", action: saveGeneralSettings)
                            .disabled(isSavingGeneralSettings)
                    }
                }

    }

    @ViewBuilder private var recordingContent: some View {
                settingsSection(
                    title: "Kayıt Kaynağı",
                    assetName: "FigmaMicrophone",
                    footer: microphoneFooterText
                ) {
                    Picker("Kayıt mikrofonu", selection: $selectedMicrophoneID) {
                        Text("Sistem varsayılanı").tag(nil as String?)
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

                    settingsDivider

                    LabeledContent("Bağlı mikrofonlar") {
                        Text(availableMicrophones.isEmpty ? "Bulunamadı" : "\(availableMicrophones.count)")
                            .monospacedDigit()
                            .foregroundStyle(
                                availableMicrophones.isEmpty
                                    ? MeetingNotchTheme.danger
                                    : MeetingNotchTheme.secondaryText
                            )
                    }

                    settingsActionRow(
                        message: microphoneSettingsMessage,
                        isFailure: microphoneSettingsFailed,
                        buttonTitle: "Mikrofonu Kaydet",
                        isBusy: isSavingMicrophone,
                        isDisabled: isLoadingMicrophones,
                        action: saveMicrophoneSelection
                    )
                }

                settingsSection(
                    title: "Kayıt İzinleri",
                    assetName: "FigmaVolume",
                    footer: "Mikrofon ve sistem sesi kayıt başlarken yeniden doğrulanır. Accessibility yalnız Zoom/Meet görüşme ve mute durumunu yerel okumak içindir; izin yoksa manuel kayıt gizlenmez ve mikrofon güvenli kapalı kalır."
                ) {
                    PermissionRow(
                        source: .microphone,
                        title: "Mikrofon",
                        detail: "Sizin konuşmanızı toplantı kaydına ekler.",
                        status: appState.audioCapturePermissions.microphone,
                        onRequestAccess: onRequestMicrophoneAccess,
                        onOpenSystemSettings: onOpenSystemSettings
                    )
                    settingsDivider
                    PermissionRow(
                        source: .systemAudio,
                        title: "Sistem sesi",
                        detail: "Toplantıdaki diğer kişilerin sesini kaydeder.",
                        status: appState.audioCapturePermissions.systemAudio,
                        onRequestAccess: onRequestSystemAudioAccess,
                        onOpenSystemSettings: onOpenSystemSettings,
                        onRelaunchApplication: onRelaunchApplication
                    )
                    settingsDivider
                    AccessibilityPermissionRow(
                        isGranted: appState.accessibilityPermissionGranted,
                        onRequestAccess: onRequestAccessibilityAccess,
                        onOpenSystemSettings: onOpenAccessibilitySettings
                    )
                }

                DisclosureGroup("Gelişmiş kayıt bilgileri") {
                settingsSection(title: "Gizlilik Sınırı", assetName: "FigmaMicrophoneOff") {
                    settingValue("Toplantı mikrofonu", "Her kayıtta kapalı başlar")
                    settingsDivider
                    settingValue("Belirsiz mute durumu", "Ses kayda alınmaz")
                    settingsDivider
                    settingValue("Manuel kontrol", "Notch veya ⌥⌘M", monospaced: true)
                    settingsDivider
                    settingValue("Google Meet", "Sekme izolasyonu yoksa fail-closed")
                    settingsDivider
                    HStack(spacing: 12) {
                        Text("Meet sekme bağlantısı")
                        Spacer()
                        Label(browserAudioStatusText, systemImage: browserAudioStatusSymbol)
                            .foregroundStyle(browserAudioStatusColor)
                    }
                }

                }
    }

    @ViewBuilder private var dataContent: some View {
                settingsSection(
                    title: "Veri ve Uygulama",
                    assetName: "FigmaArchive",
                    footer: appState.requiresTerminationConfirmation
                        ? "Kayıt veya işleme sürerken tüm veriler silinemez."
                        : nil
                ) {
                    HStack(spacing: 10) {
                        Button("Veri Klasörünü Aç", action: onOpenDataDirectory)
                            .buttonStyle(.bordered)
                        Button("Onboarding’i Göster", action: resetOnboarding)
                            .buttonStyle(.bordered)
                        Button("Tüm Verileri Sil…", role: .destructive) {
                            showsDeleteAllDataConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.requiresTerminationConfirmation || isDeletingAllData)
                    }
                    settingsDivider
                    settingValue(
                        "Sürüm",
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
                        monospaced: true
                    )
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
        case .unavailable: MeetingNotchTheme.danger
        case .waitingForMeetTab: MeetingNotchTheme.secondaryText
        case .tabConnected: MeetingNotchTheme.success
        case .recording: MeetingNotchTheme.danger
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        assetName: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.contentSpacing) {
            HStack(spacing: MeetingNotchTheme.itemSpacing) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: MeetingNotchTheme.MainPanel.iconSize,
                        height: MeetingNotchTheme.MainPanel.iconSize
                    )
                    .foregroundStyle(MeetingNotchTheme.primaryText)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MeetingNotchTheme.surface,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            if let footer {
                Text(footer)
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(MeetingNotchTheme.hairline)
            .frame(height: 1)
    }

    private func settingValue(
        _ title: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .font(
                    monospaced
                        ? MeetingNotchTheme.bodyFont.monospaced()
                        : MeetingNotchTheme.bodyFont
                )
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 28)
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
                HStack(spacing: 8) {
                    Image(isFailure ? "FigmaWarning" : "FigmaRecentCheck")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text(message)
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                }
                .foregroundStyle(
                    isFailure ? MeetingNotchTheme.danger : MeetingNotchTheme.secondaryText
                )
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("İşlem sürüyor")
            }

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled || isBusy)
        }
        .frame(minHeight: 40)
    }

    private func apply(_ snapshot: GeneralSettingsSnapshot) {
        reminderLeadTime = snapshot.reminderLeadTime
        isCalendarEnabled = snapshot.isCalendarEnabled
        selectedCalendarIDs = snapshot.selectedCalendarIDs
        calendarConnection = snapshot.calendarConnection ?? .macOS
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
            meetingRetentionPolicy: policy,
            selectedCalendarIDs: selectedCalendarIDs,
            calendarConnection: calendarConnection
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
        settingsSection(
            title: "Takvim Bağlantısı",
            assetName: "FigmaRecentCheck",
            footer: "Toplantılar seçtiğiniz takvim kaynağından alınır; Gmail okunmaz. Zoom, Google Meet ve Microsoft Teams bağlantıları etkinlik alanlarında eşleştirilir."
        ) {
            Toggle("Takvim toplantılarını göster", isOn: $isCalendarEnabled)

            settingsDivider

            Picker("Toplantı hatırlatması", selection: $reminderLeadTime) {
                Text("5 dakika ve 1 dakika önce").tag(TimeInterval(5 * 60))
                Text("10 dakika ve 1 dakika önce").tag(TimeInterval(10 * 60))
                Text("15 dakika ve 1 dakika önce").tag(TimeInterval(15 * 60))
            }
            .disabled(!isCalendarEnabled)

            settingsDivider

            LabeledContent("Bağlantı") {
                Label(calendarStatusTitle, systemImage: calendarStatusSymbol)
                    .foregroundStyle(calendarStatusColor)
            }

            if let snapshot = appState.calendarIntegrationSnapshot,
               appState.calendarAccessState == .authorized {
                DisclosureGroup("Bağlantı ayrıntıları") {
                    CalendarIntegrationDetails(snapshot: snapshot)
                }
            }

            HStack(spacing: 8) {
                calendarPrimaryAction

                Button("Hesapları Aç", systemImage: "person.crop.circle.badge.plus") {
                    onOpenInternetAccounts()
                }
                .buttonStyle(.bordered)
                .disabled(!isCalendarEnabled)
            }

            settingsActionRow(
                message: generalSettingsMessage,
                isFailure: generalSettingsFailed,
                buttonTitle: "Takvim Ayarlarını Kaydet",
                isBusy: isSavingGeneralSettings,
                isDisabled: isLoadingGeneralSettings,
                action: saveGeneralSettings
            )
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
        guard isCalendarEnabled else { return MeetingNotchTheme.secondaryText }
        return switch appState.calendarAccessState {
        case .authorized: MeetingNotchTheme.success
        case .requesting, .notDetermined: MeetingNotchTheme.secondaryText
        case .denied, .restricted: MeetingNotchTheme.warning
        case .failed: MeetingNotchTheme.danger
        }
    }

    @ViewBuilder
    private var calendarPrimaryAction: some View {
        switch appState.calendarAccessState {
        case .authorized:
            Button("Şimdi Yenile", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .buttonStyle(.bordered)
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .denied, .restricted:
            Button("Takvim İznini Aç", systemImage: "gearshape") {
                onOpenCalendarSettings()
            }
            .buttonStyle(.bordered)
            .disabled(!isCalendarEnabled)
        case .requesting:
            Button("İzin Bekleniyor…", systemImage: "clock") {}
                .buttonStyle(.bordered)
                .disabled(true)
        case .failed:
            Button("Tekrar Dene", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .buttonStyle(.bordered)
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .notDetermined:
            Button("Takvime İzin Ver", systemImage: "calendar.badge.plus") {
                onRequestCalendarAccess()
            }
            .buttonStyle(.borderedProminent)
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
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }

        LabeledContent("Okunabilir içerik") {
            Text(readableContentDescription)
                .font(.body.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.secondaryText)
        }

        LabeledContent("Çevrim içi toplantı") {
            Text(snapshot.matchedMeetingCount, format: .number)
                .font(.body.monospacedDigit())
                .foregroundStyle(
                    snapshot.matchedMeetingCount == 0
                        ? MeetingNotchTheme.secondaryText
                        : MeetingNotchTheme.success
                )
        }

        LabeledContent("Son yenileme") {
            Text(snapshot.refreshedAt, style: .relative)
                .font(.body.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.secondaryText)
        }

        if !snapshot.hasGoogleAccount {
            HStack(alignment: .top, spacing: 8) {
                Image("FigmaWarning")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("Google Calendar görünmüyor. Google hesabını macOS İnternet Hesapları’na ekleyip Takvim’i açın.")
            }
            .font(MeetingNotchTheme.MainPanel.smallFont)
            .foregroundStyle(MeetingNotchTheme.warning)
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
            Image(source == .microphone ? "FigmaMicrophone" : "FigmaVolume")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(statusColor)
                .frame(width: 20, height: 20)
                .padding(10)
                .background(
                    statusColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MeetingNotchTheme.rowTitleFont)
                Text(detail)
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
            }

            Spacer(minLength: 16)

            if status == .authorized {
                MeetingNotchStatusBadge(
                    title: "Hazır",
                    assetName: "FigmaRecentCheck",
                    tint: MeetingNotchTheme.success
                )
            } else if status == .verificationRequired {
                HStack(spacing: 8) {
                    MeetingNotchStatusBadge(
                        title: "Doğrulama gerekli",
                        assetName: "FigmaWarning",
                        tint: MeetingNotchTheme.warning
                    )
                    Button("İzin Ver", action: onRequestAccess)
                        .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                }
            } else if source == .systemAudio, status.requiresSystemSettings {
                HStack(spacing: 6) {
                    Button("Tekrar İste", action: onRequestAccess)
                        .buttonStyle(MeetingNotchActionButtonStyle())
                    Button("Ayarları Aç") { onOpenSystemSettings(source) }
                        .buttonStyle(MeetingNotchActionButtonStyle())
                    Button(action: onRelaunchApplication) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(MeetingNotchIconButtonStyle())
                    .help("MeetingNotch’u yeniden başlat")
                    .accessibilityLabel("MeetingNotch’u yeniden başlat")
                }
            } else {
                Button(actionTitle) {
                    status.requiresSystemSettings
                        ? onOpenSystemSettings(source)
                        : onRequestAccess()
                }
                .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
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

    private var statusColor: Color {
        switch status {
        case .authorized: MeetingNotchTheme.success
        case .verificationRequired, .notDetermined: MeetingNotchTheme.warning
        case .denied, .restricted: MeetingNotchTheme.danger
        }
    }
}

private struct AccessibilityPermissionRow: View {
    let isGranted: Bool
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(isGranted ? "FigmaRecentCheck" : "FigmaWarning")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    isGranted ? MeetingNotchTheme.success : MeetingNotchTheme.warning
                )
                .frame(width: 20, height: 20)
                .padding(10)
                .background(
                    (isGranted ? MeetingNotchTheme.success : MeetingNotchTheme.warning)
                        .opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility")
                    .font(MeetingNotchTheme.rowTitleFont)
                Text("Zoom/Meet call controls ve mute durumunu yerel okur; UI metni saklanmaz.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if isGranted {
                MeetingNotchStatusBadge(
                    title: "Hazır",
                    assetName: "FigmaRecentCheck",
                    tint: MeetingNotchTheme.success
                )
            } else {
                HStack(spacing: 8) {
                    Button("İzin Ver", action: onRequestAccess)
                        .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                    Button("Ayarları Aç", action: onOpenSystemSettings)
                        .buttonStyle(MeetingNotchActionButtonStyle())
                }
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

enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general = "Genel"
    case ai = "Yapay zekâ"
    case calendar = "Takvim"
    case recording = "Kayıt"
    case data = "Veri"
    var id: String { rawValue }
}
