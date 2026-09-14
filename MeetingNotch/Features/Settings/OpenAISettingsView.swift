import SwiftUI

struct OpenAISettingsActions {
    var hasKey: () async -> Bool = { false }
    var save: (String) async -> SettingsActionResult = { _ in .failed(message: "Bağlantı kullanılamıyor.") }
    var disconnect: () async -> SettingsActionResult = { .succeeded() }
}

struct OpenAISettingsView: View {
    let actions: OpenAISettingsActions
    @State private var key = ""
    @State private var connected = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Toplantı Notları · OpenAI", systemImage: "text.badge.checkmark")
                .font(.system(size: 15, weight: .semibold))
            Text("Transkriptten özet, kararlar ve kişi bazlı görevler oluşturur. Kullanım kendi OpenAI hesabınızdan ücretlenir.")
                .font(MeetingNotchTheme.bodyFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
            LabeledContent("Bağlantı", value: connected ? "Anahtar kayıtlı" : "Anahtar gerekli")
            SecureField(connected ? "Yeni OpenAI API anahtarı" : "OpenAI API anahtarı", text: $key)
                .textFieldStyle(.roundedBorder)
            Text("Bağla işlemi, toplantı verisi içermeyen küçük bir ücretli model isteğiyle erişimi doğrular. Anahtar yalnız Keychain’de saklanır.")
                .font(.caption).foregroundStyle(MeetingNotchTheme.secondaryText)
            HStack {
                Button(connected ? "Doğrula ve Güncelle" : "Doğrula ve Bağla") {
                    busy = true
                    let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let result = await actions.save(candidate)
                        key = ""
                        await finish(result)
                    }
                }.disabled(busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if connected {
                    Button("Bağlantıyı kaldır", role: .destructive) {
                        busy = true
                        Task { await finish(actions.disconnect()) }
                    }.disabled(busy)
                }
                if busy { ProgressView().controlSize(.small) }
            }
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            Text("Model: \(OpenAIMeetingSummaryService.model). Eski toplantıları detay ekranından yeniden özetleyebilirsiniz; ses yeniden yüklenmez.")
                .font(.caption).foregroundStyle(MeetingNotchTheme.secondaryText)
        }
        .padding(16)
        .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .task { connected = await actions.hasKey() }
    }

    private func finish(_ result: SettingsActionResult) async {
        switch result {
        case .succeeded(let text): message = text
        case .failed(let text): message = text
        }
        connected = await actions.hasKey()
        busy = false
    }
}
