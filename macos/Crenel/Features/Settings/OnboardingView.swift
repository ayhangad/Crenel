import SwiftUI

/// First run (`tpl-onboarding`): an ignition check, then one screen that switches on
/// everything. Each permission ends in a lamp; the system schematic lights the part of
/// the Mac it turns on. "Turn on all" walks through them and lights the lamps in order.
struct OnboardingView: View {
    @ObservedObject var setup: SetupCoordinator
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    /// The permissions whose lamps are lit. Follows the real grants; several arriving
    /// at once light one after another.
    @State private var lit: Set<SetupCapability>
    @State private var lighting: Task<Void, Never>?

    enum Step: String, CaseIterable {
        case welcome
        case setup
    }

    /// The window's content size.
    static let windowSize = CGSize(width: 560, height: 724)

    private static let groups: [(title: LocalizedStringKey, capabilities: [SetupCapability])] = [
        ("Plan", [.calendar, .reminders, .notifications]),
        ("Sound", [.microphone, .systemAudio]),
        ("Keyboard", [.inputMonitoring, .accessibility])
    ]
    /// Empty space inside `HudSchematic`'s 92 pt box above and below its strokes.
    private static let schematicInk = (top: CGFloat(4 - 0.75), bottom: CGFloat(92 - 84 - 0.75))
    /// Top to bottom, the order lamps light in.
    private static let order = groups.flatMap(\.capabilities)

    init(setup: SetupCoordinator, onComplete: @escaping () -> Void, initialStep: Step = .welcome) {
        self.setup = setup
        self.onComplete = onComplete
        _step = State(initialValue: initialStep)
        _lit = State(initialValue: Self.granted(setup))
    }

    private static func granted(_ setup: SetupCoordinator) -> Set<SetupCapability> {
        Set(SetupCapability.allCases.filter { setup.grant(for: $0) == .granted })
    }

    /// Prompts are up, or granted lamps are still lighting.
    private var isTurningOn: Bool { setup.isRunningAll || lit != Self.granted(setup) }
    private var isDone: Bool { setup.allGranted && !isTurningOn }

    var body: some View {
        VStack(spacing: 0) {
            stepLamps
                .padding(.top, Hud.Layout.edge)

            ZStack {
                switch step {
                case .welcome:
                    welcome.transition(.opacity)
                case .setup:
                    setupScreen.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Hud.Layer.window)
        .hudSurface(Hud.Layer.window)
        .foregroundStyle(Hud.Ink.ink1)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : Hud.Motion.change, value: step)
        .onChange(of: setup.grants) { _, _ in light() }
    }

    // MARK: Step lamps

    /// Three lamps: welcome, permissions, ready. Passed steps dim, the current one is white.
    private var stepLamps: some View {
        let current = step == .welcome ? 0 : (isDone ? 2 : 1)
        let granted = Self.granted(setup).count
        return HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                HudLamp(index == current ? .white : (index < current ? .dim : .off))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("\(granted) of \(SetupCapability.allCases.count) ready")
    }

    // MARK: Welcome (`ob-welcome`)

    private var welcome: some View {
        VStack(spacing: 0) {
            VStack(spacing: Hud.Layout.section) {
                HudGauge(value: 1, ticks: 90, major: 15, size: 220, ignite: !SettingsLayout.isTesting) {
                    VStack(spacing: 12) {
                        HudMark(width: 46, glow: 6)
                        TimelineView(.periodic(from: .now, by: 15)) { timeline in
                            HudSegmentDigits(HudFormat.clock(timeline.date), height: 16)
                        }
                    }
                }
                .accessibilityHidden(true)

                VStack(spacing: Hud.Layout.block) {
                    Text("A quiet instrument for your day")
                        .hudTrimmed(.page)
                        .accessibilityAddTraits(.isHeader)
                    Text("Crenel lives in the notch. It counts down to your meetings, keeps your tasks, types what you say and writes the notes.")
                        .hud(.read, Hud.Ink.ink3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .hudTrim(.read)
                        .frame(maxWidth: 380)
                }
            }
            .padding(.horizontal, Hud.Layout.edge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                step = .setup
            } label: {
                HudButtonLabel("Start", key: "↩").frame(minWidth: 140)
            }
            .buttonStyle(HudButtonStyle(kind: .primary, size: .large))
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, Hud.Layout.edge)
        }
    }

    // MARK: Permissions (`ob-setup`, `ob-turning`, `ob-done`)

    /// Window edge → ink 20 on every side; lamps → header → first label 28; the lists
    /// sit 10 out so their rows pad themselves (label → row 20, row → row 20, section 28).
    private var setupScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Hud.Layout.edge) {
                VStack(alignment: .leading, spacing: Hud.Layout.pair) {
                    Text("Switch on what you need")
                        .hudTrimmed(.hero)
                        .accessibilityAddTraits(.isHeader)
                    Text("Each switch turns on one feature. Skip any, the rest still work.")
                        .hudTrimmed(.meta)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HudSchematic(lit: schematicParts, scanning: isTurningOn && !SettingsLayout.isTesting)
                    // Laid out by its ink: the drawing spans y 4…84 of a 92 pt box
                    // (1.5 pt strokes), so the 28s above and below are visible gaps.
                    .padding(.top, -Self.schematicInk.top)
                    .padding(.bottom, -Self.schematicInk.bottom)
                    .help("System check")
            }
            .padding(.horizontal, Hud.Layout.edge)
            .padding(.top, Hud.Layout.section)
            .padding(.bottom, Hud.Layout.section)

            ScrollView {
                VStack(alignment: .leading, spacing: HudRowKind.icon.sectionGap) {
                    ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 0) {
                            HudGroupHeader(title: group.title, rows: .icon)
                            ForEach(group.capabilities) { capability in
                                OnboardingRow(
                                    capability: capability,
                                    grant: setup.grant(for: capability),
                                    isLit: lit.contains(capability),
                                    isTurningOn: isTurningOn
                                ) {
                                    Task { await setup.request(capability) }
                                }
                            }
                        }
                    }
                    // A note leads with its glyph in the 13 pt icon column; text on the
                    // row titles' line.
                    HStack(alignment: .top, spacing: Hud.Row.gap) {
                        HudIcon(.shield, size: Hud.Size.smallIcon)
                            .foregroundStyle(Hud.Ink.ink4)
                            .frame(width: OnboardingRow.iconColumn)
                        Text("Apple models process audio and text on your Mac. Choosing ElevenLabs or Deepgram sends meeting audio to that provider. Choosing OpenAI or Anthropic sends text to that provider. Claude Code sends meeting text to Anthropic.")
                            .hud(.meta)
                            .fixedSize(horizontal: false, vertical: true)
                            .hudTrim(.meta)
                    }
                    // No slab: the stack's 18 + the last row's 10 already make the 28.
                    .padding(.horizontal, Hud.Layout.rowPad)
                    .padding(.bottom, Hud.Layout.rowPad)
                }
                .padding(.horizontal, Hud.Layout.edge - Hud.Layout.rowPad)
            }
            .scrollIndicators(.never)

            HudActions {
                footerButtons
            }
            .padding(.horizontal, Hud.Layout.edge)
            .padding(.top, Hud.Layout.edge - Hud.Layout.rowPad)
            .padding(.bottom, Hud.Layout.edge)
        }
        .onAppear {
            setup.refresh()
            setup.watch(for: .seconds(600))
        }
    }

    @ViewBuilder private var footerButtons: some View {
        if isDone {
            HudButton("Open Crenel", key: "↩", kind: .primary, action: onComplete)
                .keyboardShortcut(.defaultAction)
        } else {
            HudButton("Not now", key: "esc", action: onComplete)
                .keyboardShortcut(.cancelAction)
            if isTurningOn {
                Button {} label: {
                    HStack(spacing: 6) {
                        OnboardingKeySpinner()
                        Text("Turning on")
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .primary))
                .allowsHitTesting(false)
                .opacity(0.6)
                .accessibilityLabel("Turning on")
            } else {
                HudButton("Turn on all", key: "↩", kind: .primary) {
                    Task { await setup.requestAll() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The parts of the schematic whose permission is on.
    private var schematicParts: Set<HudSchematic.Part> {
        var parts: Set<HudSchematic.Part> = []
        if lit.contains(.notifications) { parts.insert(.notifications) }
        if lit.contains(.systemAudio) { parts.insert(.speakers) }
        if lit.contains(.inputMonitoring) { parts.insert(.fnKey) }
        if lit.contains(.accessibility) { parts.insert(.cursor) }
        return parts
    }

    /// Lights the lamps of new grants top to bottom, 0.42 s apart; a withdrawn grant
    /// goes dark at once.
    private func light() {
        let granted = Self.granted(setup)
        lighting?.cancel()
        lit.formIntersection(granted)
        let pending = Self.order.filter { granted.contains($0) && !lit.contains($0) }
        guard !pending.isEmpty else { return }
        guard !reduceMotion, !SettingsLayout.isTesting, pending.count > 1 else {
            lit.formUnion(pending)
            return
        }
        lighting = Task {
            for (index, capability) in pending.enumerated() {
                if index > 0 {
                    try? await Task.sleep(for: .seconds(Hud.Motion.lampSequence))
                }
                guard !Task.isCancelled else { return }
                lit.insert(capability)
            }
        }
    }
}

/// One permission: glyph, name and what it turns on 7 under it, then Allow / Open — or
/// its lamp once it is on. 10 on every side, so row ink to row ink is 20.
private struct OnboardingRow: View {
    let capability: SetupCapability
    let grant: SetupGrant
    let isLit: Bool
    let isTurningOn: Bool
    let action: () -> Void

    /// A 16 pt glyph laid out by its 13 pt ink.
    static let iconColumn: CGFloat = 16 - 2 * Hud.Layout.glyphInset

    private var showsLamp: Bool { isLit || isTurningOn }

    var body: some View {
        HStack(alignment: .center, spacing: Hud.Row.gap) {
            HudIcon(capability.onboardingGlyph, size: 16)
                .foregroundStyle(Hud.Ink.ink3)
                .frame(width: 16, height: 16)
                .padding(-Hud.Layout.glyphInset)
            VStack(alignment: .leading, spacing: Hud.Layout.pair) {
                Text(capability.onboardingTitle).hudTrimmed(.body)
                Text(capability.onboardingDetail).hudTrimmed(.meta)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                // Always present so it can flash when it turns on.
                HudLamp(isLit ? .teal : .off, fires: true)
                    .opacity(showsLamp ? 1 : 0)
                if !showsLamp {
                    button
                }
            }
        }
        .hudRow(.icon)
        .accessibilityElement(children: .contain)
        .accessibilityValue(isLit ? "On" : "Off")
    }

    @ViewBuilder private var button: some View {
        switch grant {
        case .granted:
            EmptyView()
        case .notAsked where capability.usesSystemPrompt:
            HudButton("Allow", size: .small, action: action)
                .accessibilityLabel("Allow \(capability.title)")
        case .notAsked:
            HudButton("Open", glyph: .link, size: .small, action: action)
                .accessibilityLabel("Turn on \(capability.title) in System Settings")
        case .blocked:
            HudButton("Open", glyph: .link, size: .small, action: action)
                .help("This was turned off before; it can only be turned on in System Settings.")
                .accessibilityLabel("Turn on \(capability.title) in System Settings")
        }
    }
}

/// The dark ring spinner inside the lit "Turning on" key.
private struct OnboardingKeySpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            ZStack {
                Circle().stroke(Color.black.opacity(0.2), lineWidth: 1.5)
                Circle().trim(from: 0, to: 0.25)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }
            .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

private extension SetupCapability {
    var onboardingTitle: LocalizedStringKey {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notifications: "Notifications"
        case .microphone: "Microphone"
        case .systemAudio: "System audio"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    var onboardingDetail: LocalizedStringKey {
        switch self {
        case .calendar: "Countdown to your next meeting"
        case .reminders: "Tasks on your iPhone and Watch too"
        case .notifications: "A heads-up before meetings"
        case .microphone: "Your voice, for dictation and meetings"
        case .systemAudio: "Everyone else on a call"
        case .inputMonitoring: "Hold Fn to dictate"
        case .accessibility: "Typing at the cursor, mute in Zoom and Meet"
        }
    }

    var onboardingGlyph: HudGlyph {
        switch self {
        case .calendar: .calendar
        case .reminders: .queue
        case .notifications: .bell
        case .microphone: .mic
        case .systemAudio: .speaker
        case .inputMonitoring: .keyboard
        case .accessibility: .accessibility
        }
    }
}
