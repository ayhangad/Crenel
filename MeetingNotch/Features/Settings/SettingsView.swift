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
                Text("Settings").font(MeetingNotchTheme.pageTitleFont)
            }
            HStack(spacing: 6) {
                ForEach(SettingsCategory.allCases) { item in
                    Button { category = item } label: {
                        ViewThatFits(in: .horizontal) {
                            Label(item.title, systemImage: item.symbol)
                            Text(item.title)
                        }
                        .font(MeetingNotchTheme.controlFont)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(category == item ? MeetingNotchTheme.primaryText : MeetingNotchTheme.secondaryText)
                    }
                    .buttonStyle(MeetingNotchRowButtonStyle(selected: category == item))
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("Settings categories")
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
                microphoneSettingsMessage = "Selected mic isn’t connected; recordings will use the system default."
                microphoneSettingsFailed = true
            }
        }
        .alert("Delete all data?", isPresented: $showsDeleteAllDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete permanently", role: .destructive) { deleteAllData() }
        } message: {
            Text("Meetings, audio, transcripts, tasks on this Mac, settings, and the ElevenLabs, OpenAI and Anthropic keys in Keychain will be permanently deleted. Tasks in Apple Reminders stay. This can’t be undone.")
        }
    }

    @ViewBuilder private var generalContent: some View {
                settingsSection(title: "General", assetName: "FigmaMore") {
                    Toggle("Launch at login", isOn: $launchAtLogin)

                    settingsDivider

                    Picker("Keep meetings", selection: $retentionDays) {
                        Text("Forever").tag(nil as Int?)
                        Text("7 days").tag(7 as Int?)
                        Text("30 days").tag(30 as Int?)
                        Text("90 days").tag(90 as Int?)
                    }
                }

                settingsActionRow(message: generalSettingsMessage, isFailure: generalSettingsFailed,
                    buttonTitle: "Save changes", isBusy: isSavingGeneralSettings,
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
                    Picker("Transcript language", selection: $languageCode) {
                        Text("Automatic").tag(nil as String?)
                        Text("Turkish").tag("tr" as String?)
                        Text("English").tag("en" as String?)
                    }
                    SecureField(
                        hasStoredAPIKey ? "Type to replace the saved key" : "ElevenLabs API key",
                        text: $apiKey
                    )
                    .textContentType(.password)
                    .focused($apiKeyFocused)
                    .meetingFieldSurface(focused: apiKeyFocused)
                    .accessibilityLabel("ElevenLabs API key")
                    Link(
                        "Create an API key on ElevenLabs",
                        destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
                    )
                    .buttonStyle(.plain)
                    .foregroundStyle(MeetingNotchTheme.cyan)
                    .fixedSize(horizontal: false, vertical: true)
                    settingsActionRow(
                        message: transcriptionSettingsMessage,
                        isFailure: transcriptionSettingsFailed,
                        buttonTitle: "Verify and save",
                        isBusy: isSavingTranscriptionSettings,
                        isDisabled: isLoadingTranscriptionSettings
                            || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && !hasStoredAPIKey),
                        action: saveTranscriptionSettings
                    )
                    if hasStoredAPIKey {
                        Button("Remove connection", role: .destructive) {
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
                    settingsSection(title: "Watched calendars", assetName: "FigmaVideo") {
                        Toggle("All calendars", isOn: Binding(
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
                        Button("Save calendar selection", action: saveGeneralSettings)
                            .disabled(isSavingGeneralSettings)
                    }
                }

    }

    @ViewBuilder private var recordingContent: some View {
                settingsSection(
                    title: "Recording source",
                    assetName: "FigmaMicrophone",
                    footer: nil
                ) {
                    HStack(spacing: 12) {
                    Picker("Recording mic", selection: $selectedMicrophoneID) {
                        Text("System default").tag(nil as String?)
                        ForEach(availableMicrophones) { microphone in
                            Text(microphone.isSystemDefault ? "\(microphone.name) — default" : microphone.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(microphone.name)
                                .tag(microphone.id as String?)
                        }
                        if let selectedMicrophoneID,
                           !availableMicrophones.contains(where: { $0.id == selectedMicrophoneID }) {
                            Text("Selected mic not connected")
                                .tag(selectedMicrophoneID as String?)
                        }
                    }
                    .controlSize(.large)
                    .disabled(isLoadingMicrophones || availableMicrophones.isEmpty)

                        Button("Save", action: saveMicrophoneSelection)
                            .buttonStyle(MeetingNotchActionButtonStyle())
                            .disabled(isLoadingMicrophones || isSavingMicrophone || availableMicrophones.isEmpty)
                    }
                    if let microphoneSettingsMessage {
                        MeetingNotchFeedback(message: microphoneSettingsMessage, isFailure: microphoneSettingsFailed)
                    }
                }

                settingsSection(
                    title: "Recording permissions",
                    assetName: "FigmaVolume",
                    footer: nil
                ) {
                    PermissionRow(
                        source: .microphone,
                        title: "Microphone",
                        detail: "Adds your voice to meeting recordings.",
                        status: appState.audioCapturePermissions.microphone,
                        onRequestAccess: onRequestMicrophoneAccess,
                        onOpenSystemSettings: onOpenSystemSettings
                    )
                    settingsDivider
                    PermissionRow(
                        source: .systemAudio,
                        title: "System audio",
                        detail: "Records other people in the meeting.",
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

                DisclosureGroup("Advanced recording details") {
                settingsSection(title: "Privacy guard", assetName: "FigmaMicrophoneOff") {
                    settingValue("Meeting mic", "Starts muted in every recording")
                    settingsDivider
                    settingValue("Unknown mute state", "Audio isn’t recorded")
                    settingsDivider
                    settingValue("Manual control", "Notch or ⌥⌘M", monospaced: true)
                    settingsDivider
                    settingValue("Google Meet", "Connected call tab only")
                    settingsDivider
                    HStack(spacing: 12) {
                        Text("Meet tab connection")
                        Spacer()
                        Label(browserAudioStatusText, systemImage: browserAudioStatusSymbol)
                            .foregroundStyle(browserAudioStatusColor)
                    }
                }

                }
    }

    @ViewBuilder private var dataContent: some View {
                settingsSection(
                    title: "Data and app",
                    assetName: "FigmaArchive",
                    footer: appState.requiresTerminationConfirmation
                        ? "Can’t delete all data while recording or processing."
                        : nil
                ) {
                    MeetingNotchActionGroup {
                        Button("Open data folder", action: onOpenDataDirectory)
                            .buttonStyle(MeetingNotchActionButtonStyle())
                        Button("Open setup guide", action: resetOnboarding)
                            .buttonStyle(MeetingNotchActionButtonStyle())
                        Button("Delete all data…", role: .destructive) {
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
                        "Version",
                        "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")",
                        monospaced: true
                    )
                }
    }

    private var browserAudioStatusText: LocalizedStringKey {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: "Unavailable"
        case .waitingForMeetTab: "Waiting for Meet tab"
        case .tabConnected: "Tab connected"
        case .recording: "Connected to recording"
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
        title: LocalizedStringKey,
        assetName: String,
        footer: LocalizedStringKey? = nil,
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
        _ title: LocalizedStringKey,
        _ value: LocalizedStringKey,
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
        buttonTitle: LocalizedStringKey,
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
                    ProgressView().controlSize(.small).accessibilityLabel("Working")
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
            microphoneSettingsMessage = "Selected mic isn’t connected; recordings will use the system default."
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
                microphoneSettingsMessage = message ?? "Mic selection saved."
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
                    ? "Verified; reprocessing \(retriedJobCount) pending recordings"
                    : "Speech-to-Text access verified and saved"
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
                transcriptionSettingsMessage = message ?? "ElevenLabs connection removed"
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
            generalSettingsMessage = message ?? "Saved"
            generalSettingsFailed = false
        case .failed(let message):
            generalSettingsMessage = message
            generalSettingsFailed = true
        }
    }

    private var calendarSettingsSection: some View {
        settingsSection(
            title: "Calendar connection",
            assetName: "FigmaRecentCheck",
            footer: nil
        ) {
            Toggle("Show calendar meetings", isOn: $isCalendarEnabled)

            settingsDivider

            Picker("Meeting reminder", selection: $reminderLeadTime) {
                Text("5 min and 1 min before").tag(TimeInterval(5 * 60))
                Text("10 min and 1 min before").tag(TimeInterval(10 * 60))
                Text("15 min and 1 min before").tag(TimeInterval(15 * 60))
            }
            .disabled(!isCalendarEnabled)

            settingsDivider

            LabeledContent("Connection") {
                Label(calendarStatusTitle, systemImage: calendarStatusSymbol)
                    .foregroundStyle(calendarStatusColor)
            }

            if let snapshot = appState.calendarIntegrationSnapshot,
               appState.calendarAccessState == .authorized {
                DisclosureGroup("Connection details") {
                    CalendarIntegrationDetails(snapshot: snapshot)
                }
            }

            HStack(spacing: 8) {
                calendarPrimaryAction

                Button("Open accounts", systemImage: "person.crop.circle.badge.plus") {
                    onOpenInternetAccounts()
                }
                .buttonStyle(MeetingNotchActionButtonStyle())
                .disabled(!isCalendarEnabled)
            }

            settingsActionRow(
                message: generalSettingsMessage,
                isFailure: generalSettingsFailed,
                buttonTitle: "Save calendar settings",
                isBusy: isSavingGeneralSettings,
                isDisabled: isLoadingGeneralSettings,
                action: saveGeneralSettings
            )
        }
    }

    private var calendarStatusTitle: LocalizedStringKey {
        guard isCalendarEnabled else { return "Off" }
        if appState.isCalendarRefreshing { return "Refreshing" }
        return switch appState.calendarAccessState {
        case .authorized: "Connected"
        case .requesting: "Waiting for permission"
        case .denied, .restricted: "Permission denied"
        case .failed: "Connection error"
        case .notDetermined: "Not connected yet"
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
            Button("Refresh now", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .buttonStyle(MeetingNotchActionButtonStyle())
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .denied, .restricted:
            Button("Open calendar permission", systemImage: "gearshape") {
                onOpenCalendarSettings()
            }
            .buttonStyle(MeetingNotchActionButtonStyle())
            .disabled(!isCalendarEnabled)
        case .requesting:
            Button("Waiting for permission…", systemImage: "clock") {}
                .buttonStyle(MeetingNotchActionButtonStyle())
                .disabled(true)
        case .failed:
            Button("Try again", systemImage: "arrow.clockwise") {
                onRefreshCalendar()
            }
            .buttonStyle(MeetingNotchActionButtonStyle())
            .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .notDetermined:
            Button("Allow calendar access", systemImage: "calendar.badge.plus") {
                onRequestCalendarAccess()
            }
            .buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
            .disabled(!isCalendarEnabled)
        }
    }

    private var microphoneFooterText: String {
        if availableMicrophones.isEmpty {
            return "No mic connected. The list refreshes when you connect one."
        }
        return "The selected mic is checked when recording starts. If it’s missing, the system default is used; if it disconnects mid-recording, the notch shows a warning."
    }
}

private struct CalendarIntegrationDetails: View {
    let snapshot: CalendarIntegrationSnapshot

    var body: some View {
        LabeledContent("Account sources") {
            Text(sourceDescription)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }

        LabeledContent("Readable content") {
            Text(readableContentDescription)
                .font(.body.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.secondaryText)
        }

        LabeledContent("Online meetings") {
            Text(snapshot.matchedMeetingCount, format: .number)
                .font(.body.monospacedDigit())
                .foregroundStyle(
                    snapshot.matchedMeetingCount == 0
                        ? MeetingNotchTheme.secondaryText
                        : MeetingNotchTheme.success
                )
        }

        LabeledContent("Last refresh") {
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
                Text("Google Calendar isn’t showing. Add your Google account in macOS Internet Accounts and turn on Calendars.")
            }
            .font(MeetingNotchTheme.MainPanel.smallFont)
            .foregroundStyle(MeetingNotchTheme.warning)
        }
    }

    private var sourceDescription: String {
        let description = snapshot.sources
            .map { "\($0.kind.title) (\($0.calendarCount))" }
            .joined(separator: " · ")
        return description.isEmpty ? "No calendar sources found" : description
    }

    private var readableContentDescription: String {
        "\(snapshot.readableCalendarCount) calendars · \(snapshot.scannedEventCount) events"
    }
}

private struct PermissionRow: View {
    let source: AudioSourceKind
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
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
                    .accessibilityLabel("Allowed")
            } else {
                Button(actionTitle) {
                    status.requiresSystemSettings ? onOpenSystemSettings(source) : onRequestAccess()
                }.buttonStyle(MeetingNotchActionButtonStyle())
                if source == .systemAudio, status.requiresSystemSettings {
                    Menu {
                        Button("Ask again", action: onRequestAccess)
                        Button("Relaunch app", action: onRelaunchApplication)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 40, height: 40)
                    .accessibilityLabel("System audio options")
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityValue(statusTitle)
    }

    private var actionTitle: LocalizedStringKey {
        status.requiresSystemSettings ? "Open Settings" : "Allow"
    }

    private var statusTitle: LocalizedStringKey {
        switch status {
        case .authorized: "Allowed"
        case .verificationRequired: "System audio permission needs checking"
        case .notDetermined: "Waiting for permission"
        case .denied: "Permission denied"
        case .restricted: "Restricted by the system"
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
            Text("Mic tracking").help("Accessibility access is needed to detect the meeting’s mic state.")
            Spacer(minLength: 8)
            if isGranted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MeetingNotchTheme.success)
                    .accessibilityLabel("Allowed")
            } else {
                Button("Allow", action: onRequestAccess).buttonStyle(MeetingNotchActionButtonStyle())
                Button(action: onOpenSystemSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(MeetingNotchIconButtonStyle()).help("Accessibility settings")
                    .accessibilityLabel("Open Accessibility settings")
            }
        }.frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

}

enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general, dictation, tasks, ai, calendar, recording, data
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .tasks: "Tasks"
        case .ai: "AI"
        case .calendar: "Calendar"
        case .recording: "Recording"
        case .data: "Data"
        }
    }
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
