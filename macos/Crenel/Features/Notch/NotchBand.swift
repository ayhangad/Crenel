import SwiftUI

/// The camera band of the open notch (`.band`): the row beside the camera housing is the
/// panel's chrome. Brand on the left, window · pin on the right; the middle belongs to the
/// camera. The tabs (Today · Recordings · Tasks) sit on their own row under it, so they
/// never crowd the housing. Both stay put while the content scrolls.
struct NotchBand: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotchBandRow {
                // On a housing too wide for the word, the lit mark stays.
                ViewThatFits(in: .horizontal) {
                    HudBrand()
                    HudMark().accessibilityLabel(Text(verbatim: "Crenel"))
                }
                .padding(.leading, -2)
            } trailing: {
                HStack(spacing: 2) {
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

            tabs
                .frame(height: Hud.Notch.tabRowHeight, alignment: .bottom)
                .padding(.horizontal, Hud.Notch.openInset)
        }
    }

    private var tabs: some View {
        HudTabs<AppState.PanelTab>(
            items: AppState.PanelTab.allCases.map { tab in
                .init(tab: tab, title: tab.bandTitle,
                      badge: tab == .tasks && appState.activeTaskCount > 0 ? appState.activeTaskCount : nil)
            },
            selection: $appState.selectedTab
        )
        .background {
            // ⌘1 / ⌘2 / ⌘3 switch surfaces.
            ForEach(AppState.PanelTab.allCases) { tab in
                Button("") { appState.selectedTab = tab }
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
        case .recordings: "2"
        case .tasks: "3"
        }
    }

    var bandTitle: String {
        switch self {
        case .meetings: String(localized: "Today")
        case .recordings: String(localized: "Recordings")
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
