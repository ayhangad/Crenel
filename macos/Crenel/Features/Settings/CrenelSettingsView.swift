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

/// The OpenAI key: looked up, verified and saved, or removed.
struct OpenAISettingsActions {
    var hasKey: () async -> Bool = { false }
    var save: (String) async -> SettingsActionResult = { _ in .failed(message: "Connection unavailable.") }
    var disconnect: () async -> SettingsActionResult = { .succeeded() }
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

/// Settings › AI (`s-ai-*`). Two choices, each with the one key it needs:
/// "General AI" (who writes notes, tasks and dictation clean-up) and, added by the host
/// after it, "Voice" (who turns meeting audio into a transcript).
struct AgentSettingsView<Extra: View>: View {
    let actions: CrenelSettingsActions
    let openAI: OpenAISettingsActions
    @ObservedObject var model: CrenelSettingsModel
    @ViewBuilder var extra: () -> Extra

    @State private var hasAnthropicKey: Bool?
    @State private var hasOpenAIKey: Bool?
    @State private var onDeviceStatus: String?
    /// Whether the selected command-line tool is installed (nil while checking).
    @State private var toolInstalled: Bool?
    @State private var keyMessage: String?
    @State private var keyFailed = false

    private var provider: AgentProviderKind { model.preferences.agent.provider }

    var body: some View {
        SettingsPageHeader(glyph: .spark, title: "AI", sentence: "One provider for writing, one for voice.")

        SettingsGroup("General AI", index: 1) {
            SettingsRow(glyph: .spark, title: "Provider", detail: providerDetail) {
                providerStatus
                HudSelect(selection: providerBinding, options: providerOptions)
                    .accessibilityLabel("General AI provider")
            }
            switch provider {
            case .anthropic:
                SettingsKeyField(
                    name: "Anthropic", hasKey: hasAnthropicKey, saveTitle: "Save", saveHelp: "Saves the key to Keychain",
                    save: { key in
                        let result = await actions.saveAnthropicKey(key)
                        hasAnthropicKey = await actions.hasAnthropicKey()
                        show(result)
                    },
                    remove: {
                        let result = await actions.deleteAnthropicKey()
                        hasAnthropicKey = await actions.hasAnthropicKey()
                        show(result)
                    }
                )
            case .openAI:
                SettingsKeyField(
                    name: "OpenAI", hasKey: hasOpenAIKey, saveTitle: "Connect", saveHelp: "Sends a small paid test request",
                    save: { key in
                        let result = await openAI.save(key)
                        hasOpenAIKey = await openAI.hasKey()
                        show(result)
                    },
                    remove: {
                        let result = await openAI.disconnect()
                        hasOpenAIKey = await openAI.hasKey()
                        show(result)
                    }
                )
            default:
                EmptyView()
            }
            SettingsMessage(message: keyMessage, failed: keyFailed)
            SettingsRow(title: "Clean up dictation") {
                SettingsToggle("Clean up dictation", isOn: binding(\.agent.cleanupEnabled))
            }
            SettingsRow(title: "Voice commands on selected text") {
                SettingsToggle("Voice commands on selected text", isOn: binding(\.agent.commandModeEnabled))
            }
            SettingsMessage(message: model.message, failed: model.failed)
        }
        .task {
            hasAnthropicKey = await actions.hasAnthropicKey()
            hasOpenAIKey = await openAI.hasKey()
            onDeviceStatus = await actions.onDeviceModelStatus()
        }
        .task(id: provider) {
            keyMessage = nil
            let kind = provider
            guard let tool = CLIAgentTool.allCases.first(where: { $0.kind == kind }) else { toolInstalled = nil; return }
            toolInstalled = nil
            toolInstalled = await Task.detached { CLIToolLocator.locate(tool) != nil }.value
        }
        .task(id: model.isLoaded) {
            // Older settings let meeting notes use a different provider than the rest.
            // There is one choice now, so bring them in line once.
            guard model.isLoaded else { return }
            let expected = Self.summaryEngine(for: provider)
            if model.preferences.meetingProcessing.summary != expected {
                model.preferences.meetingProcessing.summary = expected
                model.save(actions)
            }
        }

        extra()
    }

    // MARK: Provider

    /// Meeting notes follow the one provider chosen here.
    static func summaryEngine(for provider: AgentProviderKind) -> MeetingSummaryEngine {
        provider == .openAI ? .openAI : .agent
    }

    private var providerBinding: Binding<AgentProviderKind> {
        Binding(
            get: { provider },
            set: {
                model.preferences.agent.provider = $0
                model.preferences.meetingProcessing.summary = Self.summaryEngine(for: $0)
                model.save(actions)
            }
        )
    }

    private var providerOptions: [(value: AgentProviderKind, title: String)] {
        var options: [(value: AgentProviderKind, title: String)] = [
            (.anthropic, "Claude (API key)"),
            (.openAI, "OpenAI (API key)"),
            (.claudeCode, "Claude Code"),
            (.onDevice, "On this Mac (Apple)")
        ]
        // Choices from older versions stay visible only while they are the saved one.
        if provider == .automatic { options.append((.automatic, "Automatic")) }
        if provider == .off { options.append((.off, "Off")) }
        return options
    }

    private var providerDetail: Text? {
        switch provider {
        case .anthropic, .openAI: Text("Notes, tasks and dictation clean-up · billed to you")
        case .claudeCode: Text("Sends transcript text to Anthropic using your Claude Code sign-in for notes and tasks")
        case .onDevice: onDeviceStatus.map { Text(verbatim: $0) } ?? Text("Apple’s model · free, stays on this Mac")
        case .automatic: Text("Anthropic, then OpenAI, then this Mac")
        case .off: Text("Raw text only")
        }
    }

    @ViewBuilder
    private var providerStatus: some View {
        switch provider {
        case .anthropic: keyStatus(hasAnthropicKey)
        case .openAI: keyStatus(hasOpenAIKey)
        case .claudeCode:
            switch toolInstalled {
            case .some(true): HudStatusWord(.ok, "Installed")
            case .some(false): HudStatusWord(.warn, "Not installed")
            case nil: EmptyView()
            }
        case .onDevice:
            if onDeviceStatus != nil { HudStatusWord(.warn, "Unavailable") }
        case .automatic, .off:
            EmptyView()
        }
    }

    @ViewBuilder
    private func keyStatus(_ hasKey: Bool?) -> some View {
        switch hasKey {
        case .some(true): HudStatusWord(.ok, "Connected")
        case .some(false): HudStatusWord(.warn, "Needs a key")
        case nil: EmptyView()
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
}

/// The one key of the chosen provider: a secure field, its save key, and Remove once a
/// key is stored.
struct SettingsKeyField: View {
    let name: String
    /// nil while the key is being looked up.
    let hasKey: Bool?
    var saveTitle: LocalizedStringKey = "Save"
    var saveHelp: LocalizedStringKey = ""
    let save: (String) async -> Void
    let remove: () async -> Void

    @State private var key = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsFieldRow {
            SecureField("", text: $key,
                        prompt: Text(verbatim: hasKey == true ? "Type to replace the saved \(name) key" : "\(name) API key")
                            .foregroundStyle(Hud.Ink.ink3))
                .textFieldStyle(.plain)
                .textContentType(.password)
                .hud(.body)
                .focused($focused)
                .hudField(isFocused: focused)
                .onSubmit(submit)
                .accessibilityLabel("\(name) API key")
            if busy { HudSpinner() }
            HudButton(saveTitle, action: submit)
                .disabled(busy || hasKey == nil || trimmed.isEmpty)
                .help(saveHelp)
            if hasKey == true {
                HudButton("Remove", kind: .danger) {
                    busy = true
                    Task {
                        await remove()
                        busy = false
                    }
                }
                .disabled(busy)
                .accessibilityLabel("Remove \(name) key")
            }
        }
    }

    private func submit() {
        guard !busy, hasKey != nil, !trimmed.isEmpty else { return }
        busy = true
        let candidate = trimmed
        Task {
            await save(candidate)
            key = ""
            busy = false
        }
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
