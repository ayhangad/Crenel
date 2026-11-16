import SwiftUI

struct OpenAISettingsActions {
    var hasKey: () async -> Bool = { false }
    var save: (String) async -> SettingsActionResult = { _ in .failed(message: "Connection unavailable.") }
    var disconnect: () async -> SettingsActionResult = { .succeeded() }
}

struct OpenAISettingsView: View {
    let actions: OpenAISettingsActions
    @State private var key = ""
    @FocusState private var keyFocused: Bool
    @State private var connected = false
    @State private var loading = true
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        SettingsGroup("OpenAI") {
            SettingsRow(glyph: .sparkle, title: "OpenAI", detail: Text("Summaries and tasks · billed to you")) {
                if loading {
                    Text("Checking…").hud(.label, Hud.Ink.text3)
                } else if connected {
                    Text("Connected").hud(.label, Hud.Ink.ok)
                } else {
                    Text("Key required").hud(.label, Hud.Ink.text3)
                }
            }
            SettingsFieldRow {
                SecureField(connected ? "New OpenAI API key" : "OpenAI API key", text: $key)
                    .textContentType(.password)
                    .focused($keyFocused)
                    .settingsField(focused: keyFocused)
                    .accessibilityLabel("OpenAI API key")
                if busy { ProgressView().controlSize(.small).accessibilityLabel("Working") }
                Button(connected ? "Update" : "Connect") {
                    busy = true
                    let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let result = await actions.save(candidate)
                        key = ""
                        await finish(result)
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .primary))
                .disabled(loading || busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Sends a small paid test request")
                if connected {
                    Button {
                        busy = true
                        Task { await finish(actions.disconnect()) }
                    } label: {
                        Text("Remove").foregroundStyle(Hud.Ink.live)
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .disabled(busy)
                    .accessibilityLabel("Remove connection")
                }
            }
            if let message {
                SettingsNote(message, color: failed ? Hud.Ink.live : Hud.Ink.text3)
            }
        }
        .task { connected = await actions.hasKey(); loading = false }
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
