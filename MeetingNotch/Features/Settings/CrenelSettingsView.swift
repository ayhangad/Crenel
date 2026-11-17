import SwiftUI

/// Data and actions the Crenel settings screens need. Views never touch Keychain,
/// EventKit or the event tap directly.
struct CrenelSettingsActions {
    var load: () async -> CrenelPreferences = { .default }
    var save: (CrenelPreferences) async -> SettingsActionResult = { _ in .succeeded() }
    var hasAnthropicKey: () async -> Bool = { false }
    var saveAnthropicKey: (String) async -> SettingsActionResult = { _ in .failed(message: "Unavailable.") }
    var deleteAnthropicKey: () async -> SettingsActionResult = { .succeeded() }
    var onDeviceModelStatus: () async -> String? = { nil }
}

/// Shared load/edit/save state for the Dictation, Tasks and AI pages. Every change is
/// saved as it is made.
@MainActor
final class CrenelSettingsModel: ObservableObject {
    @Published var preferences = CrenelPreferences.default
    @Published var isLoaded = false
    @Published var message: String?
    @Published var failed = false

    func load(_ actions: CrenelSettingsActions) async {
        preferences = await actions.load()
        isLoaded = true
    }

    func save(_ actions: CrenelSettingsActions) {
        let snapshot = preferences
        Task {
            switch await actions.save(snapshot) {
            case .succeeded(let message):
                self.message = message
                self.failed = false
            case .failed(let message):
                self.message = message
                self.failed = true
            }
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<CrenelPreferences, Value>, actions: CrenelSettingsActions) -> Binding<Value> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { self.preferences[keyPath: keyPath] = $0; self.save(actions) }
        )
    }
}

// MARK: - Dictation

/// Settings › Dictation (`s-dictation`, `s-dictation-perms`).
struct DictationSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let actions: CrenelSettingsActions
    @ObservedObject var model: CrenelSettingsModel
    @State private var newTerm = ""
    @State private var showsWords = false

    var body: some View {
        SettingsPageHeader(glyph: .waveform, title: "Dictation", sentence: "The key you hold and how it listens.") {
            switch appState.dictationAvailability {
            case .ready: HudStatusWord(.ok, "Ready")
            case .needsInputMonitoring: HudStatusWord(.off(), "Needs access")
            case .disabled: HudStatusWord(.dim, "Off")
            }
        }

        SettingsGroup("Dictation", index: 1) {
            SettingsRow(glyph: .waveform, title: "Dictation",
                        detail: Text("Hold a key anywhere to type with your voice")) {
                SettingsToggle("Dictation", isOn: binding(\.dictationEnabled))
            }
            permissionRows
            SettingsRow(glyph: .keyboard, title: "Shortcut",
                        detail: model.preferences.dictationTrigger.trigger == .fnHold
                            ? Text("⌃Space still switches input languages") : nil) {
                HudSelect(selection: binding(\.dictationTrigger.trigger), options: [
                    (DictationTrigger.fnHold, "Hold Fn (🌐)"),
                    (DictationTrigger.rightOptionHold, "Hold right ⌥"),
                    (DictationTrigger.rightCommandHold, "Hold right ⌘")
                ])
                .accessibilityLabel("Shortcut")
            }
            SettingsRow(title: "Mode") {
                HudSelect(selection: binding(\.dictationTrigger.mode), options: [
                    (DictationTriggerMode.holdToTalk, "Hold to talk"),
                    (DictationTriggerMode.toggle, "Press to start, press to stop")
                ])
                .accessibilityLabel("Mode")
            }
            SettingsRow(title: "Double-tap for hands-free") {
                SettingsToggle("Double-tap for hands-free", isOn: binding(\.dictationTrigger.allowsDoubleTapHandsFree))
            }
            SettingsRow(title: "Language") {
                HudSelect(selection: binding(\.dictationLanguage), options: [
                    (DictationLanguage.automatic, "System language"),
                    (DictationLanguage.turkish, "Turkish"),
                    (DictationLanguage.english, "English")
                ])
                .accessibilityLabel("Language")
            }
        }

        SettingsGroup("Speech model", index: 2) {
            SettingsRow(glyph: .shield, title: "On this Mac", detail: Text("Nothing you say leaves the Mac")) {
                HudButton("Download", glyph: .chevronDown, size: .small, action: crenelActions.dictation.prepareSpeechAssets)
                    .accessibilityLabel("Download model")
            }
            SettingsRow(title: "Words to know", detail: Text(verbatim: wordsDetail)) {
                HudButton(showsWords ? "Done" : "Edit", trailingGlyph: showsWords ? nil : .chevronDown, size: .small) {
                    showsWords.toggle()
                }
                .accessibilityLabel(showsWords ? "Done editing words" : "Edit words to know")
            }
            if showsWords {
                SettingsFieldRow {
                    HudTextField(text: $newTerm, prompt: "Crenel, SwiftUI, Ayhan", onSubmit: addTerm)
                        .accessibilityLabel("New dictionary term")
                    HudButton("Add", glyph: .plus, action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.preferences.dictationVocabulary.isEmpty {
                    SettingsWordChips(items: model.preferences.dictationVocabulary) { term in
                        model.preferences.dictationVocabulary.removeAll { $0 == term }
                        model.save(actions)
                    }
                    .padding(.leading, SettingsLayout.textInset)
                    .padding(.trailing, SettingsLayout.rowInset)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
            SettingsMessage(message: model.message, failed: model.failed)
        }
        .animation(reduceMotion ? nil : Hud.Motion.change, value: showsWords)
    }

    private var wordsDetail: String {
        let words = model.preferences.dictationVocabulary
        return words.isEmpty ? "Names and terms to spell right" : words.joined(separator: ", ")
    }

    @ViewBuilder
    private var permissionRows: some View {
        switch appState.dictationAvailability {
        case .needsInputMonitoring:
            SettingsRow(glyph: .keyboard, title: "Input Monitoring", detail: Text("Needed for the shortcut")) {
                HudStatusWord(.off(), "Off")
                HudButton("Allow", size: .small, action: crenelActions.dictation.requestInputMonitoring)
                    .accessibilityLabel("Allow Input Monitoring")
            }
        case .ready, .disabled:
            EmptyView()
        }
        if !appState.accessibilityPermissionGranted {
            SettingsNote("Without Accessibility, text goes to the clipboard.")
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !model.preferences.dictationVocabulary.contains(term) else { return }
        model.preferences.dictationVocabulary.append(String(term.prefix(60)))
        newTerm = ""
        model.save(actions)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CrenelPreferences, Value>) -> Binding<Value> {
        model.binding(keyPath, actions: actions)
    }
}

// MARK: - AI

/// Settings › AI (`s-ai-*`): who writes, the Anthropic key, what meetings use, then the
/// OpenAI key and whatever the host adds after it (ElevenLabs).
struct AgentSettingsView<Extra: View>: View {
    let actions: CrenelSettingsActions
    let openAI: OpenAISettingsActions
    @ObservedObject var model: CrenelSettingsModel
    @ViewBuilder var extra: () -> Extra

    @State private var anthropicKey = ""
    @State private var hasAnthropicKey = false
    @State private var isSavingKey = false
    @State private var keyMessage: String?
    @State private var keyFailed = false
    @State private var onDeviceStatus: String?
    /// nil while checking.
    @State private var openAIConnected: Bool?
    /// Whether the selected command-line tool is installed (nil while checking).
    @State private var toolInstalled: Bool?
    @FocusState private var keyFocused: Bool

    private var provider: AgentProviderKind { model.preferences.agent.provider }

    var body: some View {
        SettingsPageHeader(glyph: .spark, title: "AI", sentence: "Who writes your notes and cleans up dictation.") {
            chain
        }

        SettingsGroup("Model", index: 1) {
            SettingsRow(glyph: .spark, title: "Who writes", detail: providerDetail) {
                providerStatus
                HudSelect(selection: binding(\.agent.provider), options: [
                    (AgentProviderKind.automatic, "Automatic"),
                    (AgentProviderKind.onDevice, "On this Mac (Apple)"),
                    (AgentProviderKind.openAI, "OpenAI (your key)"),
                    (AgentProviderKind.anthropic, "Anthropic (your key)"),
                    (AgentProviderKind.claudeCode, "Claude Code (this Mac)"),
                    (AgentProviderKind.codex, "Codex (this Mac)"),
                    (AgentProviderKind.off, "Off")
                ])
                .accessibilityLabel("Model")
            }
            SettingsRow(title: "Clean up dictation") {
                SettingsToggle("Clean up dictation", isOn: binding(\.agent.cleanupEnabled))
            }
            SettingsRow(title: "Voice commands on selected text") {
                SettingsToggle("Voice commands on selected text", isOn: binding(\.agent.commandModeEnabled))
            }
            if provider == .openAI {
                SettingsFieldRow {
                    HudTextField(text: optionalBinding(\.agent.openAIModelID), prompt: "OpenAI model ID (empty: default)")
                        .accessibilityLabel("OpenAI model ID")
                }
            }
            SettingsMessage(message: model.message, failed: model.failed)
        }

        if provider == .anthropic || provider == .automatic {
            SettingsGroup("Anthropic", index: 2) {
                SettingsRow(glyph: .spark, title: "Anthropic",
                            detail: Text("Notes and dictation clean-up · billed to you")) {
                    if hasAnthropicKey {
                        HudStatusWord(.ok, "Connected")
                        HudButton("Remove", kind: .danger, size: .small, action: removeAnthropicKey)
                            .disabled(isSavingKey)
                            .accessibilityLabel("Remove Anthropic key")
                    } else {
                        HudStatusWord(.dim, "No key")
                    }
                }
                SettingsFieldRow {
                    SecureField("", text: $anthropicKey,
                                prompt: Text(hasAnthropicKey ? "New Anthropic API key" : "Anthropic API key").foregroundStyle(Hud.Ink.ink3))
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                        .hud(.body)
                        .focused($keyFocused)
                        .hudField(isFocused: keyFocused)
                        .onSubmit(saveAnthropicKey)
                        .accessibilityLabel("Anthropic API key")
                    if isSavingKey { HudSpinner() }
                    HudButton("Save", action: saveAnthropicKey)
                        .disabled(isSavingKey || anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Saves the key to Keychain")
                }
                SettingsFieldRow {
                    HudTextField(text: optionalBinding(\.agent.anthropicModelID),
                                 prompt: "Anthropic model ID (empty: \(AnthropicProvider.defaultModel))")
                        .accessibilityLabel("Anthropic model ID")
                }
                SettingsMessage(message: keyMessage, failed: keyFailed)
            }
        }

        SettingsGroup("Meetings", index: 3) {
            SettingsRow(glyph: .waveform, title: "Transcript",
                        detail: model.preferences.meetingProcessing.transcription == .onDevice
                            ? Text("Free · audio stays on this Mac") : nil) {
                HudSelect(selection: binding(\.meetingProcessing.transcription), options: [
                    (MeetingTranscriptionEngine.elevenLabs, "ElevenLabs (cloud, speaker names)"),
                    (MeetingTranscriptionEngine.onDevice, "On this Mac (Apple Speech)")
                ])
                .accessibilityLabel("Transcript")
            }
            SettingsRow(glyph: .spark, title: "Notes") {
                HudSelect(selection: binding(\.meetingProcessing.summary), options: [
                    (MeetingSummaryEngine.openAI, "OpenAI"),
                    (MeetingSummaryEngine.agent, "Same as above")
                ])
                .accessibilityLabel("Notes")
            }
        }
        .task {
            hasAnthropicKey = await actions.hasAnthropicKey()
            onDeviceStatus = await actions.onDeviceModelStatus()
        }
        .task(id: provider) {
            let kind = provider
            guard let tool = CLIAgentTool.allCases.first(where: { $0.kind == kind }) else { toolInstalled = nil; return }
            toolInstalled = nil
            toolInstalled = await Task.detached { CLIToolLocator.locate(tool) != nil }.value
        }

        OpenAISettingsView(actions: openAI, connected: $openAIConnected)

        extra()
    }

    // MARK: Header chain

    private enum Link: CaseIterable {
        case anthropic, openAI, thisMac

        var title: LocalizedStringKey {
            switch self {
            case .anthropic: "Anthropic"
            case .openAI: "OpenAI"
            case .thisMac: "This Mac"
            }
        }
    }

    /// The link of the fallback chain that will write, if any can.
    private var litLink: Link? {
        switch provider {
        case .automatic:
            if hasAnthropicKey { return .anthropic }
            if openAIConnected == true { return .openAI }
            return onDeviceStatus == nil ? .thisMac : nil
        case .anthropic: return hasAnthropicKey ? .anthropic : nil
        case .openAI: return openAIConnected == true ? .openAI : nil
        case .onDevice: return onDeviceStatus == nil ? .thisMac : nil
        case .claudeCode, .codex, .off: return nil
        }
    }

    /// The fallback chain as three lamps: lit = will be used. A command-line tool is
    /// outside the chain, so it shows as the one lamp it is.
    @ViewBuilder
    private var chain: some View {
        switch provider {
        case .off:
            EmptyView()
        case .claudeCode, .codex:
            HStack(spacing: 6) {
                HudLamp(toolInstalled == true ? .teal : .off)
                Text(verbatim: provider == .codex ? "Codex" : "Claude Code").hud(.meta)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .hudWell()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(toolInstalled == true ? "Installed" : "Not installed")
        default:
            HStack(spacing: 12) {
                ForEach(Array(Link.allCases.enumerated()), id: \.offset) { index, link in
                    if index > 0 {
                        HudIcon(.chevronRight, size: 12).foregroundStyle(Hud.Ink.ink4)
                    }
                    HStack(spacing: 6) {
                        HudLamp(litLink == link ? .teal : .off)
                        Text(link.title).hud(.meta)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .hudWell()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fallback order: Anthropic, then OpenAI, then this Mac")
        }
    }

    // MARK: Model row

    private var providerDetail: Text? {
        switch provider {
        case .automatic: Text("Anthropic, then OpenAI, then this Mac")
        case .onDevice: onDeviceStatus.map { Text(verbatim: $0) } ?? Text("Apple’s model, on this Mac")
        case .openAI: Text("Your OpenAI key")
        case .anthropic: Text("Your Anthropic key")
        case .claudeCode, .codex: Text("Your sign-in on this Mac · notes only, not dictation")
        case .off: Text("Raw text only")
        }
    }

    @ViewBuilder
    private var providerStatus: some View {
        switch provider {
        case .claudeCode, .codex:
            switch toolInstalled {
            case .some(true): HudStatusWord(.ok, "Installed")
            case .some(false): HudStatusWord(.warn, "Not installed")
            case nil: EmptyView()
            }
        case .onDevice:
            if onDeviceStatus != nil { HudStatusWord(.warn, "Unavailable") }
        default:
            EmptyView()
        }
    }

    // MARK: Actions

    private func saveAnthropicKey() {
        let key = anthropicKey
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty, !isSavingKey else { return }
        isSavingKey = true
        Task {
            let result = await actions.saveAnthropicKey(key)
            anthropicKey = ""
            hasAnthropicKey = await actions.hasAnthropicKey()
            show(result)
            isSavingKey = false
        }
    }

    private func removeAnthropicKey() {
        isSavingKey = true
        Task {
            let result = await actions.deleteAnthropicKey()
            hasAnthropicKey = await actions.hasAnthropicKey()
            show(result)
            isSavingKey = false
        }
    }

    private func show(_ result: SettingsActionResult) {
        switch result {
        case .succeeded(let message): keyMessage = message; keyFailed = false
        case .failed(let message): keyMessage = message; keyFailed = true
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CrenelPreferences, Value>) -> Binding<Value> {
        model.binding(keyPath, actions: actions)
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<CrenelPreferences, String?>) -> Binding<String> {
        Binding(
            get: { model.preferences[keyPath: keyPath] ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                model.preferences[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                model.save(actions)
            }
        )
    }
}

// MARK: - Tasks

/// Settings › Tasks (`s-tasks-*`).
struct TaskStorageSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    let actions: CrenelSettingsActions
    @ObservedObject var model: CrenelSettingsModel

    var body: some View {
        SettingsPageHeader(glyph: .queue, title: "Tasks", sentence: "Where your tasks live.")

        SettingsGroup("Storage", index: 1) {
            SettingsRow(glyph: .queue, title: "Keep tasks in",
                        detail: model.preferences.taskStorage == .reminders
                            ? Text("Also on iPhone, iPad and Watch") : Text("Only on this Mac")) {
                HudSelect(selection: model.binding(\.taskStorage, actions: actions), options: [
                    (TaskStorageBackend.reminders, "Apple Reminders"),
                    (TaskStorageBackend.local, "This Mac only")
                ])
                .accessibilityLabel("Keep tasks in")
            }
            statusRow
            SettingsMessage(message: model.message, failed: model.failed)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch appState.taskStorageStatus {
        case .reminders(let listTitle):
            SettingsRow(title: "Reminders", detail: Text("“\(listTitle)” list")) {
                HudStatusWord(.ok, "Connected")
                HudButton("Open", glyph: .link, size: .small) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
                }
                .accessibilityLabel("Open Reminders")
            }
        case .localNotConnected:
            SettingsRow(title: "Reminders") {
                HudStatusWord(.dim, "Not connected")
                HudButton("Connect", size: .small, action: crenelActions.tasks.connectReminders)
                    .accessibilityLabel("Connect Reminders")
            }
        case .localDenied:
            SettingsRow(title: "Reminders", detail: Text("Privacy & Security › Reminders")) {
                HudStatusWord(.off(), "Access off")
                HudButton("Open", glyph: .link, size: .small) {
                    if let url = SetupCapability.reminders.settingsURL { NSWorkspace.shared.open(url) }
                }
                .accessibilityLabel("Open Reminders privacy settings")
            }
        case .localAfterError(let message):
            SettingsRow(title: "Reminders", detail: Text(verbatim: message)) {
                HudStatusWord(.err, "Error")
                HudButton("Try again", size: .small, action: crenelActions.tasks.connectReminders)
            }
        case .localByChoice:
            EmptyView()
        }
    }
}

// MARK: - Word chips

/// The dictionary as removable chips.
struct SettingsWordChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                SettingsWordChip(item: item) { onRemove(item) }
            }
        }
    }
}

private struct SettingsWordChip: View {
    let item: String
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Hud.Radius.s, style: .continuous)
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(verbatim: item).lineLimit(1)
                HudIcon(.close, size: 8)
                    .foregroundStyle(isHovering ? Hud.Ink.ink1 : Hud.Ink.ink4)
            }
            .hud(.meta, Hud.Ink.ink2)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(shape.fill(isHovering ? Hud.Ink.fieldFocus : Hud.Ink.field))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.hover, value: isHovering)
        .accessibilityLabel("Remove \(item)")
    }
}
