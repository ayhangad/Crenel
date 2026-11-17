import SwiftUI

/// The camera band of the open notch (`.band`): the row beside the camera housing is the
/// panel's chrome. Brand and tabs on the left, Recordings · window · pin on the right;
/// the middle belongs to the camera. It stays put while the content scrolls.
struct NotchBand: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelNotchMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showsHistory: Bool
    let onTogglePin: () -> Void

    var body: some View {
        NotchBandRow {
            // The brand and the tabs must fit beside the camera; on a wider housing the
            // word goes and the lit mark stays.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    HudBrand()
                    tabs
                }
                HStack(spacing: 12) {
                    HudMark().accessibilityLabel(Text(verbatim: "Crenel"))
                    tabs
                }
                tabs
            }
            .padding(.leading, -2)
        } trailing: {
            HStack(spacing: 2) {
                HudIconButton(.tape, isOn: showsHistory, help: "Recordings") {
                    showsHistory.toggle()
                }
                .accessibilityAddTraits(showsHistory ? .isSelected : [])

                HudIconButton(.window, help: "Open in window") {
                    NotificationCenter.default.post(name: .openDesktopWorkspace, object: nil)
                }

                Button(action: onTogglePin) {
                    HudIcon(.pin, size: 16)
                        .rotationEffect(.degrees(appState.isNotchPinned ? 0 : 30))
                }
                .buttonStyle(HudButtonStyle(kind: .icon, isOn: appState.isNotchPinned))
                .animation(reduceMotion ? nil : Hud.Motion.slab, value: appState.isNotchPinned)
                .help(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
                .accessibilityLabel(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
                .accessibilityValue(appState.isNotchPinned ? "Pinned" : "Not pinned")
            }
        }
    }

    private var tabs: some View {
        // On the Recordings page neither tab is lit: the lamp is under the tape icon.
        HudTabs<AppState.PanelTab?>(
            items: [
                .init(tab: AppState.PanelTab.meetings, title: AppState.PanelTab.meetings.bandTitle),
                .init(tab: AppState.PanelTab.tasks, title: AppState.PanelTab.tasks.bandTitle,
                      badge: appState.activeTaskCount > 0 ? appState.activeTaskCount : nil)
            ],
            selection: Binding(
                get: { showsHistory ? nil : appState.selectedTab },
                set: { tab in
                    showsHistory = false
                    if let tab { appState.selectedTab = tab }
                }
            )
        )
        .background {
            // ⌘1 / ⌘2 switch surfaces.
            ForEach(AppState.PanelTab.allCases) { tab in
                Button("") {
                    showsHistory = false
                    appState.selectedTab = tab
                }
                .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel tabs")
    }
}

/// The band's grid (`1fr 186px 1fr`): two equal sides and the camera housing between
/// them. On a screen without a notch the sides simply share the row.
struct NotchBandRow<Leading: View, Trailing: View>: View {
    @Environment(\.crenelNotchMetrics) private var metrics
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: metrics.hasPhysicalNotch ? metrics.hardware.width : 0, height: 1)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Hud.Notch.openInset)
        .frame(height: max(metrics.topInset, Hud.Notch.bandHeight))
    }
}

private extension AppState.PanelTab {
    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .meetings: "1"
        case .tasks: "2"
        }
    }

    var bandTitle: String {
        switch self {
        case .meetings: String(localized: "Today")
        case .tasks: String(localized: "Tasks")
        }
    }
}

// MARK: - Ignition

private struct NotchPanelIgnitesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for views created while the notch panel is opening from closed. Pass it to
    /// `HudGauge(ignite:)` / `HudVUMeter(ignite:)` so instruments sweep once per open and
    /// not again on a tab change.
    var notchPanelIgnites: Bool {
        get { self[NotchPanelIgnitesKey.self] }
        set { self[NotchPanelIgnitesKey.self] = newValue }
    }
}

enum NotchPanelIgnition {
    /// Views created within this long of the panel opening take part in the ignition.
    static let window: TimeInterval = 0.6

    static func ignites(openedAt: Date?, now: Date = Date(), reduceMotion: Bool) -> Bool {
        guard let openedAt, !reduceMotion else { return false }
        let elapsed = now.timeIntervalSince(openedAt)
        return elapsed >= 0 && elapsed < window
    }
}
