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
    @State private var showsPrivacyDetails = false
    @State private var showsCalendarDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Hud.Space.x6) {
            Text("Settings")
                .font(Hud.font(22, .semibold))
                .foregroundStyle(Hud.Ink.text1)
                .padding(.horizontal, Hud.Size.rowInset)
            SettingsCategoryTabs(selection: $category)
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Hud.Space.x6)
                .id(category)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : Hud.Motion.change, value: category)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Hud.Space.x6)
        .padding(.top, Hud.Space.x7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.06))
        .foregroundStyle(Hud.Ink.text1)
        .font(Hud.Style.body.font)
        .tint(Hud.Ink.text2)
        .buttonStyle(HudButtonStyle(kind: .ghost))
        .toggleStyle(.switch)
        .controlSize(.small)
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

    // MARK: Pages

    @ViewBuilder private var generalContent: some View {
        SettingsGroup("General") {
            SettingsRow(glyph: .sun, title: "Launch at login") {
                Toggle("Launch at login", isOn: $launchAtLogin).settingsSwitch()
            }
            SettingsRow(glyph: .archive, title: "Keep meetings") {
                Picker("Keep meetings", selection: $retentionDays) {
                    Text("Forever").tag(nil as Int?)
                    Text("7 days").tag(7 as Int?)
                    Text("30 days").tag(30 as Int?)
                    Text("90 days").tag(90 as Int?)
                }.settingsMenu()
            }
            saveRow(message: generalSettingsMessage, isFailure: generalSettingsFailed,
                    buttonTitle: "Save changes", isBusy: isSavingGeneralSettings,
                    isDisabled: isLoadingGeneralSettings, action: saveGeneralSettings)
        }
    }

    @ViewBuilder private var aiContent: some View {
        AgentSettingsView(actions: crenelSettings)
        OpenAISettingsView(actions: openAISettings)

        SettingsGroup("ElevenLabs") {
            SettingsRow(glyph: .waveform, title: "ElevenLabs") {
                if hasStoredAPIKey {
                    Text("Connected").hud(.label, Hud.Ink.ok)
                } else {
                    Link("Get a key", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                        .accessibilityLabel("Create an API key on ElevenLabs")
                }
            }
            SettingsRow(title: "Transcript language") {
                Picker("Transcript language", selection: $languageCode) {
                    Text("Automatic").tag(nil as String?)
                    Text("Turkish").tag("tr" as String?)
                    Text("English").tag("en" as String?)
                }.settingsMenu()
            }
            SettingsFieldRow {
                SecureField(
                    hasStoredAPIKey ? "Type to replace the saved key" : "ElevenLabs API key",
                    text: $apiKey
                )
                .textContentType(.password)
                .focused($apiKeyFocused)
                .settingsField(focused: apiKeyFocused)
                .accessibilityLabel("ElevenLabs API key")
                if isSavingTranscriptionSettings {
                    ProgressView().controlSize(.small).accessibilityLabel("Working")
                }
                Button("Verify and save", action: saveTranscriptionSettings)
                    .buttonStyle(HudButtonStyle(kind: .primary))
                    .disabled(isLoadingTranscriptionSettings || isSavingTranscriptionSettings
                        || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !hasStoredAPIKey))
                if hasStoredAPIKey {
                    Button(action: deleteTranscriptionAPIKey) {
                        Text("Remove").foregroundStyle(Hud.Ink.live)
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .disabled(isSavingTranscriptionSettings)
                    .accessibilityLabel("Remove connection")
                }
            }
            if let transcriptionSettingsMessage {
                SettingsNote(transcriptionSettingsMessage,
                             color: transcriptionSettingsFailed ? Hud.Ink.live : Hud.Ink.text3)
            }
        }
    }

    @ViewBuilder private var calendarContent: some View {
        calendarSettingsSection
        if let notificationService {
            MeetingNotificationSettingsView(service: notificationService)
        }
        if let calendars = appState.calendarIntegrationSnapshot?.calendars, !calendars.isEmpty {
            SettingsGroup("Watched calendars") {
                SettingsRow(glyph: .calendar, title: "All calendars") {
                    Toggle("All calendars", isOn: Binding(
                        get: { selectedCalendarIDs == nil },
                        set: { selectedCalendarIDs = $0 ? nil : calendars.map(\.id) }
                    )).settingsSwitch()
                }
                if selectedCalendarIDs != nil {
                    ForEach(calendars) { calendar in
                        SettingsRow(title: calendar.title) {
                            Toggle(calendar.title, isOn: Binding(
                                get: { selectedCalendarIDs?.contains(calendar.id) ?? true },
                                set: { selected in
                                    var ids = Set(selectedCalendarIDs ?? [])
                                    if selected { ids.insert(calendar.id) } else { ids.remove(calendar.id) }
                                    selectedCalendarIDs = ids.sorted()
                                }
                            )).settingsSwitch()
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Save selection", action: saveGeneralSettings)
                        .buttonStyle(HudButtonStyle(kind: .primary))
                        .disabled(isSavingGeneralSettings)
                        .accessibilityLabel("Save calendar selection")
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .padding(.top, Hud.Space.x2)
            }
        }
    }

    @ViewBuilder private var recordingContent: some View {
        SettingsGroup("Source") {
            SettingsRow(glyph: .mic, title: "Recording mic",
                        detail: availableMicrophones.isEmpty && !isLoadingMicrophones
                            ? Text("No mic connected") : nil) {
                HStack(spacing: Hud.Space.x2) {
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
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    .disabled(isLoadingMicrophones || availableMicrophones.isEmpty)

                    Button("Save", action: saveMicrophoneSelection)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                        .disabled(isLoadingMicrophones || isSavingMicrophone || availableMicrophones.isEmpty)
                }
            }
            if let microphoneSettingsMessage {
                SettingsNote(microphoneSettingsMessage,
                             color: microphoneSettingsFailed ? Hud.Ink.signal : Hud.Ink.text3)
            }
        }

        SettingsGroup("Permissions") {
            PermissionRow(
                source: .microphone,
                title: "Microphone",
                detail: "Your voice",
                status: appState.audioCapturePermissions.microphone,
                onRequestAccess: onRequestMicrophoneAccess,
                onOpenSystemSettings: onOpenSystemSettings
            )
            PermissionRow(
                source: .systemAudio,
                title: "System audio",
                detail: "Other people in the call",
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
        }

        SettingsGroup("Privacy guard") {
            SettingsRow(glyph: .shield, title: "Meet tab connection") {
                Text(browserAudioStatusText).hud(.label, browserAudioStatusColor)
            }
            ExpandRow(title: "Details", isExpanded: $showsPrivacyDetails)
                .accessibilityLabel("Advanced recording details")
            if showsPrivacyDetails {
                Group {
                    settingValue("Meeting mic", "Starts muted")
                    settingValue("Unknown mute state", "Not recorded")
                    settingValue("Manual control", "Notch or ⌥⌘M")
                    settingValue("Google Meet", "Connected call tab only")
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Hud.Motion.change, value: showsPrivacyDetails)
    }

    @ViewBuilder private var dataContent: some View {
        SettingsGroup("Data") {
            SettingsRow(glyph: .archive, title: "Data folder") {
                Button("Open", action: onOpenDataDirectory)
                    .accessibilityLabel("Open data folder")
            }
            SettingsRow(glyph: .window, title: "Setup guide") {
                Button("Open", action: resetOnboarding)
                    .accessibilityLabel("Open setup guide")
            }
            SettingsRow(glyph: .trash, title: "Delete all data",
                        detail: appState.requiresTerminationConfirmation
                            ? Text("Not while recording or processing") : nil) {
                Button(role: .destructive) {
                    showsDeleteAllDataConfirmation = true
                } label: {
                    Text("Delete…").foregroundStyle(Hud.Ink.live)
                }
                .disabled(appState.requiresTerminationConfirmation || isDeletingAllData)
                .accessibilityLabel("Delete all data…")
            }
            if let generalSettingsMessage {
                SettingsNote(generalSettingsMessage, color: generalSettingsFailed ? Hud.Ink.live : Hud.Ink.text3)
            }
        }
        SettingsGroup("About") {
            settingValue(
                "Version",
                "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")"
            )
        }
    }

    // MARK: Pieces

    private var browserAudioStatusText: LocalizedStringKey {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: "Unavailable"
        case .waitingForMeetTab: "Waiting for Meet tab"
        case .tabConnected: "Connected"
        case .recording: "Recording"
        }
    }

    private var browserAudioStatusColor: Color {
        switch appState.browserAudioConnectionStatus {
        case .unavailable: Hud.Ink.live
        case .waitingForMeetTab: Hud.Ink.text3
        case .tabConnected: Hud.Ink.ok
        case .recording: Hud.Ink.live
        }
    }

    private func settingValue(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        SettingsRow(title: title) {
            Text(value).hud(.label, Hud.Ink.text2).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func saveRow(
        message: String?,
        isFailure: Bool,
        buttonTitle: LocalizedStringKey,
        isBusy: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Hud.Space.x2) {
            if let message {
                Text(message)
                    .hud(.meta, isFailure ? Hud.Ink.live : Hud.Ink.text3)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView().controlSize(.small).accessibilityLabel("Working")
            }
            Button(buttonTitle, action: action)
                .buttonStyle(HudButtonStyle(kind: .primary))
                .disabled(isDisabled || isBusy)
        }
        .padding(.leading, Hud.Size.rowInset + Hud.Size.icon + Hud.Space.x3)
        .padding(.trailing, Hud.Size.rowInset)
        .padding(.top, Hud.Space.x2)
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
        SettingsGroup("Calendar") {
            SettingsRow(glyph: .calendar, title: "Show calendar meetings") {
                Toggle("Show calendar meetings", isOn: $isCalendarEnabled).settingsSwitch()
            }
            SettingsRow(glyph: .bell, title: "Meeting reminder") {
                Picker("Meeting reminder", selection: $reminderLeadTime) {
                    Text("5 min and 1 min before").tag(TimeInterval(5 * 60))
                    Text("10 min and 1 min before").tag(TimeInterval(10 * 60))
                    Text("15 min and 1 min before").tag(TimeInterval(15 * 60))
                }
                .settingsMenu()
                .disabled(!isCalendarEnabled)
            }
            SettingsRow(glyph: .people, title: "Connection") {
                HStack(spacing: Hud.Space.x2) {
                    Text(calendarStatusTitle).hud(.label, calendarStatusColor)
                    calendarPrimaryAction
                }
            }
            SettingsRow(title: "Accounts") {
                Button("Open", action: onOpenInternetAccounts)
                    .disabled(!isCalendarEnabled)
                    .accessibilityLabel("Open accounts")
            }

            if let snapshot = appState.calendarIntegrationSnapshot,
               appState.calendarAccessState == .authorized {
                ExpandRow(title: "Details", isExpanded: $showsCalendarDetails)
                    .accessibilityLabel("Connection details")
                if showsCalendarDetails {
                    CalendarIntegrationDetails(snapshot: snapshot)
                        .transition(.opacity)
                }
            }

            saveRow(
                message: generalSettingsMessage,
                isFailure: generalSettingsFailed,
                buttonTitle: "Save",
                isBusy: isSavingGeneralSettings,
                isDisabled: isLoadingGeneralSettings,
                action: saveGeneralSettings
            )
            .accessibilityLabel("Save calendar settings")
        }
        .animation(reduceMotion ? nil : Hud.Motion.change, value: showsCalendarDetails)
    }

    private var calendarStatusTitle: LocalizedStringKey {
        guard isCalendarEnabled else { return "Off" }
        if appState.isCalendarRefreshing { return "Refreshing" }
        return switch appState.calendarAccessState {
        case .authorized: "Connected"
        case .requesting: "Waiting for permission"
        case .denied, .restricted: "Permission denied"
        case .failed: "Connection error"
        case .notDetermined: "Not connected"
        }
    }

    private var calendarStatusColor: Color {
        guard isCalendarEnabled else { return Hud.Ink.text3 }
        return switch appState.calendarAccessState {
        case .authorized: Hud.Ink.ok
        case .requesting, .notDetermined: Hud.Ink.text3
        case .denied, .restricted: Hud.Ink.signal
        case .failed: Hud.Ink.live
        }
    }

    @ViewBuilder
    private var calendarPrimaryAction: some View {
        switch appState.calendarAccessState {
        case .authorized:
            Button("Refresh") { onRefreshCalendar() }
                .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
                .accessibilityLabel("Refresh now")
        case .denied, .restricted:
            Button("Open") { onOpenCalendarSettings() }
                .disabled(!isCalendarEnabled)
                .accessibilityLabel("Open calendar permission")
        case .requesting:
            EmptyView()
        case .failed:
            Button("Try again") { onRefreshCalendar() }
                .disabled(!isCalendarEnabled || appState.isCalendarRefreshing)
        case .notDetermined:
            Button("Allow") { onRequestCalendarAccess() }
                .disabled(!isCalendarEnabled)
                .accessibilityLabel("Allow calendar access")
        }
    }
}

// MARK: - Category tabs

/// Category switcher: icon and word per tab, a soft plate gliding to the selection.
private struct SettingsCategoryTabs: View {
    @Binding var selection: SettingsCategory
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsCategory.allCases) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(Hud.Motion.glide) { selection = item }
                } label: {
                    HStack(spacing: 7) {
                        CrenelIcon(item.glyph, size: Hud.Size.smallIcon)
                        Text(item.title).font(Hud.Style.label.font)
                    }
                    .foregroundStyle(isSelected ? Hud.Ink.text1 : Hud.Ink.text3)
                    .padding(.horizontal, Hud.Space.x3)
                    .frame(height: 26)
                    .background {
                        if isSelected {
                            Capsule().fill(Hud.Ink.selected)
                                .matchedGeometryEffect(id: "settings.tab", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(white: 1, opacity: 0.035)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings categories")
    }
}

/// A quiet row that shows or hides secondary rows below it.
private struct ExpandRow: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: Hud.Space.x2) {
                Text(title)
                CrenelIcon(.chevronDown, size: 10)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .hud(.meta, isHovering ? Hud.Ink.text2 : Hud.Ink.text3)
            .padding(.leading, Hud.Size.rowInset + Hud.Size.icon + Hud.Space.x3)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct CalendarIntegrationDetails: View {
    let snapshot: CalendarIntegrationSnapshot

    var body: some View {
        detail("Account sources", Text(sourceDescription))
        detail("Readable content", Text(readableContentDescription))
        detail("Online meetings", Text(snapshot.matchedMeetingCount, format: .number),
               color: snapshot.matchedMeetingCount == 0 ? Hud.Ink.text2 : Hud.Ink.ok)
        detail("Last refresh", Text(snapshot.refreshedAt, style: .relative))

        if !snapshot.hasGoogleAccount {
            SettingsNote("Google Calendar missing · add it in Internet Accounts", color: Hud.Ink.signal)
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: Text, color: Color = Hud.Ink.text2) -> some View {
        SettingsRow(title: title) {
            value.hud(.label, color).lineLimit(1).truncationMode(.middle)
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
        SettingsRow(glyph: source == .microphone ? .mic : .speaker, title: title, detail: detailText) {
            if status == .authorized {
                Text("Allowed").hud(.label, Hud.Ink.ok)
            } else {
                HStack(spacing: Hud.Space.x1) {
                    Button(actionTitle) {
                        status.requiresSystemSettings ? onOpenSystemSettings(source) : onRequestAccess()
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    if source == .systemAudio, status.requiresSystemSettings {
                        Menu {
                            Button("Ask again", action: onRequestAccess)
                            Button("Relaunch app", action: onRelaunchApplication)
                        } label: { CrenelIcon(.more, size: Hud.Size.smallIcon) }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .foregroundStyle(Hud.Ink.text3)
                        .frame(width: Hud.Size.control, height: Hud.Size.control)
                        .accessibilityLabel("System audio options")
                    }
                }
            }
        }
        .accessibilityValue(statusTitle)
    }

    private var detailText: Text {
        switch status {
        case .authorized: Text(detail)
        default: Text(statusTitle).foregroundStyle(statusColor)
        }
    }

    private var actionTitle: LocalizedStringKey {
        status.requiresSystemSettings ? "Open" : "Allow"
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
        case .authorized: Hud.Ink.ok
        case .verificationRequired, .notDetermined: Hud.Ink.signal
        case .denied, .restricted: Hud.Ink.live
        }
    }
}

private struct AccessibilityPermissionRow: View {
    let isGranted: Bool
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void

    var body: some View {
        SettingsRow(glyph: .accessibility, title: "Mic tracking",
                    detail: isGranted ? Text("Reads the meeting’s mute state")
                        : Text("Needs Accessibility").foregroundStyle(Hud.Ink.signal)) {
            if isGranted {
                Text("Allowed").hud(.label, Hud.Ink.ok)
            } else {
                HStack(spacing: Hud.Space.x1) {
                    Button("Allow", action: onRequestAccess)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                    Button("Open", action: onOpenSystemSettings)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                        .help("Accessibility settings")
                        .accessibilityLabel("Open Accessibility settings")
                }
            }
        }
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
    /// The Crenel icon for the category tab.
    var glyph: CrenelGlyph {
        switch self {
        case .general: .sliders
        case .dictation: .waveform
        case .tasks: .tasks
        case .ai: .sparkle
        case .calendar: .calendar
        case .recording: .mic
        case .data: .archive
        }
    }
}
