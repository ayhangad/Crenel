import SwiftUI

/// Data and actions the Crenel settings screens need. Views never touch Keychain,
/// EventKit or the event tap directly.
struct CrenelSettingsActions {
    var load: () async -> CrenelPreferences = { .default }
    var save: (CrenelPreferences) async -> SettingsActionResult = { _ in .succeeded() }
    var hasAnthropicKey: () async -> Bool = { false }
    var saveAnthropicKey: (String) async -> SettingsActionResult = { _ in .failed(message: "Kullanılamıyor.") }
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
            CrenelSettingsCard(title: "Akıllı dikte", symbol: "mic") {
                Toggle("Dikteyi kullan", isOn: binding(\.dictationEnabled))
                permissionRow

                Picker("Kısayol", selection: binding(\.dictationTrigger.trigger)) {
                    Text("Fn (🌐) basılı tut").tag(DictationTrigger.fnHold)
                    Text("Sağ ⌥ basılı tut").tag(DictationTrigger.rightOptionHold)
                    Text("Sağ ⌘ basılı tut").tag(DictationTrigger.rightCommandHold)
                }
                Picker("Mod", selection: binding(\.dictationTrigger.mode)) {
                    Text("Basılı tut, konuş").tag(DictationTriggerMode.holdToTalk)
                    Text("Bas başlat, bas bitir").tag(DictationTriggerMode.toggle)
                }
                Toggle("Çift dokunuşla eller serbest", isOn: binding(\.dictationTrigger.allowsDoubleTapHandsFree))
                Picker("Dil", selection: binding(\.dictationLanguage)) {
                    Text("Sistem dili").tag(DictationLanguage.automatic)
                    Text("Türkçe").tag(DictationLanguage.turkish)
                    Text("İngilizce").tag(DictationLanguage.english)
                }
                HStack {
                    Text("Ses modeli cihazda çalışır; ilk kullanımda indirilir.")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                    Spacer()
                    Button("Modeli indir", action: crenelActions.dictation.prepareSpeechAssets)
                }
                if model.preferences.dictationTrigger.trigger == .fnHold {
                    Text("Fn dikte tuşuyken tek başına dil değiştirmez, emoji açmaz. Dil değiştirmek için ⌃Boşluk kullanın; dikte kapanınca Fn’nin eski davranışı geri gelir.")
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CrenelSettingsCard(title: "Kişisel sözlük", symbol: "character.book.closed") {
                Text("İsimler, ürünler ve teknik terimler bu yazımla eklenir.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                HStack {
                    TextField("Örn. Crenel, SwiftUI, Ayhan", text: $newTerm)
                        .focused($termFocused)
                        .meetingFieldSurface(focused: termFocused)
                        .onSubmit(addTerm)
                    Button("Ekle", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.preferences.dictationVocabulary.isEmpty {
                    FlowChips(items: model.preferences.dictationVocabulary) { term in
                        model.preferences.dictationVocabulary.removeAll { $0 == term }
                        model.save(actions)
                    }
                }
            }

            CrenelSettingsCard(title: "Son dikteler", symbol: "clock.arrow.circlepath") {
                if appState.dictationHistory.isEmpty {
                    Text("Bu oturumda dikte yok. Geçmiş yalnızca bellekte tutulur, diske yazılmaz.")
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
                            .help("Kopyala")
                            .accessibilityLabel("Dikteyi kopyala")
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
                Label("Kısayol için Girdi İzleme izni gerekli", systemImage: "keyboard")
                    .foregroundStyle(MeetingNotchTheme.warning)
                Spacer()
                Button("İzin ver", action: crenelActions.dictation.requestInputMonitoring)
            }
        case .ready:
            Label("Kısayol hazır. İmlecin olduğu yere yazar.", systemImage: "checkmark.circle")
                .foregroundStyle(MeetingNotchTheme.success)
        case .disabled:
            EmptyView()
        }
        if !appState.accessibilityPermissionGranted {
            Text("Metni doğrudan yazmak için Erişilebilirlik izni gerekir; izin yoksa metin panoya kopyalanır.")
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
            Text("Dikteyi temizler, noktalar ve seçili metni sesli komutla düzenler.")
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
            Picker("Model", selection: binding(\.agent.provider)) {
                Text("Otomatik (önerilen)").tag(AgentProviderKind.automatic)
                Text("Cihazda (Apple)").tag(AgentProviderKind.onDevice)
                Text("OpenAI (kendi anahtarınız)").tag(AgentProviderKind.openAI)
                Text("Anthropic (kendi anahtarınız)").tag(AgentProviderKind.anthropic)
                Text("Kapalı").tag(AgentProviderKind.off)
            }
            if model.preferences.agent.provider == .automatic {
                Text("Kayıtlı API anahtarınızı kullanır: önce Anthropic (Claude Haiku), yoksa OpenAI. Anahtar yoksa cihazdaki Apple modeline geçer.")
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
            Toggle("Dikteyi düzenle", isOn: binding(\.agent.cleanupEnabled))
            Toggle("Seçili metinde sesli komut", isOn: binding(\.agent.commandModeEnabled))

            if model.preferences.agent.provider == .openAI {
                Text("OpenAI anahtarı toplantı özetleriyle ortaktır; Yapay zekâ › OpenAI bölümünden bağlanır.")
                    .font(MeetingNotchTheme.MainPanel.smallFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Model kimliği (boş: varsayılan)", text: optionalBinding(\.agent.openAIModelID))
                    .meetingFieldSurface(focused: false)
            }
            if model.preferences.agent.provider == .anthropic || model.preferences.agent.provider == .automatic {
                HStack {
                    SecureField(hasAnthropicKey ? "Yeni Anthropic API anahtarı" : "Anthropic API anahtarı", text: $anthropicKey)
                        .textContentType(.password)
                        .focused($keyFocused)
                        .meetingFieldSurface(focused: keyFocused)
                    Button("Kaydet") {
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
                        Button("Kaldır") {
                            Task {
                                keyMessage = await actions.deleteAnthropicKey().message
                                hasAnthropicKey = await actions.hasAnthropicKey()
                            }
                        }
                    }
                }
                Label(hasAnthropicKey ? "Anahtar Keychain’de" : "Anahtar gerekli", systemImage: hasAnthropicKey ? "checkmark.circle" : "key")
                    .foregroundStyle(hasAnthropicKey ? MeetingNotchTheme.success : MeetingNotchTheme.secondaryText)
                TextField("Model kimliği (boş: varsayılan)", text: optionalBinding(\.agent.anthropicModelID))
                    .meetingFieldSurface(focused: false)
                if let keyMessage {
                    Text(keyMessage).font(MeetingNotchTheme.MainPanel.smallFont)
                }
            }
            Divider()
            Text("Toplantılar")
                .font(MeetingNotchTheme.MainPanel.smallFont.weight(.semibold))
            Picker("Transkript", selection: binding(\.meetingProcessing.transcription)) {
                ForEach(MeetingTranscriptionEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Özet", selection: binding(\.meetingProcessing.summary)) {
                ForEach(MeetingSummaryEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if model.preferences.meetingProcessing.transcription == .onDevice {
                Text("Cihaz içi transkript ücretsizdir ve ses Mac’ten çıkmaz; konuşmacılar “Siz” ve “Katılımcılar” olarak ayrılır.")
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
        CrenelSettingsCard(title: "Görevler", symbol: "checklist") {
            Picker("Görevleri sakla", selection: Binding(
                get: { model.preferences.taskStorage },
                set: { model.preferences.taskStorage = $0; model.save(actions) }
            )) {
                Text("Apple Hatırlatıcılar").tag(TaskStorageBackend.reminders)
                Text("Yalnızca bu Mac").tag(TaskStorageBackend.local)
            }
            statusRow
            Text("Hatırlatıcılar’da “Crenel” listesi kullanılır: görevler iPhone, iPad ve Watch’ta görünür; saatli görevlerin bildirimini Apple gönderir. “Üzerinde çalışılıyor” ve sıralama yalnızca bu Mac’te tutulur.")
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
            Label("Bağlı · “\(listTitle)” listesi", systemImage: "checkmark.circle")
                .foregroundStyle(MeetingNotchTheme.success)
        case .localNotConnected:
            HStack {
                Label("Hatırlatıcılar bağlı değil", systemImage: "icloud.slash")
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                Spacer()
                Button("Bağla", action: crenelActions.tasks.connectReminders)
            }
        case .localDenied:
            Label("Hatırlatıcılar izni kapalı (Sistem Ayarları › Gizlilik › Hatırlatıcılar)", systemImage: "lock")
                .foregroundStyle(MeetingNotchTheme.warning)
        case .localAfterError(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(MeetingNotchTheme.warning)
                Spacer()
                Button("Tekrar dene", action: crenelActions.tasks.connectReminders)
            }
        case .localByChoice:
            Label("Görevler bu Mac’te saklanıyor", systemImage: "desktopcomputer")
                .foregroundStyle(MeetingNotchTheme.secondaryText)
        }
    }
}

// MARK: - Building blocks

private struct CrenelSettingsCard<Content: View>: View {
    let title: String
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
                .accessibilityLabel("\(item) terimini kaldır")
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
