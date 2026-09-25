import SwiftUI

struct MeetingNotificationSettingsView: View {
    @ObservedObject var service: MeetingNotificationService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Toplantı Bildirimleri", systemImage: "bell.badge")
                .font(.system(size: 15, weight: .semibold))
            Text(service.status).font(MeetingNotchTheme.bodyFont)
            HStack {
                Button("Bildirimlere izin ver") { Task { await service.requestAccess() } }
                Button("Bildirim ayarları") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(20)
        .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: MeetingNotchTheme.surfaceRadius))
        .buttonStyle(MeetingNotchActionButtonStyle())
        .task { await service.refreshStatus() }
    }
}
