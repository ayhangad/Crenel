import SwiftUI

struct MeetingNotificationSettingsView: View {
    @ObservedObject var service: MeetingNotificationService
    var body: some View {
        SettingsGroup("Notifications") {
            SettingsRow(glyph: .bell, title: "Meeting notifications", detail: Text(service.status)) {
                HStack(spacing: Hud.Space.x1) {
                    Button("Allow") { Task { await service.requestAccess() } }
                        .accessibilityLabel("Allow notifications")
                    Button("Open") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .accessibilityLabel("Notification settings")
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        }
        .task { await service.refreshStatus() }
    }
}
