import SwiftUI

/// Settings, hosted to the right of the app sidebar (`tpl-desktop`, `s-*`): its own
/// title and search row, a second rail with a lamp per section, and the page.
struct SettingsView: View {
    @Environment(\.crenelActions) var appActions
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion

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
    /// Where the data lives and how much of it there is; nil measures the real folder.
    let onLoadDataFolder: (() async -> SettingsDataFolder?)?

    var notificationService: MeetingNotificationService?
    var openAISettings = OpenAISettingsActions()
    var crenelSettings = CrenelSettingsActions()

    @StateObject var crenel = CrenelSettingsModel()

    @State var category = SettingsCategory.general
    @State var query = ""
    @State var hoveredResult: AnyHashable?
    @Namespace var resultSpace

    // General and Calendar share one stored document.
    @State var savedGeneral = GeneralSettingsSnapshot.default
    @State var reminderLeadTime: TimeInterval = 10 * 60
    @State var isCalendarEnabled = true
    @State var selectedCalendarIDs: [String]?
    @State var launchAtLogin = false
    @State var retentionDays: Int?
    @State var isLoadingGeneralSettings = true
    @State var isSavingGeneralSettings = false
    @State var generalMessage: String?
    @State var generalFailed = false
    @State var calendarMessage: String?

    @State var isDeletingAllData = false
    @State var showsDeleteAllDataConfirmation = false
    @State var dataMessage: String?
    @State var dataFailed = false
    @State var dataFolder: SettingsDataFolder?

    @State var availableMicrophones: [MicrophoneDevice] = []
    @State var selectedMicrophoneID: String?
    @State var isLoadingMicrophones = true
    @State var isSavingMicrophone = false
    @State var microphoneSettingsMessage: String?
    @State var microphoneSettingsFailed = false
    @State var showsPrivacyDetails = false

    @State var languageCode: String?
    @State var apiKey = ""
    @FocusState var apiKeyFocused: Bool
    @State var hasStoredAPIKey = false
    @State var isLoadingTranscriptionSettings = true
    @State var isSavingTranscriptionSettings = false
    @State var transcriptionSettingsMessage: String?
    @State var transcriptionSettingsFailed = false

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
        initialCategory: SettingsCategory = .general,
        onLoadDataFolder: (() async -> SettingsDataFolder?)? = nil,
        initialQuery: String = ""
    ) {
        _category = State(initialValue: initialCategory)
        _query = State(initialValue: initialQuery)
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
        self.onLoadDataFolder = onLoadDataFolder
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(alignment: .top, spacing: 0) {
                SettingsRail(status: railStatus, selection: Binding(
                    get: { category },
                    set: { category = $0; query = "" }
                ))
                .frame(width: Hud.Window.settingsRailWidth)

                ScrollView {
                    Group {
                        if trimmedQuery.isEmpty {
                            SettingsPage { page }
                                .id(category)
                        } else {
                            searchResults
                        }
                    }
                    .frame(maxWidth: SettingsLayout.contentWidth, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.trailing, 32)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Hud.Layer.window)
        .hudSurface(Hud.Layer.window)
        .foregroundStyle(Hud.Ink.ink1)
        .font(Hud.Style.body.font)
        .tint(Hud.Ink.ink2)
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
                await crenel.load(crenelSettings)
                await loadDataFolder()
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

    // MARK: Chrome

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Settings").hud(.hero).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HudSearchField(text: $query, prompt: "Search settings")
                .frame(width: 220)
                .accessibilityLabel("Search settings")
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .frame(height: Hud.Window.toolbarHeight)
    }

    @ViewBuilder private var page: some View {
        switch category {
        case .general: generalPage
        case .dictation: DictationSettingsView(actions: crenelSettings, model: crenel)
        case .tasks: TaskStorageSettingsView(actions: crenelSettings, model: crenel)
        case .ai:
            AgentSettingsView(actions: crenelSettings, openAI: openAISettings, model: crenel) {
                voiceGroup
            }
        case .calendar: calendarPage
        case .recording: recordingPage
        case .data: dataPage
        }
    }

    /// The real state of each section, for the lamp at the end of its rail item.
    private func railStatus(_ item: SettingsCategory) -> SettingsRailStatus {
        switch item {
        case .general, .data:
            return .none
        case .dictation:
            switch appState.dictationAvailability {
            case .ready: return .ready
            case .needsInputMonitoring: return .accessOff(blocking: false)
            case .disabled: return .idle
            }
        case .tasks:
            switch appState.taskStorageStatus {
            case .reminders: return .ready
            case .localNotConnected, .localByChoice: return .idle
            case .localDenied: return .accessOff(blocking: false)
            case .localAfterError: return .failed
            }
        case .ai:
            return crenel.preferences.agent.provider == .off ? .idle : .ready
        case .calendar:
            guard isCalendarEnabled else { return .idle }
            switch appState.calendarAccessState {
            case .authorized: return .ready
            case .notDetermined, .requesting: return .idle
            case .denied, .restricted: return .accessOff(blocking: false)
            case .failed: return .failed
            }
        case .recording:
            let permissions = appState.audioCapturePermissions
            if permissions.microphone != .authorized || permissions.systemAudio != .authorized {
                return .accessOff(blocking: true)
            }
            return appState.accessibilityPermissionGranted ? .ready : .accessOff(blocking: false)
        }
    }

    // MARK: Search

    /// Rows whose title matches, across every section; choosing one opens its page.
    private var searchResults: some View {
        let matches = SettingsCategory.allCases.flatMap { item in
            item.searchTitles
                .filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
                .map { (category: item, title: $0) }
        }
        return VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
            if matches.isEmpty {
                HStack(spacing: 12) {
                    HudIcon(.search, size: 16).foregroundStyle(Hud.Ink.ink3)
                    Text("No setting matches “\(trimmedQuery)”").hud(.body, Hud.Ink.ink2)
                }
                .padding(.horizontal, SettingsLayout.rowInset)
                .frame(height: Hud.Row.oneLine)
                .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HudGroupHeader(title: "Results", count: matches.count)
                    ForEach(matches, id: \.title) { match in
                        Button {
                            category = match.category
                            query = ""
                        } label: {
                            HStack(spacing: 12) {
                                HudIcon(match.category.hudGlyph, size: 16).foregroundStyle(Hud.Ink.ink3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: match.title).hud(.body)
                                    Text(match.category.title).hud(.meta)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                HudIcon(.chevronRight, size: 12).foregroundStyle(Hud.Ink.ink4)
                            }
                            .lineLimit(1)
                            .padding(.horizontal, SettingsLayout.rowInset)
                            .frame(height: SettingsLayout.rowHeight)
                            .hudGlide(AnyHashable(match.title), hovered: $hoveredResult, in: resultSpace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudGroupCard()
                .padding(.top, 4)
            }
        }
    }

    // MARK: Loading

    func apply(_ snapshot: GeneralSettingsSnapshot) {
        savedGeneral = snapshot
        reminderLeadTime = snapshot.reminderLeadTime
        isCalendarEnabled = snapshot.isCalendarEnabled
        selectedCalendarIDs = snapshot.selectedCalendarIDs
        launchAtLogin = snapshot.launchAtLogin
        retentionDays = snapshot.meetingRetentionPolicy.days
        isLoadingGeneralSettings = false
    }

    func apply(_ snapshot: TranscriptionSettingsSnapshot) {
        languageCode = snapshot.languageCode
        hasStoredAPIKey = snapshot.hasStoredAPIKey
        isLoadingTranscriptionSettings = false
    }

    func apply(_ snapshot: MicrophoneSettingsSnapshot) {
        availableMicrophones = snapshot.devices
        selectedMicrophoneID = snapshot.selectedDeviceID
        isLoadingMicrophones = false
        if !snapshot.selectedDeviceIsAvailable {
            microphoneSettingsMessage = "Selected mic isn’t connected; recordings will use the system default."
            microphoneSettingsFailed = true
        }
    }

    func loadDataFolder() async {
        if let onLoadDataFolder {
            dataFolder = await onLoadDataFolder()
        } else {
            dataFolder = await SettingsDataFolder.measure()
        }
    }

    // MARK: Saving

    /// General › Save: what the page shows, with the calendar values already stored.
    func saveGeneralSettings() {
        isSavingGeneralSettings = true
        generalMessage = nil
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
            switch await onSaveGeneralSettings(snapshot) {
            case .succeeded(let message):
                savedGeneral = snapshot
                generalMessage = message ?? "Saved"
                generalFailed = false
            case .failed(let message):
                generalMessage = message
                generalFailed = true
            }
            isSavingGeneralSettings = false
        }
    }

    /// Calendar switches save as they change. They leave unsaved General edits alone.
    func saveCalendarSettings() {
        let snapshot = GeneralSettingsSnapshot(
            reminderLeadTime: reminderLeadTime,
            isCalendarEnabled: isCalendarEnabled,
            launchAtLogin: savedGeneral.launchAtLogin,
            meetingRetentionPolicy: savedGeneral.meetingRetentionPolicy,
            selectedCalendarIDs: selectedCalendarIDs
        )
        Task {
            switch await onSaveGeneralSettings(snapshot) {
            case .succeeded:
                savedGeneral = snapshot
                calendarMessage = nil
            case .failed(let message):
                calendarMessage = message
            }
        }
    }

    func saveMicrophoneSelection() {
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

    func saveTranscriptionSettings() {
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

    func deleteTranscriptionAPIKey() {
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

    func resetOnboarding() {
        Task { handleDataResult(await onResetOnboarding(), fallback: nil) }
    }

    func deleteAllData() {
        isDeletingAllData = true
        dataMessage = nil
        Task {
            handleDataResult(await onDeleteAllData(), fallback: "Saved")
            isDeletingAllData = false
            apply(await onLoadGeneralSettings())
            apply(await onLoadMicrophoneSettings())
            apply(await onLoadTranscriptionSettings())
            await crenel.load(crenelSettings)
            await loadDataFolder()
        }
    }

    private func handleDataResult(_ result: SettingsActionResult, fallback: String?) {
        switch result {
        case .succeeded(let message):
            dataMessage = message ?? fallback
            dataFailed = false
        case .failed(let message):
            dataMessage = message
            dataFailed = true
        }
    }
}

// MARK: - Sections

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
    /// Legacy icon.
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
    /// The icon of the section in the rail and on its page header.
    var hudGlyph: HudGlyph {
        switch self {
        case .general: .sun
        case .dictation: .waveform
        case .tasks: .queue
        case .ai: .spark
        case .calendar: .calendar
        case .recording: .mic
        case .data: .archive
        }
    }
    /// Row titles of the section, for search.
    var searchTitles: [String] {
        switch self {
        case .general: ["Open at login", "Keep meetings"]
        case .dictation: ["Dictation", "Input Monitoring", "Shortcut", "Mode", "Double-tap for hands-free",
                          "Language", "Speech model", "Words to know"]
        case .tasks: ["Keep tasks in", "Reminders"]
        case .ai: ["Who writes", "Clean up dictation", "Voice commands on selected text", "Anthropic",
                   "Transcript", "Notes", "OpenAI", "ElevenLabs", "Transcript language"]
        case .calendar: ["Show meetings in the notch", "Heads-up", "Connection", "Accounts",
                         "Meeting notifications", "Calendars"]
        case .recording: ["Microphone", "Level", "Microphone permission", "System audio", "Mute tracking",
                          "Meet tab", "How your mic is handled"]
        case .data: ["Data folder", "Setup", "Delete all data", "Version"]
        }
    }
}

// MARK: - Data folder

/// The data folder as the Data page shows it.
struct SettingsDataFolder: Equatable, Sendable {
    /// Display path, home abbreviated to `~`.
    var path: String
    var bytes: Int64

    /// The size as segment digits and a unit: "2.1" GB, "482" MB.
    var readout: (digits: String, unit: String) {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes >= 1000 {
            return (String(format: "%.1f", megabytes / 1000), "GB")
        }
        return (String(Int(megabytes.rounded())), "MB")
    }

    /// Measures the real folder off the main thread. Tests get nothing: they must not
    /// read the user's data.
    static func measure() async -> SettingsDataFolder? {
        guard !SettingsLayout.isTesting else { return nil }
        return await Task.detached(priority: .utility) { measureNow() }.value
    }

    private static func measureNow() -> SettingsDataFolder? {
        guard let root = try? AppStorageLayout.applicationSupport().root else { return nil }
        var bytes: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) {
            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return SettingsDataFolder(path: (root.path as NSString).abbreviatingWithTildeInPath, bytes: bytes)
    }
}
