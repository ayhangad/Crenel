import SwiftUI

struct GoogleCalendarSettingsActions {
    var configured = false
    var connected: () async -> Bool = { false }
    var connect: () async -> SettingsActionResult = { .failed(message: GoogleCalendarError.notConfigured.localizedDescription) }
    var disconnect: () async -> SettingsActionResult = { .succeeded() }
}

struct GoogleCalendarSettingsView: View {
    let actions: GoogleCalendarSettingsActions
    @State private var connected = false
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Google Calendar", systemImage: "calendar")
                .font(.system(size: 15, weight: .semibold))
            Text(actions.configured
                 ? "Google hesabınızı tarayıcıda seçin. Yalnız takvim ve etkinlikler okunur; Gmail’e erişilmez."
                 : "Google hesabınızı Sistem Ayarları → İnternet Hesapları’ndan ekleyin. Ardından aşağıdan takvim erişimini açın.")
                .font(.callout).foregroundStyle(MeetingNotchTheme.secondaryText)
            if actions.configured {
                HStack {
                    Button(connected ? "Google bağlantısını yenile" : "Google hesabını bağla") {
                        busy = true
                        Task { await finish(actions.connect()) }
                    }.disabled(busy)
                    if connected || busy {
                        Button(busy ? "İptal et" : "Bağlantıyı kaldır") {
                            Task { await finish(actions.disconnect()) }
                        }
                    }
                    if busy { ProgressView().controlSize(.small) }
                }
            }
            if let message { MeetingNotchFeedback(message: message, isFailure: failed) }
        }.padding(20)
            .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: MeetingNotchTheme.surfaceRadius))
            .buttonStyle(MeetingNotchActionButtonStyle())
        .task { connected = await actions.connected() }
    }
    private func finish(_ result: SettingsActionResult) async {
        switch result {
        case .succeeded(let text): message = text ?? "Bağlantı güncellendi."; failed = false
        case .failed(let text): message = text; failed = true
        }
        connected = await actions.connected()
        busy = false
    }
}
