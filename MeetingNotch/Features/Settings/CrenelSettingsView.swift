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
        VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
            SettingsGroup("Dictation") {
                SettingsRow(glyph: .waveform, title: "Use dictation") {
                    Toggle("Use dictation", isOn: binding(\.dictationEnabled)).settingsSwitch()
                }
                permissionRows
                SettingsRow(glyph: .keyboard, title: "Shortcut",
                            detail: model.preferences.dictationTrigger.trigger == .fnHold
                                ? Text("Use ⌃Space to switch input languages") : nil) {
                    Picker("Shortcut", selection: binding(\.dictationTrigger.trigger)) {
                        Text("Hold Fn (🌐)").tag(DictationTrigger.fnHold)
                        Text("Hold right ⌥").tag(DictationTrigger.rightOptionHold)
                        Text("Hold right ⌘").tag(DictationTrigger.rightCommandHold)
                    }.settingsMenu()
                }
                SettingsRow(title: "Mode") {
                    Picker("Mode", selection: binding(\.dictationTrigger.mode)) {
                        Text("Hold to talk").tag(DictationTriggerMode.holdToTalk)
                        Text("Press to start, press to stop").tag(DictationTriggerMode.toggle)
                    }.settingsMenu()
                }
                SettingsRow(title: "Double-tap for hands-free") {
                    Toggle("Double-tap for hands-free", isOn: binding(\.dictationTrigger.allowsDoubleTapHandsFree))
                        .settingsSwitch()
                }
                SettingsRow(title: "Language") {
                    Picker("Language", selection: binding(\.dictationLanguage)) {
                        Text("System language").tag(DictationLanguage.automatic)
                        Text("Turkish").tag(DictationLanguage.turkish)
                        Text("English").tag(DictationLanguage.english)
                    }.settingsMenu()
                }
                SettingsRow(title: "Speech model", detail: Text("On-device")) {
                    Button("Download", action: crenelActions.dictation.prepareSpeechAssets)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                        .accessibilityLabel("Download model")
                }
            }

            SettingsGroup("Dictionary") {
                HStack(spacing: Hud.Space.x2) {
                    TextField("Crenel, SwiftUI, Ayhan", text: $newTerm)
                        .focused($termFocused)
                        .settingsField(focused: termFocused)
                        .onSubmit(addTerm)
                        .accessibilityLabel("New dictionary term")
                    Button(action: addTerm) { HudIcon(.plus, size: Hud.Size.smallIcon) }
                        .buttonStyle(HudButtonStyle(kind: .iconFilled))
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add")
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .padding(.vertical, Hud.Space.x1)
                if !model.preferences.dictationVocabulary.isEmpty {
                    FlowChips(items: model.preferences.dictationVocabulary) { term in
                        model.preferences.dictationVocabulary.removeAll { $0 == term }
                        model.save(actions)
                    }
                    .padding(.horizontal, Hud.Size.rowInset)
                    .padding(.top, Hud.Space.x2)
                }
            }

            SettingsGroup("Recent") {
                if appState.dictationHistory.isEmpty {
                    SettingsNote("Nothing yet · kept in memory only")
                } else {
                    ForEach(appState.dictationHistory.prefix(8)) { entry in
                        SettingsRow(title: entry.finalText,
                                    detail: Text([entry.appName, entry.createdAt.formatted(date: .omitted, time: .shortened)]
                                        .compactMap { $0 }.joined(separator: " · "))) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.finalText, forType: .string)
                            } label: {
                                CrenelIcon(.copy, size: Hud.Size.smallIcon)
                            }
                            .buttonStyle(HudButtonStyle(kind: .icon))
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
    private var permissionRows: some View {
        switch appState.dictationAvailability {
        case .needsInputMonitoring:
            SettingsRow(glyph: .keyboard, title: "Input Monitoring", detail: Text("Needed for the shortcut")) {
                Button("Allow", action: crenelActions.dictation.requestInputMonitoring)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        case .ready, .disabled:
            EmptyView()
        }
        if !appState.accessibilityPermissionGranted {
            SettingsNote("Without Accessibility, text goes to the clipboard")
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
        VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
            SettingsGroup("Agent") {
                SettingsRow(glyph: .sparkle, title: "Model", detail: providerDetail) {
                    Picker("Model", selection: binding(\.agent.provider)) {
                        Text("Automatic").tag(AgentProviderKind.automatic)
                        Text("On-device (Apple)").tag(AgentProviderKind.onDevice)
                        Text("OpenAI (your key)").tag(AgentProviderKind.openAI)
                        Text("Anthropic (your key)").tag(AgentProviderKind.anthropic)
                        Text("Off").tag(AgentProviderKind.off)
                    }.settingsMenu()
                }
                SettingsRow(title: "Clean up dictation") {
                    Toggle("Clean up dictation", isOn: binding(\.agent.cleanupEnabled)).settingsSwitch()
                }
                SettingsRow(title: "Voice commands on selected text") {
                    Toggle("Voice commands on selected text", isOn: binding(\.agent.commandModeEnabled)).settingsSwitch()
                }

                if model.preferences.agent.provider == .openAI {
                    SettingsFieldRow {
                        TextField("OpenAI model ID (empty: default)", text: optionalBinding(\.agent.openAIModelID))
                            .settingsField()
                    }
                }
                if model.preferences.agent.provider == .anthropic || model.preferences.agent.provider == .automatic {
                    SettingsRow(title: "Anthropic") {
                        if hasAnthropicKey {
                            Text("Connected").hud(.label, Hud.Ink.ok)
                        } else {
                            Text("Key required").hud(.label, Hud.Ink.text3)
                        }
                    }
                    SettingsFieldRow {
                        SecureField(hasAnthropicKey ? "New Anthropic API key" : "Anthropic API key", text: $anthropicKey)
                            .textContentType(.password)
                            .focused($keyFocused)
                            .settingsField(focused: keyFocused)
                            .accessibilityLabel("Anthropic API key")
                        Button("Save") {
                            let key = anthropicKey
                            Task {
                                let result = await actions.saveAnthropicKey(key)
                                anthropicKey = ""
                                hasAnthropicKey = await actions.hasAnthropicKey()
                                keyMessage = result.message
                            }
                        }
                        .buttonStyle(HudButtonStyle(kind: .primary))
                        .disabled(anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if hasAnthropicKey {
                            Button {
                                Task {
                                    keyMessage = await actions.deleteAnthropicKey().message
                                    hasAnthropicKey = await actions.hasAnthropicKey()
                                }
                            } label: {
                                Text("Remove").foregroundStyle(Hud.Ink.live)
                            }
                            .buttonStyle(HudButtonStyle(kind: .ghost))
                        }
                    }
                    SettingsFieldRow {
                        TextField("Anthropic model ID (empty: default)", text: optionalBinding(\.agent.anthropicModelID))
                            .settingsField()
                    }
                    if let keyMessage {
                        SettingsNote(keyMessage)
                    }
                }
            }

            SettingsGroup("Meetings") {
                SettingsRow(glyph: .waveform, title: "Transcript",
                            detail: model.preferences.meetingProcessing.transcription == .onDevice
                                ? Text("Free · audio stays on this Mac") : nil) {
                    Picker("Transcript", selection: binding(\.meetingProcessing.transcription)) {
                        ForEach(MeetingTranscriptionEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.settingsMenu()
                }
                SettingsRow(glyph: .sparkle, title: "Summary") {
                    Picker("Summary", selection: binding(\.meetingProcessing.summary)) {
                        ForEach(MeetingSummaryEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.settingsMenu()
                }
            }

            CrenelSaveStatus(message: model.message, failed: model.failed)
        }
        .task {
            await model.load(actions)
            hasAnthropicKey = await actions.hasAnthropicKey()
            onDeviceStatus = await actions.onDeviceModelStatus()
        }
    }

    private var providerDetail: Text? {
        switch model.preferences.agent.provider {
        case .automatic: Text("Anthropic, then OpenAI, then on-device")
        case .onDevice: onDeviceStatus.map { Text($0).foregroundStyle(Hud.Ink.signal) }
        case .openAI: Text("Uses the OpenAI key below")
        default: nil
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
        VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
            SettingsGroup("Tasks") {
                SettingsRow(glyph: .tasks, title: "Store tasks in",
                            detail: model.preferences.taskStorage == .reminders
                                ? Text("Syncs to iPhone, iPad and Watch") : nil) {
                    Picker("Store tasks in", selection: Binding(
                        get: { model.preferences.taskStorage },
                        set: { model.preferences.taskStorage = $0; model.save(actions) }
                    )) {
                        Text("Apple Reminders").tag(TaskStorageBackend.reminders)
                        Text("This Mac only").tag(TaskStorageBackend.local)
                    }.settingsMenu()
                }
                statusRow
            }
            CrenelSaveStatus(message: model.message, failed: model.failed)
        }
        .task { await model.load(actions) }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch appState.taskStorageStatus {
        case .reminders(let listTitle):
            SettingsRow(title: "Reminders", detail: Text("“\(listTitle)” list")) {
                Text("Connected").hud(.label, Hud.Ink.ok)
            }
        case .localNotConnected:
            SettingsRow(title: "Reminders", detail: Text("Not connected")) {
                Button("Connect", action: crenelActions.tasks.connectReminders)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        case .localDenied:
            SettingsRow(title: "Reminders",
                        detail: Text("Privacy & Security › Reminders")) {
                Text("Access off").hud(.label, Hud.Ink.signal)
            }
        case .localAfterError(let message):
            SettingsRow(title: "Reminders", detail: Text(message).foregroundStyle(Hud.Ink.live)) {
                Button("Try again", action: crenelActions.tasks.connectReminders)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        case .localByChoice:
            EmptyView()
        }
    }
}

// MARK: - Settings row system

/// Shared layout values for every settings page.
enum SettingsLayout {
    /// Space between groups — groups are separated by air, never lines.
    static let groupSpacing: CGFloat = Hud.Space.x7
    /// Rows read best at a comfortable measure, not the full window width.
    static let contentWidth: CGFloat = 600
}

/// A plain group: a small header, then its rows. No card, no rules.
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .hud(.label, Hud.Ink.text3)
                    .padding(.horizontal, Hud.Size.rowInset)
                    .frame(height: 22, alignment: .bottom)
                    .padding(.bottom, Hud.Space.x1)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: SettingsLayout.contentWidth, alignment: .leading)
    }
}

/// One setting: icon · name · optional one-line detail · control or status on the right.
struct SettingsRow<Trailing: View>: View {
    var glyph: CrenelGlyph?
    let title: Text
    var detail: Text?
    @ViewBuilder let trailing: Trailing

    init(glyph: CrenelGlyph? = nil, title: LocalizedStringKey, detail: Text? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.glyph = glyph
        self.title = Text(title)
        self.detail = detail
        self.trailing = trailing()
    }

    init(glyph: CrenelGlyph? = nil, title: String, detail: Text? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.glyph = glyph
        self.title = Text(verbatim: title)
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Hud.Space.x3) {
            Group {
                if let glyph {
                    CrenelIcon(glyph, size: Hud.Size.icon)
                } else {
                    Color.clear
                }
            }
            .frame(width: Hud.Size.icon, height: Hud.Size.icon)
            .foregroundStyle(Hud.Ink.text3)

            VStack(alignment: .leading, spacing: 2) {
                title.hud(.body).lineLimit(1)
                if let detail {
                    detail.hud(.meta, Hud.Ink.text3).lineLimit(1)
                }
            }
            Spacer(minLength: Hud.Space.x4)
            trailing
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(minHeight: Hud.Size.row)
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(glyph: CrenelGlyph? = nil, title: LocalizedStringKey, detail: Text? = nil) {
        self.init(glyph: glyph, title: title, detail: detail) { EmptyView() }
    }
}

/// A row holding a text field and its buttons, aligned with row text.
struct SettingsFieldRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Hud.Space.x2) { content }
            .padding(.leading, Hud.Size.rowInset + Hud.Size.icon + Hud.Space.x3)
            .padding(.trailing, Hud.Size.rowInset)
            .padding(.vertical, Hud.Space.x1)
    }
}

/// One short secondary line under a group.
struct SettingsNote: View {
    let text: Text
    var color: Color = Hud.Ink.text3

    init(_ key: LocalizedStringKey, color: Color = Hud.Ink.text3) {
        self.text = Text(key)
        self.color = color
    }

    init(_ string: String, color: Color = Hud.Ink.text3) {
        self.text = Text(verbatim: string)
        self.color = color
    }

    var body: some View {
        text.hud(.meta, color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, Hud.Size.rowInset + Hud.Size.icon + Hud.Space.x3)
            .padding(.trailing, Hud.Size.rowInset)
            .padding(.vertical, Hud.Space.x1)
    }
}

extension View {
    /// A plain switch with a neutral tint.
    func settingsSwitch() -> some View {
        labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Hud.Ink.text2)
    }

    /// A compact menu picker sitting at the right of a row.
    func settingsMenu() -> some View {
        labelsHidden().pickerStyle(.menu).fixedSize().controlSize(.small)
    }

    /// A text field on a faint fill — no border, focus lifts the fill only.
    func settingsField(focused: Bool = false) -> some View {
        textFieldStyle(.plain)
            .font(Hud.Style.body.font)
            .foregroundStyle(Hud.Ink.text1)
            .padding(.horizontal, Hud.Space.x3)
            .frame(height: Hud.Size.control)
            .background(
                RoundedRectangle(cornerRadius: Hud.Size.corner - 2, style: .continuous)
                    .fill(focused ? Hud.Ink.selected : Hud.Ink.hover)
            )
            .animation(Hud.Motion.hover, value: focused)
    }
}

private struct CrenelSaveStatus: View {
    let message: String?
    let failed: Bool

    var body: some View {
        if let message {
            SettingsNote(message, color: failed ? Hud.Ink.live : Hud.Ink.text3)
                .frame(maxWidth: SettingsLayout.contentWidth, alignment: .leading)
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: Hud.Space.x1 + 2, alignment: .leading)],
                  alignment: .leading, spacing: Hud.Space.x1 + 2) {
            ForEach(items, id: \.self) { item in
                FlowChip(item: item) { onRemove(item) }
            }
        }
    }
}

private struct FlowChip: View {
    let item: String
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: Hud.Space.x1 + 2) {
                Text(item).lineLimit(1)
                HudIcon(.close, size: 8)
                    .foregroundStyle(isHovering ? Hud.Ink.text1 : Hud.Ink.text4)
            }
            .hud(.meta, Hud.Ink.text2)
            .padding(.horizontal, Hud.Space.x2)
            .frame(height: 24)
            .background(Capsule().fill(isHovering ? Hud.Ink.selected : Hud.Ink.hover))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
        .accessibilityLabel("Remove \(item)")
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
