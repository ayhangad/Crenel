import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var notificationService: MeetingNotificationService?
    var openAISettings = OpenAISettingsActions()
    var crenelSettings = CrenelSettingsActions()

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
    @FocusState private var apiKeyFocused: Bool
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
        crenelSettings: CrenelSettingsActions = CrenelSettingsActions(),
        notificationService: MeetingNotificationService? = nil,
        initialCategory: SettingsCategory = .general
    ) {
        _category = State(initialValue: initialCategory)
        self.notificationService = notificationService
        self.openAISettings = openAISettings
        self.crenelSettings = crenelSettings
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
                Text("Ayarlar").font(MeetingNotchTheme.pageTitleFont)
            }
            HStack(spacing: 6) {
                ForEach(SettingsCategory.allCases) { item in
                    Button { category = item } label: {
                        ViewThatFits(in: .horizontal) {
                            Label(item.rawValue, systemImage: item.symbol)
                            Text(item.rawValue)
                        }
                        .font(MeetingNotchTheme.controlFont)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(category == item ? MeetingNotchTheme.primaryText : MeetingNotchTheme.secondaryText)
                    }
                    .buttonStyle(MeetingNotchRowButtonStyle(selected: category == item))
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("Ayar kategorileri")
            ScrollView {
            LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.sectionSpacing) {
                switch category {
                case .general: generalContent
                case .dictation: DictationSettingsView(actions: crenelSettings)
                case .tasks: TaskStorageSettingsView(actions: crenelSettings)
                case .ai: aiContent
                case .calendar: calendarContent
                case .recording: recordingContent
                case .data: dataContent
                }
            }
            .padding(.vertical, 4)
            .id(category)
            .transition(MeetingNotchMotion.content(reduceMotion: reduceMotion))
            }
            .animation(MeetingNotchMotion.navigation(reduceMotion: reduceMotion), value: category)
            .scrollIndicators(.hidden)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MeetingNotchTheme.workspaceBackground)
        .foregroundStyle(MeetingNotchTheme.primaryText)
        .font(MeetingNotchTheme.bodyFont)
        .tint(MeetingNotchTheme.cyan)
        .buttonStyle(MeetingNotchActionButtonStyle())
        .toggleStyle(.switch)
        .controlSize(.small)
        .environment(\.colorScheme, .dark)
        .environment(\.workspacePalette, true)
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
            Text("Toplantılar, ses kayıtları, transkriptler, bu Mac’teki görevler, ayarlar ve Keychain’deki ElevenLabs, OpenAI ve Anthropic anahtarları kalıcı olarak silinecek. Apple Hatırlatıcılar’daki görevleriniz silinmez. Bu işlem geri alınamaz.")
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                AgentSettingsView(actions: crenelSettings)
                OpenAISettingsView(actions: openAISettings)

                settingsSection(
                    title: "ElevenLabs",
                    assetName: "FigmaVoice"
                ) {
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
                    .focused($apiKeyFocused)
                    .meetingFieldSurface(focused: apiKeyFocused)
                    .accessibilityLabel("ElevenLabs API anahtarı")
                    Link(
                        "ElevenLabs’te API anahtarı oluştur",
                        destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
                    )
                    .buttonStyle(.plain)
                    .foregroundStyle(MeetingNotchTheme.cyan)
                    .fixedSize(horizontal: false, vertical: true)
                    settingsActionRow(
                        message: transcriptionSettingsMessage,
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
                        .buttonStyle(MeetingNotchActionButtonStyle())
                        .disabled(isSavingTranscriptionSettings)
                    }
                }

    }

    }

    @ViewBuilder private var calendarContent: some View {
                if let notificationService {
                    MeetingNotificationSettingsView(service: notificationService)
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
                    footer: nil
                ) {
                    HStack(spacing: 12) {
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

                        Button("Kaydet", action: saveMicrophoneSelection)
                            .buttonStyle(MeetingNotchActionButtonStyle())
                            .disabled(isLoadingMicrophones || isSavingMicrophone || availableMicrophones.isEmpty)
                    }
                    if let microphoneSettingsMessage {
                        MeetingNotchFeedback(message: microphoneSettingsMessage, isFailure: microphoneSettingsFailed)
                    }
                }

                settingsSection(
                    title: "Kayıt İzinleri",
                    assetName: "FigmaVolume",
                    footer: nil
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
                    settingValue("Google Meet", "Yalnız bağlı görüşme sekmesi")
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
                    MeetingNotchActionGroup {
                        Button("Veri Klasörünü Aç", action: onOpenDataDirectory)
                            .buttonStyle(MeetingNotchActionButtonStyle())
                        Button("Kurulum rehberini aç", action: resetOnboarding)
                            .buttonStyle(MeetingNotchActionButtonStyle())
                        Button("Tüm Verileri Sil…", role: .destructive) {
                            showsDeleteAllDataConfirmation = true
                        }
                        .buttonStyle(MeetingNotchActionButtonStyle(kind: .danger))
                        .disabled(appState.requiresTerminationConfirmation || isDeletingAllData)
                    }
                    if let generalSettingsMessage {
                        MeetingNotchFeedback(message: generalSettingsMessage, isFailure: generalSettingsFailed)
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

            if let footer {
                Text(footer)
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
        VStack(alignment: .leading, spacing: 10) {
            if let message {
                MeetingNotchFeedback(message: message, isFailure: isFailure)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView().controlSize(.small).accessibilityLabel("İşlem sürüyor")
                }
                Button(buttonTitle, action: action)
                    .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                    .disabled(isDisabled || isBusy)
            }
        }
        .frame(minHeight: 40)
    }

    private func apply(_ snapshot: GeneralSettingsSnapshot) {
        reminderLeadTime = snapshot.reminderLeadTime
        isCalendarEnabled = snapshot.isCalendarEnabled
        selectedCalendarIDs = snapshot.selectedCalendarIDs
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
            selectedCalendarIDs: selectedCalendarIDs
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
            footer: nil
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
                .buttonStyle(MeetingNotchActionButtonStyle())
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
            .buttonStyle(MeetingNotchActionButtonStyle())
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .denied, .restricted:
            Button("Takvim İznini Aç", systemImage: "gearshape") {
                onOpenCalendarSettings()
            }
            .buttonStyle(MeetingNotchActionButtonStyle())
            .disabled(!isCalendarEnabled)
        case .requesting:
            Button("İzin Bekleniyor…", systemImage: "clock") {}
                .buttonStyle(MeetingNotchActionButtonStyle())
                .disabled(true)
        case .failed:
            Button("Tekrar Dene", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .buttonStyle(MeetingNotchActionButtonStyle())
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .notDetermined:
            Button("Takvime İzin Ver", systemImage: "calendar.badge.plus") {
                onRequestCalendarAccess()
            }
            .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
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
        HStack(spacing: 10) {
            Image(systemName: source == .microphone ? "mic" : "speaker.wave.2")
                .foregroundStyle(statusColor).frame(width: 24)
            Text(title).font(MeetingNotchTheme.bodyFont).help(detail)
            Spacer(minLength: 8)
            if status == .authorized {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MeetingNotchTheme.success)
                    .accessibilityLabel("İzin verildi")
            } else {
                Button(actionTitle) {
                    status.requiresSystemSettings ? onOpenSystemSettings(source) : onRequestAccess()
                }.buttonStyle(MeetingNotchActionButtonStyle())
                if source == .systemAudio, status.requiresSystemSettings {
                    Menu {
                        Button("Tekrar iste", action: onRequestAccess)
                        Button("Uygulamayı yeniden başlat", action: onRelaunchApplication)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 40, height: 40)
                    .accessibilityLabel("Sistem sesi seçenekleri")
                }
            }
        }
        .frame(minHeight: 44)
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
        HStack(spacing: 10) {
            Image(systemName: "accessibility").frame(width: 24)
                .foregroundStyle(isGranted ? MeetingNotchTheme.success : MeetingNotchTheme.secondaryText)
            Text("Mikrofon takibi").help("Toplantının mikrofon durumunu algılamak için erişilebilirlik izni gerekir.")
            Spacer(minLength: 8)
            if isGranted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MeetingNotchTheme.success)
                    .accessibilityLabel("İzin verildi")
            } else {
                Button("İzin ver", action: onRequestAccess).buttonStyle(MeetingNotchActionButtonStyle())
                Button(action: onOpenSystemSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(MeetingNotchIconButtonStyle()).help("Erişilebilirlik ayarları")
                    .accessibilityLabel("Erişilebilirlik ayarlarını aç")
            }
        }.frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

}

enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general = "Genel"
    case dictation = "Dikte"
    case tasks = "Görevler"
    case ai = "Yapay zekâ"
    case calendar = "Takvim"
    case recording = "Kayıt"
    case data = "Veri"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .dictation: "waveform"
        case .tasks: "checklist"
        case .ai: "text.badge.checkmark"
        case .calendar: "calendar"
        case .recording: "mic"
        case .data: "externaldrive"
        }
    }
}
