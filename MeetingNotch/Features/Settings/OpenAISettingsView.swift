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
        VStack(alignment: .leading, spacing: 12) {
            Label("OpenAI", systemImage: "text.badge.checkmark")
                .font(.system(size: 15, weight: .semibold))
            Text("Summaries and tasks · Billed to your account.")
                .font(MeetingNotchTheme.bodyFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
            HStack {
                Text("Connection").foregroundStyle(MeetingNotchTheme.secondaryText)
                Spacer()
                Label(loading ? "Checking…" : connected ? "Connected" : "Key required", systemImage: loading ? "clock" : connected ? "checkmark.circle" : "key")
                    .foregroundStyle(connected ? MeetingNotchTheme.success : MeetingNotchTheme.secondaryText)
            }.font(MeetingNotchTheme.controlFont)
            SecureField(connected ? "New OpenAI API key" : "OpenAI API key", text: $key)
                .textContentType(.password)
                .focused($keyFocused)
                .meetingFieldSurface(focused: keyFocused)
                .accessibilityLabel("OpenAI API key")
            Text("Testing the connection sends a small paid request.")
                .font(.caption).foregroundStyle(MeetingNotchTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(connected ? "Update" : "Connect") {
                    busy = true
                    let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let result = await actions.save(candidate)
                        key = ""
                        await finish(result)
                    }
                }.buttonStyle(MeetingNotchActionButtonStyle(kind: .primary)).disabled(loading || busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if connected {
                    Button("Remove connection", role: .destructive) {
                        busy = true
                        Task { await finish(actions.disconnect()) }
                    }.disabled(busy)
                }
                if busy { ProgressView().controlSize(.small) }
            }
            if let message { MeetingNotchFeedback(message: message, isFailure: failed) }

        }
        .padding(20)
        .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: MeetingNotchTheme.surfaceRadius))
        .buttonStyle(MeetingNotchActionButtonStyle())
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
