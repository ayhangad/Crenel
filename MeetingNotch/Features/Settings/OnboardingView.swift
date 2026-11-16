import SwiftUI

/// First run: a welcome, then one screen that sets up everything. Every capability is
/// listed with why it is needed and its live state; "Turn on all" walks through them.
/// Nothing is configured per module later.
struct OnboardingView: View {
    @ObservedObject var setup: SetupCoordinator
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step

    enum Step: String, CaseIterable {
        case welcome
        case setup
    }

    init(setup: SetupCoordinator, onComplete: @escaping () -> Void, initialStep: Step = .welcome) {
        self.setup = setup
        self.onComplete = onComplete
        _step = State(initialValue: initialStep)
    }

    private static let background = Color(white: 0.06)

    var body: some View {
        VStack(spacing: 0) {
            progressMeter
                .padding(.horizontal, Hud.Space.x8)
                .padding(.top, Hud.Space.x8 + Hud.Space.x2)

            ZStack {
                switch step {
                case .welcome:
                    welcome
                        .transition(.opacity)
                case .setup:
                    setupScreen
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 680)
        .background(Self.background)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : Hud.Motion.change, value: step)
    }

    // MARK: Progress

    /// The welcome is the first segment, then one segment per capability.
    private var progressMeter: some View {
        let total = SetupCapability.allCases.count
        let granted = SetupCapability.allCases.filter { setup.grant(for: $0) == .granted }.count
        let done = (step == .setup ? 1 : 0) + granted
        return HudSegmentMeter(segments: total + 1, progress: Double(done) / Double(total + 1))
            .accessibilityElement()
            .accessibilityLabel("\(granted) of \(total) ready")
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: Hud.Space.x6) {
            Spacer(minLength: 0)
            CrenelOrb(top: .white, bottom: Hud.Ink.text3, level: 0.25, density: 18)
                .frame(width: 200, height: 200)
            VStack(spacing: Hud.Space.x3) {
                CrenelIcon(.logo, size: 26)
                    .foregroundStyle(Hud.Ink.text1)
                Text("A helper that lives in your notch")
                    .font(Hud.font(22, .semibold))
                    .foregroundStyle(Hud.Ink.text1)
                Text("Calendar, tasks, dictation and meeting recording — all in one place, set up once.")
                    .hud(.meta, Hud.Ink.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Spacer(minLength: 0)
            Button {
                step = .setup
            } label: {
                Text("Get started").frame(minWidth: 160)
            }
            .buttonStyle(HudButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, Hud.Space.x8)
        }
        .padding(.horizontal, Hud.Space.x8)
    }

    // MARK: Setup

    private var setupScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Hud.Space.x1) {
                Text("Give Crenel what it needs")
                    .font(Hud.font(20, .semibold))
                    .foregroundStyle(Hud.Ink.text1)
                Text("All optional. Skipping a permission only turns off that feature; the rest still work.")
                    .hud(.meta, Hud.Ink.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Hud.Space.x8)
            .padding(.top, Hud.Space.x7)
            .padding(.bottom, Hud.Space.x4)

            ScrollView {
                VStack(alignment: .leading, spacing: Hud.Space.x4) {
                    group("Plan", [.calendar, .reminders, .notifications])
                    group("Audio", [.microphone, .systemAudio])
                    group("Keyboard", [.inputMonitoring, .accessibility])
                    HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x2) {
                        CrenelIcon(.shield, size: Hud.Size.smallIcon)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        Text("Dictation and the agent run on-device. Meeting audio is processed only for transcripts, and only when you start a recording.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .hud(.meta, Hud.Ink.text4)
                    .padding(.horizontal, Hud.Size.rowInset)
                    .padding(.top, Hud.Space.x2)
                }
                .padding(.horizontal, Hud.Space.x8 - Hud.Size.rowInset)
                .padding(.bottom, Hud.Space.x4)
            }
            .scrollIndicators(.never)

            HStack(spacing: Hud.Space.x2) {
                Spacer()
                if setup.allGranted {
                    Button("Open Crenel", action: onComplete)
                        .buttonStyle(HudButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not now", action: onComplete)
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                    Button {
                        Task { await setup.requestAll() }
                    } label: {
                        HStack(spacing: Hud.Space.x2) {
                            if setup.isRunningAll {
                                ProgressView().controlSize(.mini).tint(.black)
                            }
                            Text("Turn on all")
                        }
                    }
                    .buttonStyle(HudButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.isRunningAll)
                }
            }
            .padding(.horizontal, Hud.Space.x8)
            .padding(.top, Hud.Space.x3)
            .padding(.bottom, Hud.Space.x7)
        }
        .onAppear {
            setup.refresh()
            setup.watch(for: .seconds(600))
        }
        .animation(reduceMotion ? nil : Hud.Motion.change, value: setup.grants)
    }

    private func group(_ title: LocalizedStringKey, _ capabilities: [SetupCapability]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .hud(.label, Hud.Ink.text3)
                .padding(.horizontal, Hud.Size.rowInset)
                .frame(height: 22, alignment: .bottom)
                .padding(.bottom, Hud.Space.x1)
                .accessibilityAddTraits(.isHeader)
            ForEach(capabilities) { capability in
                SetupRow(capability: capability, grant: setup.grant(for: capability)) {
                    Task { await setup.request(capability) }
                }
            }
        }
    }
}

private struct SetupRow: View {
    let capability: SetupCapability
    let grant: SetupGrant
    let action: () -> Void

    var body: some View {
        HStack(spacing: Hud.Space.x3) {
            CrenelIcon(capability.glyph, size: Hud.Size.icon)
                .foregroundStyle(Hud.Ink.text3)
                .frame(width: Hud.Size.icon + 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title).hud(.body, Hud.Ink.text1)
                Text(capability.detail).hud(.meta, Hud.Ink.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: Hud.Space.x2)
            status
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
    }

    @ViewBuilder private var status: some View {
        switch grant {
        case .granted:
            Text("Connected")
                .hud(.label, Hud.Ink.ok)
                .frame(height: Hud.Size.control)
                .padding(.trailing, Hud.Space.x1)
                .transition(.opacity)
                .accessibilityLabel("\(capability.title) ready")
        case .notAsked:
            Button(capability.usesSystemPrompt ? "Allow" : "Open", action: action)
                .buttonStyle(HudButtonStyle(kind: .ghost))
                .accessibilityLabel("Allow \(capability.title)")
        case .blocked:
            Button("Open", action: action)
                .buttonStyle(HudButtonStyle(kind: .ghost))
                .help("This permission was turned off before; it can only be turned on in System Settings.")
                .accessibilityLabel("Turn on \(capability.title) in System Settings")
        }
    }
}
