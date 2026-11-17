import SwiftUI

// The pages SettingsView owns the state of: General, Calendar, Recording, Data, and the
// ElevenLabs group of the AI page.

extension SettingsView {
    // MARK: General (`s-general`)

    @ViewBuilder var generalPage: some View {
        SettingsPageHeader(glyph: .sun, title: "General", sentence: "How Crenel starts and how long it keeps things.")

        SettingsGroup("Startup", index: 1) {
            SettingsRow(glyph: .sun, title: "Open at login",
                        detail: Text("Crenel sits in the notch from the moment you log in")) {
                SettingsToggle("Open at login", isOn: $launchAtLogin)
            }
        }

        SettingsGroup("Storage", index: 2) {
            SettingsRow(glyph: .archive, title: "Keep meetings",
                        detail: Text("Older meetings are deleted with their audio")) {
                HudSelect(selection: $retentionDays, options: [
                    (nil as Int?, "Forever"), (7 as Int?, "7 days"), (30 as Int?, "30 days"), (90 as Int?, "90 days")
                ])
                .accessibilityLabel("Keep meetings")
            }
        }

        HudActions {
            if isSavingGeneralSettings {
                HudSpinner()
            } else if let generalMessage {
                HudStatusWord(generalFailed ? .err : .ok, generalMessage)
            }
        } buttons: {
            HudButton("Save", key: "⌘S", kind: .primary, action: saveGeneralSettings)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isLoadingGeneralSettings || isSavingGeneralSettings)
                .accessibilityLabel("Save changes")
        }
        .settingsStagger(3)
    }

    // MARK: Calendar (`s-calendar-*`)

    private var calendarIsConnected: Bool {
        isCalendarEnabled && appState.calendarAccessState == .authorized
    }

    @ViewBuilder var calendarPage: some View {
        SettingsPageHeader(glyph: .calendar, title: "Calendar", sentence: "Meetings and their countdown in the notch.") {
            if calendarIsConnected, let snapshot = appState.calendarIntegrationSnapshot {
                SettingsReadoutWell(values: [
                    .init(digits: "\(snapshot.readableCalendarCount)", label: "calendars"),
                    .init(digits: "\(snapshot.scannedEventCount)", label: "events")
                ])
            }
        }

        SettingsGroup("Calendar", index: 1) {
            SettingsRow(glyph: .calendar, title: "Show meetings in the notch") {
                SettingsToggle("Show meetings in the notch", isOn: calendarBinding($isCalendarEnabled))
            }
            SettingsRow(glyph: .bell, title: "Heads-up") {
                HudSelect(selection: calendarBinding($reminderLeadTime), options: [
                    (TimeInterval(5 * 60), "5 min and 1 min before"),
                    (TimeInterval(10 * 60), "10 min and 1 min before"),
                    (TimeInterval(15 * 60), "15 min and 1 min before")
                ])
                .disabled(!isCalendarEnabled)
                .accessibilityLabel("Meeting reminder")
            }
            SettingsRow(glyph: .people, title: "Connection", detail: connectionDetail) {
                calendarConnection
            }
            SettingsRow(title: "Accounts", detail: Text(verbatim: accountsDetail)) {
                HudButton("Open", glyph: .link, size: .small, action: onOpenInternetAccounts)
                    .disabled(!isCalendarEnabled)
                    .accessibilityLabel("Open accounts")
            }
            if calendarIsConnected, let snapshot = appState.calendarIntegrationSnapshot, !snapshot.hasGoogleAccount {
                SettingsNote("Google Calendar missing · add it in Internet Accounts", status: .warn)
            }
            SettingsMessage(message: calendarMessage, failed: true)
        }

        if let notificationService {
            MeetingNotificationSettingsView(service: notificationService, index: 2)
        }

        if calendarIsConnected, let calendars = appState.calendarIntegrationSnapshot?.calendars, !calendars.isEmpty {
            SettingsGroup("Calendars", index: 3) {
                SettingsRow(glyph: .calendar, title: "All calendars") {
                    SettingsToggle("All calendars", isOn: Binding(
                        get: { selectedCalendarIDs == nil },
                        set: {
                            selectedCalendarIDs = $0 ? nil : calendars.map(\.id)
                            saveCalendarSettings()
                        }
                    ))
                }
                if selectedCalendarIDs != nil {
                    ForEach(calendars) { calendar in
                        SettingsRow(title: calendar.title) {
                            SettingsToggle(calendar.title, isOn: Binding(
                                get: { selectedCalendarIDs?.contains(calendar.id) ?? true },
                                set: { selected in
                                    var ids = Set(selectedCalendarIDs ?? [])
                                    if selected { ids.insert(calendar.id) } else { ids.remove(calendar.id) }
                                    selectedCalendarIDs = ids.sorted()
                                    saveCalendarSettings()
                                }
                            ))
                        }
                    }
                }
            }
        }
    }

    /// A calendar control: stores the value, then saves the page.
    private func calendarBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; saveCalendarSettings() }
        )
    }

    private var connectionDetail: Text? {
        guard calendarIsConnected, !appState.isCalendarRefreshing,
              let snapshot = appState.calendarIntegrationSnapshot else { return nil }
        return Text("Refreshed \(snapshot.refreshedAt, format: .relative(presentation: .numeric))")
    }

    private var accountsDetail: String {
        let sources = (appState.calendarIntegrationSnapshot?.sources ?? [])
            .map { "\($0.kind.title) (\($0.calendarCount))" }
            .joined(separator: " · ")
        guard calendarIsConnected, !sources.isEmpty else { return "From Internet Accounts" }
        return "\(sources), from Internet Accounts"
    }

    @ViewBuilder private var calendarConnection: some View {
        if !isCalendarEnabled {
            HudStatusWord(.dim, "Off")
        } else if appState.isCalendarRefreshing {
            HStack(spacing: 8) {
                HudSpinner()
                Text("Refreshing").hud(.label, Hud.Ink.ink2)
            }
        } else {
            switch appState.calendarAccessState {
            case .authorized:
                HudStatusWord(.ok, "Connected")
                HudButton("Refresh", size: .small, action: onRefreshCalendar)
                    .accessibilityLabel("Refresh now")
            case .notDetermined:
                HudStatusWord(.dim, "Not connected")
                HudButton("Allow", size: .small, action: onRequestCalendarAccess)
                    .accessibilityLabel("Allow calendar access")
            case .requesting:
                HudStatusWord(.dim, "Waiting for permission")
            case .denied, .restricted:
                HudStatusWord(.off(), "Access off")
                HudButton("Open", glyph: .link, size: .small, action: onOpenCalendarSettings)
                    .accessibilityLabel("Open calendar permission")
            case .failed:
                HudStatusWord(.err, "Connection error")
                HudButton("Try again", size: .small, action: onRefreshCalendar)
            }
        }
    }

    // MARK: Recording (`s-recording`, `s-recording-denied`)

    @ViewBuilder var recordingPage: some View {
        SettingsPageHeader(glyph: .mic, title: "Recording", sentence: "What Crenel hears, and what it never records.") {
            recordingReadout
        }

        SettingsGroup("Source", index: 1) {
            SettingsRow(glyph: .mic, title: "Microphone",
                        detail: availableMicrophones.isEmpty && !isLoadingMicrophones
                            ? Text("No mic connected") : nil) {
                if isSavingMicrophone { HudSpinner() }
                HudSelect(selection: Binding(
                    get: { selectedMicrophoneID },
                    set: { selectedMicrophoneID = $0; saveMicrophoneSelection() }
                ), options: microphoneOptions)
                    .disabled(isLoadingMicrophones || isSavingMicrophone || availableMicrophones.isEmpty)
                    .accessibilityLabel("Recording mic")
            }
            SettingsRow(title: "Level", detail: Text(liveMicLevel == nil ? "Moves while Crenel is listening" : "Live")) {
                HudCapacityScale(level: liveMicLevel ?? 0)
                    .frame(width: 232)
            }
            SettingsMessage(message: microphoneSettingsMessage, failed: microphoneSettingsFailed)
        }

        SettingsGroup("Permissions", index: 2) {
            SettingsPermissionRow(
                source: .microphone,
                title: "Microphone",
                detail: "Your voice",
                status: appState.audioCapturePermissions.microphone,
                onRequestAccess: onRequestMicrophoneAccess,
                onOpenSystemSettings: onOpenSystemSettings
            )
            SettingsPermissionRow(
                source: .systemAudio,
                title: "System audio",
                detail: "Everyone else on the call",
                status: appState.audioCapturePermissions.systemAudio,
                onRequestAccess: onRequestSystemAudioAccess,
                onOpenSystemSettings: onOpenSystemSettings,
                onRelaunchApplication: onRelaunchApplication
            )
            SettingsRow(glyph: .accessibility, title: "Mute tracking",
                        detail: appState.accessibilityPermissionGranted
                            ? Text("Reads mute in Zoom and Meet") : Text("Needs Accessibility")) {
                if appState.accessibilityPermissionGranted {
                    HudStatusWord(.ok, "Allowed")
                } else {
                    HudStatusWord(.off(), "Off")
                    HudIconButton(.link, framed: true, small: true, help: "Open Accessibility settings",
                                  action: onOpenAccessibilitySettings)
                    HudButton("Allow", size: .small, action: onRequestAccessibilityAccess)
                        .accessibilityLabel("Allow Accessibility")
                }
            }
        }

        SettingsGroup("Privacy guard", index: 3) {
            SettingsRow(glyph: .shield, title: "Meet tab") {
                switch appState.browserAudioConnectionStatus {
                case .unavailable: HudStatusWord(.dim, "Unavailable")
                case .waitingForMeetTab: HudStatusWord(.dim, "Waiting for a call tab")
                case .tabConnected: HudStatusWord(.ok, "Connected")
                case .recording:
                    HStack(spacing: 8) {
                        HudLamp(.red, form: .dot, loop: .pulse)
                        Text("Recording").hud(.label, Hud.Ink.ink2)
                    }
                }
            }
            SettingsExpand(title: "How your mic is handled", isExpanded: $showsPrivacyDetails)
                .accessibilityLabel("Advanced recording details")
            if showsPrivacyDetails {
                Group {
                    SettingsRow(title: "Your mic") { SettingsValue("Starts muted") }
                    SettingsRow(title: "Mute state unknown") { SettingsValue("Not recorded") }
                    SettingsRow(title: "By hand") { SettingsValue("Notch or ⌥⌘M") }
                    SettingsRow(title: "Google Meet") { SettingsValue("Connected call tab only") }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Hud.Motion.change, value: showsPrivacyDetails)
    }

    @ViewBuilder private var recordingReadout: some View {
        let permissions = appState.audioCapturePermissions
        if permissions.microphone != .authorized {
            HudStatusWord(.off(blocking: true), "Microphone off")
        } else if permissions.systemAudio != .authorized {
            HudStatusWord(.off(blocking: true), "Call audio off")
        } else if !appState.accessibilityPermissionGranted {
            HudStatusWord(.off(), "Mute tracking off")
        } else {
            HudStatusWord(.ok, "All allowed")
        }
    }

    private var microphoneOptions: [(value: String?, title: String)] {
        var options: [(value: String?, title: String)] = [(nil, "System default")]
        options += availableMicrophones.map { ($0.id as String?, $0.isSystemDefault ? "\($0.name) — default" : $0.name) }
        if let selectedMicrophoneID, !availableMicrophones.contains(where: { $0.id == selectedMicrophoneID }) {
            options.append((selectedMicrophoneID, "Selected mic not connected"))
        }
        return options
    }

    /// The mic level, only while Crenel is already listening (a recording or dictation).
    private var liveMicLevel: Double? {
        if appState.meetingFlow.isRecording {
            return Double(appState.recordingCaptureStatus.microphone.level)
        }
        if case .listening(_, let level) = appState.dictationState {
            return Double(level)
        }
        return nil
    }

    // MARK: Data (`s-data`, `s-data-busy`)

    @ViewBuilder var dataPage: some View {
        SettingsPageHeader(glyph: .archive, title: "Data", sentence: "Everything stays in one folder on this Mac.") {
            SettingsReadoutWell(values: dataReadout)
        }

        SettingsGroup("Folder", index: 1) {
            SettingsRow(glyph: .archive, title: "Data folder",
                        detail: dataFolder.map { Text(verbatim: $0.path) }) {
                HudButton("Show in Finder", size: .small, action: onOpenDataDirectory)
                    .accessibilityLabel("Open data folder")
            }
            SettingsRow(glyph: .window, title: "Setup", detail: Text("Walk through permissions again")) {
                HudButton("Run again", size: .small, action: resetOnboarding)
                    .accessibilityLabel("Open setup guide")
            }
        }

        SettingsGroup("Danger zone", index: 2) {
            SettingsRow(glyph: .trash, title: "Delete all data",
                        detail: appState.requiresTerminationConfirmation
                            ? Text("Not while recording or processing")
                            : Text("Meetings, audio, tasks on this Mac, settings and keys")) {
                if isDeletingAllData { HudSpinner() }
                HudButton("Delete…", kind: .danger, size: .small) {
                    showsDeleteAllDataConfirmation = true
                }
                .disabled(appState.requiresTerminationConfirmation || isDeletingAllData)
                .accessibilityLabel("Delete all data…")
            }
            SettingsMessage(message: dataMessage, failed: dataFailed)
        }

        HStack(spacing: 12) {
            HudAppTile(size: 22)
            Text(verbatim: versionLine).hud(.meta)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .settingsStagger(3)
        .accessibilityElement(children: .combine)
    }

    private var dataReadout: [SettingsReadoutWell.Value] {
        var values: [SettingsReadoutWell.Value] = []
        if let dataFolder {
            let size = dataFolder.readout
            values.append(.init(digits: size.digits, unit: size.unit, label: "on disk"))
        }
        values.append(.init(digits: "\(appState.storedMeetings.count)", label: "meetings"))
        return values
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String else { return "Crenel \(version)" }
        return "Crenel \(version) · build \(build)"
    }

    // MARK: Voice (AI page)

    /// Settings › AI › Voice: who transcribes meetings, and that provider's key.
    @ViewBuilder var voiceGroup: some View {
        let engine = crenel.preferences.meetingProcessing.transcription
        SettingsGroup("Voice", index: 2) {
            SettingsRow(glyph: .waveform, title: "Provider", detail: voiceDetail(engine)) {
                if engine == .elevenLabs, !isLoadingTranscriptionSettings {
                    if hasStoredAPIKey { HudStatusWord(.ok, "Connected") } else { HudStatusWord(.warn, "Needs a key") }
                }
                HudSelect(
                    selection: Binding(
                        get: { engine == .elevenLabs ? SettingsVoiceProvider.elevenLabs : .onDevice },
                        set: { choice in
                            guard let engine = choice.engine else { return }
                            crenel.preferences.meetingProcessing.transcription = engine
                            crenel.save(crenelSettings)
                        }
                    ),
                    options: SettingsVoiceProvider.allCases.map { ($0, $0.title) },
                    disabled: Set(SettingsVoiceProvider.allCases.filter { $0.engine == nil })
                )
                .accessibilityLabel("Voice provider")
            }
            if engine == .elevenLabs {
                SettingsFieldRow {
                    SecureField("", text: $apiKey,
                                prompt: Text(hasStoredAPIKey ? "Type to replace the saved ElevenLabs key" : "ElevenLabs API key")
                                    .foregroundStyle(Hud.Ink.ink3))
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                        .hud(.body)
                        .focused($apiKeyFocused)
                        .hudField(isFocused: apiKeyFocused)
                        .onSubmit(saveTranscriptionSettings)
                        .accessibilityLabel("ElevenLabs API key")
                    if isSavingTranscriptionSettings { HudSpinner() }
                    HudButton("Verify and save", action: saveTranscriptionSettings)
                        .disabled(isLoadingTranscriptionSettings || isSavingTranscriptionSettings
                            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Checks Speech-to-Text access before saving")
                    if hasStoredAPIKey {
                        HudButton("Remove", kind: .danger, action: deleteTranscriptionAPIKey)
                            .disabled(isSavingTranscriptionSettings)
                            .accessibilityLabel("Remove ElevenLabs key")
                    } else {
                        Link(destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!) {
                            HudButtonLabel("Get a key", glyph: .link)
                        }
                        .buttonStyle(HudButtonStyle(kind: .secondary))
                        .accessibilityLabel("Create an API key on ElevenLabs")
                    }
                }
                SettingsMessage(message: transcriptionSettingsMessage, failed: transcriptionSettingsFailed)
            }
            SettingsRow(title: "Transcript language") {
                HudSelect(
                    selection: Binding(
                        get: { languageCode },
                        set: { code in
                            languageCode = code
                            // Saved as it is chosen, like every other setting; no key involved.
                            Task { _ = await onSaveTranscriptionSettings(code, nil) }
                        }
                    ),
                    options: [(nil as String?, "Automatic"), ("tr" as String?, "Turkish"), ("en" as String?, "English")]
                )
                .accessibilityLabel("Transcript language")
            }
        }
    }

    private func voiceDetail(_ engine: MeetingTranscriptionEngine) -> Text {
        switch engine {
        case .elevenLabs: Text("Meeting transcripts with speaker names · billed to you")
        case .onDevice: Text("Apple Speech · free, audio stays on this Mac")
        }
    }
}

/// The voice providers offered on the AI page. Two of them are announced, not built.
enum SettingsVoiceProvider: CaseIterable, Hashable {
    case elevenLabs, onDevice, openAI, deepgram

    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .onDevice: "On this Mac (Apple Speech)"
        case .openAI: "OpenAI · coming soon"
        case .deepgram: "Deepgram · coming soon"
        }
    }

    /// nil: not available yet.
    var engine: MeetingTranscriptionEngine? {
        switch self {
        case .elevenLabs: .elevenLabs
        case .onDevice: .onDevice
        case .openAI, .deepgram: nil
        }
    }
}

// MARK: - Permission row

/// Microphone and system audio: the state as a lamp or an octagon, then the way to
/// change it at the trailing edge.
struct SettingsPermissionRow: View {
    let source: AudioSourceKind
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: AudioCapturePermissionStatus
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: (AudioSourceKind) -> Void
    var onRelaunchApplication: () -> Void = {}

    var body: some View {
        SettingsRow(glyph: source == .microphone ? .mic : .speaker, title: title, detail: Text(detail)) {
            switch status {
            case .authorized:
                HudStatusWord(.ok, "Allowed")
            case .notDetermined:
                HudStatusWord(.off(), "Off")
                HudButton("Allow", size: .small, action: onRequestAccess)
            case .verificationRequired:
                HudStatusWord(.warn, "Needs checking")
                HudButton("Allow", size: .small, action: onRequestAccess)
            case .denied, .restricted:
                HudStatusWord(.off(blocking: true), status == .denied ? "Denied" : "Restricted")
                if source == .systemAudio {
                    Menu {
                        Button("Ask again", action: onRequestAccess)
                        Button("Relaunch app", action: onRelaunchApplication)
                    } label: {
                        HudIcon(.more, size: 14)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(HudButtonStyle(kind: .iconFramed, size: .small))
                    .fixedSize()
                    .help("More")
                    .accessibilityLabel("System audio options")
                }
                HudButton("Open", glyph: .link, size: .small) { onOpenSystemSettings(source) }
            }
        }
        .accessibilityValue(statusTitle)
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
}
