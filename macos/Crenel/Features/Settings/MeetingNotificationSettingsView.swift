import SwiftUI

/// Settings › Calendar › Notifications.
struct MeetingNotificationSettingsView: View {
    @ObservedObject var service: MeetingNotificationService
    var index = 2

    var body: some View {
        SettingsGroup("Notifications", index: index) {
            MeetingNotificationRow(status: service.status) {
                Task { await service.requestAccess() }
            }
        }
        .task { await service.refreshStatus() }
    }
}

/// The notification row: the state as a lamp or a shape, and the one way to change it.
struct MeetingNotificationRow: View {
    /// The service's status sentence.
    let status: String
    let onAllow: () -> Void

    private enum Access { case on, off, notAsked, unknown }

    private var access: Access {
        switch status {
        case "Notifications on": .on
        case "Notifications are off in System Settings": .off
        case "Notification access needed": .notAsked
        default: .unknown
        }
    }

    var body: some View {
        SettingsRow(glyph: .bell, title: "Meeting notifications",
                    detail: access == .unknown ? Text(verbatim: status) : nil) {
            switch access {
            case .on:
                HudStatusWord(.ok, "On")
                openButton
            case .off:
                HudStatusWord(.off(), "Off")
                openButton
            case .notAsked:
                HudStatusWord(.dim, "Not asked")
                HudButton("Allow", size: .small, action: onAllow)
                    .accessibilityLabel("Allow notifications")
            case .unknown:
                openButton
                HudButton("Allow", size: .small, action: onAllow)
                    .accessibilityLabel("Allow notifications")
            }
        }
    }

    private var openButton: some View {
        HudButton("Open", glyph: .link, size: .small) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        .accessibilityLabel("Notification settings")
    }
}
