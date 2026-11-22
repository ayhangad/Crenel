import SwiftUI

private struct DesktopRailBoundsKey: PreferenceKey {
    static let defaultValue: [DesktopSection: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DesktopSection: Anchor<CGRect>], nextValue: () -> [DesktopSection: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The sidebar (`.sidebar`, 224 pt): brand and clock, the four places, the live card
/// while recording, the Systems telltales, and Settings. One lamp slides along the rail.
struct DesktopSidebar: View {
    let actions: DesktopActions
    @ObservedObject var navigation: DesktopNavigation
    @ObservedObject var preferences: DesktopPreferencesModel
    let openSettings: (SettingsCategory) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: DesktopSection?

    var body: some View {
        DesktopClock { now in
            VStack(alignment: .leading, spacing: 0) {
                brand(now: now)
                VStack(alignment: .leading, spacing: 2) {
                    item(.today, readout: todayReadout(now: now))
                    item(.meetings, readout: appState.storedMeetings.isEmpty ? nil : "\(appState.storedMeetings.count)")
                    item(.tasks, readout: appState.activeTaskCount > 0 ? "\(appState.activeTaskCount)" : nil)
                    item(.dictation, readout: preferences.keyLabel)
                    Spacer(minLength: 8)
                    if case .recording(let startedAt) = appState.meetingFlow {
                        DesktopRecordingCard(actions: actions, startedAt: startedAt)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                    systems
                        .padding(.bottom, 8)
                    item(.settings, readout: "⌘,")
                        .keyboardShortcut(",", modifiers: .command)
                }
                .overlayPreferenceValue(DesktopRailBoundsKey.self) { anchors in
                    GeometryReader { proxy in
                        if let anchor = anchors[navigation.section] {
                            let rect = proxy[anchor]
                            Capsule().fill(Hud.Ink.ink1)
                                .shadow(color: Hud.Ink.ink1.opacity(0.75), radius: 3)
                                .shadow(color: Hud.Ink.ink1.opacity(0.22), radius: 7)
                                .frame(width: 3, height: 14)
                                .offset(x: 0, y: rect.midY - 7)
                                .animation(reduceMotion ? nil : Hud.Motion.railLamp, value: rect)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: Hud.Window.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Hud.Layer.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(white: 1, opacity: 0.035)).frame(width: 1)
        }
        .hudSurface(Hud.Layer.sidebar)
        .animation(reduceMotion ? nil : Hud.Motion.card, value: appState.meetingFlow.isRecording)
        .animation(Hud.Motion.hover, value: hovered)
    }

    // MARK: Brand

    private func brand(now: Date) -> some View {
        HStack(spacing: 10) {
            Button(action: actions.showNotch) {
                HStack(spacing: 10) {
                    HudAppTile()
                    Text(verbatim: "Crenel").font(Hud.font(13, .semibold)).foregroundStyle(Hud.Ink.ink1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show notch")
            .accessibilityLabel("Show notch")
            Spacer(minLength: 4)
            HudSegmentDigits(DesktopFormat.clock(now), height: 10, color: Hud.Ink.ink3, glows: false)
                .help(DesktopFormat.format(now, "EEE d MMM"))
                .accessibilityLabel(Text(now, style: .time))
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.top, 50)
        .padding(.bottom, 20)
    }

    // MARK: Rail

    private func todayReadout(now: Date) -> String? {
        guard let status = NotchAgendaStatus.resolve(items: appState.upcomingMeetings, now: now) else { return nil }
        switch status.phase {
        case .upcoming(let startsIn): return "in \(NotchAgendaFormatter.durationText(startsIn))"
        case .ongoing: return "now"
        }
    }

    private func item(_ section: DesktopSection, readout: String?) -> some View {
        let isSelected = navigation.section == section
        return Button {
            navigation.section = section
        } label: {
            HStack(spacing: 12) {
                HudIcon(section.glyph, size: 16, solid: isSelected)
                    .foregroundStyle(isSelected ? Hud.Ink.ink1 : Hud.Ink.ink3)
                Text(verbatim: section.title).hud(.label, isSelected ? Hud.Ink.ink1 : Hud.Ink.ink2)
                Spacer(minLength: 4)
                if let readout {
                    Text(verbatim: readout).hud(.meta, isSelected ? Hud.Ink.ink3 : Hud.Ink.ink4)
                }
            }
            .lineLimit(1)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: Hud.Window.railItem)
            .background {
                let shape = RoundedRectangle(cornerRadius: Hud.Layout.hitRadius, style: .continuous)
                if isSelected {
                    shape.fill(LinearGradient(colors: [Color(white: 1, opacity: 0.075), Color(white: 1, opacity: 0.04)],
                                              startPoint: .leading, endPoint: .trailing))
                } else if hovered == section {
                    shape.fill(Color(white: 1, opacity: 0.04))
                }
            }
            .contentShape(Rectangle())
            .anchorPreference(key: DesktopRailBoundsKey.self, value: .bounds) { [section: $0] }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? section : (hovered == section ? nil : hovered) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Systems

    private var systems: some View {
        let all = DesktopSystem.all(appState)
        let needsUser = all.contains(where: \.needsUser)
        return VStack(alignment: .leading, spacing: Hud.Layout.label) {
            HStack(alignment: .lastTextBaseline) {
                Text("Systems").hudTrimmed(.section)
                Spacer(minLength: 4)
                if needsUser {
                    Text("needs you").hudTrimmed(.micro, Hud.Ink.signal)
                } else {
                    Text(verbatim: "\(all.filter(\.isOn).count) of \(all.count) on").hudTrimmed(.micro)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { offset, system in
                    if offset > 0 { Spacer(minLength: 0) }
                    Button { openSettings(system.category) } label: {
                        HudTelltale(system.glyph, system.state, paren: system.paren, badge: system.badge)
                            .frame(height: 16)
                            .padding(.vertical, -Hud.Layout.glyphInset)
                            .contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain)
                    .help(system.help)
                    .accessibilityLabel(Text(verbatim: system.help))
                }
            }
            .padding(.trailing, 2)
        }
        .padding(Hud.Space.x3)
        .accessibilityElement(children: .contain)
    }
}

/// The live card (`.well`) under the rail while recording: the notch's instruments, smaller.
private struct DesktopRecordingCard: View {
    let actions: DesktopActions
    let startedAt: Date
    @EnvironmentObject private var appState: AppState
    @Environment(\.desktopFixedNow) private var fixedNow

    var body: some View {
        VStack(alignment: .leading, spacing: Hud.Layout.block) {
            HStack(spacing: 12) {
                HudLamp(.red, form: .dot, loop: fixedNow == nil ? .pulse : .steady).frame(width: 13)
                Text("Recording").hudTrimmed(.label, Hud.Ink.ink1)
                Spacer(minLength: 4)
                HudLadder(level: level, quiet: !micOpen && level < 0.02).desktopInline()
            }
            HStack(alignment: .firstTextBaseline) {
                elapsed
                Spacer(minLength: 8)
                if let title {
                    Text(verbatim: title).hudTrimmed(.meta).truncationMode(.tail)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                HudIconButton(micOpen ? .mic : .micOff, framed: true, small: true,
                              help: appState.meetingMicrophoneGate?.nextManualState == .closed
                                  ? "Turn your mic off (⌥⌘M)" : "Turn your mic on (⌥⌘M)", action: actions.toggleMicrophone)
                Button(action: actions.stopRecording) {
                    HStack(spacing: 5) {
                        HudIcon(.stop, size: 12).foregroundStyle(Hud.Ink.live)
                        Text("Stop")
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .secondary, size: .small))
                .accessibilityLabel("Stop recording")
            }
        }
        .padding(Hud.Layout.edge)
        .hudWell()
    }

    @ViewBuilder private var elapsed: some View {
        if let fixedNow {
            HudSegmentDigits(DesktopFormat.length(fixedNow.timeIntervalSince(startedAt)), height: 22)
        } else {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                HudSegmentDigits(DesktopFormat.length(context.date.timeIntervalSince(startedAt)), height: 22)
            }
        }
    }

    private var micOpen: Bool { appState.meetingMicrophoneGate?.permitsAudio ?? true }

    private var level: Double {
        Double(max(appState.recordingCaptureStatus.microphone.level, appState.recordingCaptureStatus.systemAudio.level))
    }

    /// The calendar meeting this recording belongs to, when there is exactly one candidate.
    private var title: String? {
        RecordingMeetingContext.resolve(meetings: appState.upcomingMeetings, session: nil, now: fixedNow ?? Date())?.title
    }
}
