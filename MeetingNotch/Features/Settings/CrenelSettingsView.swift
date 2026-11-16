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

/// Shared load/edit/save state for the Crenel settings sections.
@MainActor
private final class CrenelSettingsModel: ObservableObject {
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
}

// MARK: - Dictation

struct DictationSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    let actions: CrenelSettingsActions
    @StateObject private var model = CrenelSettingsModel()
    @State private var newTerm = ""
    @FocusState private var termFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.sectionSpacing) {
            CrenelSettingsCard(title: "Smart dictation", symbol: "mic") {
                Toggle("Use dictation", isOn: binding(\.dictationEnabled))
                permissionRow

                Picker("Shortcut", selection: binding(\.dictationTrigger.trigger)) {
                    Text("Hold Fn (🌐)").tag(DictationTrigger.fnHold)
                    Text("Hold right ⌥").tag(DictationTrigger.rightOptionHold)
                    Text("Hold right ⌘").tag(DictationTrigger.rightCommandHold)
                }
                Picker("Mode", selection: binding(\.dictationTrigger.mode)) {
                    Text("Hold to talk").tag(DictationTriggerMode.holdToTalk)
                    Text("Press to start, press to stop").tag(DictationTriggerMode.toggle)
                }
                Toggle("Double-tap for hands-free", isOn: binding(\.dictationTrigger.allowsDoubleTapHandsFree))
                Picker("Language", selection: binding(\.dictationLanguage)) {
                    Text("System language").tag(DictationLanguage.automatic)
                    Text("Turkish").tag(DictationLanguage.turkish)
                    Text("English").tag(DictationLanguage.english)
                }
                HStack {
                    Text("The speech model runs on-device and downloads on first use.")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                    Spacer()
                    Button("Download model", action: crenelActions.dictation.prepareSpeechAssets)
                }
                if model.preferences.dictationTrigger.trigger == .fnHold {
                    Text("While Fn is the dictation key, it won’t switch input languages or open emoji on its own. Use ⌃Space to switch languages; Fn’s usual behavior returns when dictation is off.")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CrenelSettingsCard(title: "Personal dictionary", symbol: "character.book.closed") {
                Text("Names, products and technical terms are written exactly as entered.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                HStack {
                    TextField("E.g. Crenel, SwiftUI, Ayhan", text: $newTerm)
                        .focused($termFocused)
                        .meetingFieldSurface(focused: termFocused)
                        .onSubmit(addTerm)
                    Button("Add", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.preferences.dictationVocabulary.isEmpty {
                    FlowChips(items: model.preferences.dictationVocabulary) { term in
                        model.preferences.dictationVocabulary.removeAll { $0 == term }
                        model.save(actions)
                    }
                }
            }

            CrenelSettingsCard(title: "Recent dictations", symbol: "clock.arrow.circlepath") {
                if appState.dictationHistory.isEmpty {
                    Text("No dictations this session. History stays in memory and is never written to disk.")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                } else {
                    ForEach(appState.dictationHistory.prefix(8)) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.finalText).lineLimit(2)
                                Text([entry.appName, entry.createdAt.formatted(date: .omitted, time: .shortened)]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(MeetingNotchTheme.MainPanel.smallFont)
                                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                            }
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.finalText, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(MeetingNotchIconButtonStyle())
                            .help("Copy")
                            .accessibilityLabel("Copy dictation")
                        }
                    }
                }
            }

            CrenelSaveStatus(message: model.message, failed: model.failed)
        }
        .task { await model.load(actions) }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch appState.dictationAvailability {
        case .needsInputMonitoring:
            HStack {
                Label("The shortcut needs Input Monitoring access", systemImage: "keyboard")
                    .foregroundStyle(MeetingNotchTheme.warning)
                Spacer()
                Button("Allow", action: crenelActions.dictation.requestInputMonitoring)
            }
        case .ready:
            Label("Shortcut ready. Types at the cursor.", systemImage: "checkmark.circle")
                .foregroundStyle(MeetingNotchTheme.success)
        case .disabled:
            EmptyView()
        }
        if !appState.accessibilityPermissionGranted {
            Text("Typing text directly needs Accessibility access; without it, text is copied to the clipboard.")
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { model.preferences[keyPath: keyPath] = $0; model.save(actions) }
        )
    }
}

// MARK: - Agent

struct AgentSettingsView: View {
    let actions: CrenelSettingsActions
    @StateObject private var model = CrenelSettingsModel()
    @State private var anthropicKey = ""
    @State private var hasAnthropicKey = false
    @State private var keyMessage: String?
    @State private var onDeviceStatus: String?
    @FocusState private var keyFocused: Bool

    var body: some View {
        CrenelSettingsCard(title: "Agent", symbol: "sparkles") {
            Text("Cleans up and punctuates dictation, and edits selected text by voice.")
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
            Picker("Model", selection: binding(\.agent.provider)) {
                Text("Automatic (recommended)").tag(AgentProviderKind.automatic)
                Text("On-device (Apple)").tag(AgentProviderKind.onDevice)
                Text("OpenAI (your key)").tag(AgentProviderKind.openAI)
                Text("Anthropic (your key)").tag(AgentProviderKind.anthropic)
                Text("Off").tag(AgentProviderKind.off)
            }
            if model.preferences.agent.provider == .automatic {
                Text("Uses your saved API key: Anthropic (Claude Haiku) first, then OpenAI. With no key, it falls back to Apple’s on-device model.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.preferences.agent.provider == .onDevice, let onDeviceStatus {
                Text(onDeviceStatus)
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Clean up dictation", isOn: binding(\.agent.cleanupEnabled))
            Toggle("Voice commands on selected text", isOn: binding(\.agent.commandModeEnabled))

            if model.preferences.agent.provider == .openAI {
                Text("The OpenAI key is shared with meeting summaries; connect it under AI › OpenAI.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Model ID (empty: default)", text: optionalBinding(\.agent.openAIModelID))
                    .meetingFieldSurface(focused: false)
            }
            if model.preferences.agent.provider == .anthropic || model.preferences.agent.provider == .automatic {
                HStack {
                    SecureField(hasAnthropicKey ? "New Anthropic API key" : "Anthropic API key", text: $anthropicKey)
                        .textContentType(.password)
                        .focused($keyFocused)
                        .meetingFieldSurface(focused: keyFocused)
                    Button("Save") {
                        let key = anthropicKey
                        Task {
                            let result = await actions.saveAnthropicKey(key)
                            anthropicKey = ""
                            hasAnthropicKey = await actions.hasAnthropicKey()
                            keyMessage = result.message
                        }
                    }
                    .disabled(anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasAnthropicKey {
                        Button("Remove") {
                            Task {
                                keyMessage = await actions.deleteAnthropicKey().message
                                hasAnthropicKey = await actions.hasAnthropicKey()
                            }
                        }
                    }
                }
                Label(hasAnthropicKey ? "Key in Keychain" : "Key required", systemImage: hasAnthropicKey ? "checkmark.circle" : "key")
                    .foregroundStyle(hasAnthropicKey ? MeetingNotchTheme.success : MeetingNotchTheme.secondaryText)
                TextField("Model ID (empty: default)", text: optionalBinding(\.agent.anthropicModelID))
                    .meetingFieldSurface(focused: false)
                if let keyMessage {
                    Text(keyMessage).font(MeetingNotchTheme.MainPanel.smallFont)
                }
            }
            Divider()
            Text("Meetings")
                .font(MeetingNotchTheme.MainPanel.smallFont.weight(.semibold))
            Picker("Transcript", selection: binding(\.meetingProcessing.transcription)) {
                ForEach(MeetingTranscriptionEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Summary", selection: binding(\.meetingProcessing.summary)) {
                ForEach(MeetingSummaryEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if model.preferences.meetingProcessing.transcription == .onDevice {
                Text("On-device transcripts are free and audio never leaves your Mac; speakers are split into “You” and “Participants”.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CrenelSaveStatus(message: model.message, failed: model.failed)
        }
        .task {
            await model.load(actions)
            hasAnthropicKey = await actions.hasAnthropicKey()
            onDeviceStatus = await actions.onDeviceModelStatus()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CrenelPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { model.preferences[keyPath: keyPath] = $0; model.save(actions) }
        )
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

struct TaskStorageSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    let actions: CrenelSettingsActions
    @StateObject private var model = CrenelSettingsModel()

    var body: some View {
        CrenelSettingsCard(title: "Tasks", symbol: "checklist") {
            Picker("Store tasks in", selection: Binding(
                get: { model.preferences.taskStorage },
                set: { model.preferences.taskStorage = $0; model.save(actions) }
            )) {
                Text("Apple Reminders").tag(TaskStorageBackend.reminders)
                Text("This Mac only").tag(TaskStorageBackend.local)
            }
            statusRow
            Text("Uses a “Crenel” list in Reminders: tasks show up on iPhone, iPad and Watch, and Apple sends alerts for timed tasks. “In progress” and ordering stay on this Mac.")
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            CrenelSaveStatus(message: model.message, failed: model.failed)
        }
        .task { await model.load(actions) }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch appState.taskStorageStatus {
        case .reminders(let listTitle):
            Label("Connected · “\(listTitle)” list", systemImage: "checkmark.circle")
                .foregroundStyle(MeetingNotchTheme.success)
        case .localNotConnected:
            HStack {
                Label("Reminders not connected", systemImage: "icloud.slash")
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                Spacer()
                Button("Connect", action: crenelActions.tasks.connectReminders)
            }
        case .localDenied:
            Label("Reminders access is off (System Settings › Privacy & Security › Reminders)", systemImage: "lock")
                .foregroundStyle(MeetingNotchTheme.warning)
        case .localAfterError(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(MeetingNotchTheme.warning)
                Spacer()
                Button("Try again", action: crenelActions.tasks.connectReminders)
            }
        case .localByChoice:
            Label("Tasks are stored on this Mac", systemImage: "desktopcomputer")
                .foregroundStyle(MeetingNotchTheme.secondaryText)
        }
    }
}

// MARK: - Building blocks

private struct CrenelSettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.contentSpacing) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct CrenelSaveStatus: View {
    let message: String?
    let failed: Bool

    var body: some View {
        if let message {
            Text(message)
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(failed ? MeetingNotchTheme.danger : MeetingNotchTheme.secondaryText)
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    onRemove(item)
                } label: {
                    HStack(spacing: 4) {
                        Text(item).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(MeetingNotchTheme.MainPanel.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item)")
            }
        }
    }
}

private extension SettingsActionResult {
    var message: String? {
        switch self {
        case .succeeded(let message): message
        case .failed(let message): message
        }
    }
}
