import SwiftUI

struct OpenAISettingsActions {
    var hasKey: () async -> Bool = { false }
    var save: (String) async -> SettingsActionResult = { _ in .failed(message: "Connection unavailable.") }
    var disconnect: () async -> SettingsActionResult = { .succeeded() }
}

/// Settings › AI › OpenAI: the key's state, a field with its save key beside it, and
/// Remove on the status row.
struct OpenAISettingsView: View {
    let actions: OpenAISettingsActions
    /// nil while the key is being looked up. The AI page reads it for its fallback chain.
    @Binding var connected: Bool?
    var index = 4

    @State private var key = ""
    @FocusState private var keyFocused: Bool
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false

    private var isConnected: Bool { connected == true }

    var body: some View {
        SettingsGroup("OpenAI", index: index) {
            SettingsRow(glyph: .spark, title: "OpenAI", detail: Text("Notes and tasks · billed to you")) {
                if connected == nil {
                    HudStatusWord(.dim, "Checking…")
                } else if isConnected {
                    HudStatusWord(.ok, "Connected")
                    HudButton("Remove", kind: .danger, size: .small) {
                        busy = true
                        Task { await finish(actions.disconnect()) }
                    }
                    .disabled(busy)
                    .accessibilityLabel("Remove OpenAI key")
                } else {
                    HudStatusWord(.dim, "No key")
                }
            }
            SettingsFieldRow {
                SecureField("", text: $key,
                            prompt: Text(isConnected ? "New OpenAI API key" : "OpenAI API key").foregroundStyle(Hud.Ink.ink3))
                    .textFieldStyle(.plain)
                    .textContentType(.password)
                    .hud(.body)
                    .focused($keyFocused)
                    .hudField(isFocused: keyFocused)
                    .onSubmit(save)
                    .accessibilityLabel("OpenAI API key")
                if busy { HudSpinner() }
                HudButton(isConnected ? "Update" : "Connect", action: save)
                    .disabled(!canSave)
                    .help("Sends a small paid test request")
            }
            SettingsMessage(message: message, failed: failed)
        }
        .task { connected = await actions.hasKey() }
    }

    private var canSave: Bool {
        connected != nil && !busy && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        busy = true
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await actions.save(candidate)
            key = ""
            await finish(result)
        }
    }

    private func finish(_ result: SettingsActionResult) async {
        switch result {
        case .succeeded(let text): message = text ?? "Connection updated."; failed = false
        case .failed(let text): message = text; failed = true
        }
        connected = await actions.hasKey()
        busy = false
    }
}
