import SwiftUI

/// First run: a welcome, then one screen that sets up everything. Every capability is
/// listed with why it is needed and its live state; "Hepsini aç" walks through them.
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

    var body: some View {
        ZStack {
            Crenel.Palette.ink
            switch step {
            case .welcome:
                welcome
                    .transition(.crenelMorph(anchor: .center))
            case .setup:
                setupScreen
                    .transition(.crenelMorph(anchor: .center))
            }
        }
        .frame(width: 560, height: 680)
        .background(Crenel.Palette.ink)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .animation(Crenel.Motion.resolve(Crenel.Motion.morph, reduceMotion: reduceMotion), value: step)
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: Crenel.Space.xxl) {
            Spacer(minLength: 0)
            WelcomeMark()
            VStack(spacing: Crenel.Space.m) {
                Text("crenel")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Crenel.Palette.textPrimary)
                Text("notch’unuzdaki yardımcı.\ntakvim, görevler, dikte ve toplantı kaydı — tek seferde kurulur.")
                    .crenelText(.callout, color: Crenel.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }
            Spacer(minLength: 0)
            Button {
                step = .setup
            } label: {
                HStack(spacing: Crenel.Space.s) {
                    Text("başlayalım")
                    CrenelIcon(.chevronRight, size: 9)
                }
                .frame(minWidth: 160)
            }
            .buttonStyle(CrenelButtonStyle(kind: .primary, size: .large))
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, Crenel.Space.xxxl)
        }
        .padding(.horizontal, Crenel.Space.xxxl)
    }

    // MARK: Setup

    private var setupScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Crenel.Space.s) {
                Text("kurulum").eyebrow(color: Crenel.Palette.brand)
                Text("crenel’e ihtiyacı olanı verin")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Crenel.Palette.textPrimary)
                Text("hepsi isteğe bağlı. vermediğiniz izin yalnız o özelliği kapatır.")
                    .crenelText(.callout, color: Crenel.Palette.textTertiary)
            }
            .padding(.horizontal, Crenel.Space.xxl)
            .padding(.top, Crenel.Space.xxxl + Crenel.Space.s)
            .padding(.bottom, Crenel.Space.xl)

            ScrollView {
                VStack(spacing: Crenel.Space.l) {
                    group("plan", [.calendar, .reminders, .notifications])
                    group("ses", [.microphone, .systemAudio])
                    group("klavye", [.inputMonitoring, .accessibility])
                    HStack(alignment: .top, spacing: Crenel.Space.s) {
                        CrenelIcon(.shield, size: 9)
                        Text("dikte ve agent cihazda çalışır. toplantı sesi yalnız siz kayıt başlattığınızda, transkript için işlenir.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .crenelText(.caption, color: Crenel.Palette.textTertiary)
                    .padding(.horizontal, Crenel.Space.xs)
                }
                .padding(.horizontal, Crenel.Space.xxl)
                .padding(.bottom, Crenel.Space.l)
            }
            .scrollIndicators(.never)

            HStack(spacing: Crenel.Space.m) {
                progressSummary
                Spacer()
                if setup.allGranted {
                    Button("crenel’i aç", action: onComplete)
                        .buttonStyle(CrenelButtonStyle(kind: .primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("şimdilik bu kadar", action: onComplete)
                        .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .large))
                    Button {
                        Task { await setup.requestAll() }
                    } label: {
                        HStack(spacing: Crenel.Space.s) {
                            if setup.isRunningAll {
                                CrenelSpinner(tint: Crenel.Palette.ink)
                            }
                            Text("hepsini aç")
                        }
                    }
                    .buttonStyle(CrenelButtonStyle(kind: .primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.isRunningAll)
                }
            }
            .padding(.horizontal, Crenel.Space.xxl)
            .padding(.vertical, Crenel.Space.xl)
            .background(alignment: .top) {
                Rectangle().fill(Crenel.Palette.hairline).frame(height: 1)
            }
        }
        .onAppear {
            setup.refresh()
            setup.watch(for: .seconds(600))
        }
        .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: setup.grants)
    }

    private var progressSummary: some View {
        let granted = SetupCapability.allCases.filter { setup.grant(for: $0) == .granted }.count
        let total = SetupCapability.allCases.count
        return HStack(spacing: Crenel.Space.s) {
            CrenelPixelMeter(progress: Double(granted) / Double(total), tint: Crenel.Palette.success, segments: total, height: 6)
                .frame(width: 70)
            Text("\(granted)/\(total) hazır")
                .crenelText(.caption, color: Crenel.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func group(_ title: String, _ capabilities: [SetupCapability]) -> some View {
        VStack(alignment: .leading, spacing: Crenel.Space.s) {
            Text(title).eyebrow()
                .padding(.horizontal, Crenel.Space.xs)
            VStack(spacing: 0) {
                ForEach(Array(capabilities.enumerated()), id: \.element) { index, capability in
                    SetupRow(capability: capability, grant: setup.grant(for: capability)) {
                        Task { await setup.request(capability) }
                    }
                    if index < capabilities.count - 1 {
                        Rectangle().fill(Crenel.Palette.hairline).frame(height: 1).padding(.leading, 48)
                    }
                }
            }
            .crenelSurface()
        }
    }
}

private struct SetupRow: View {
    let capability: SetupCapability
    let grant: SetupGrant
    let action: () -> Void

    var body: some View {
        HStack(spacing: Crenel.Space.m) {
            CrenelIcon(capability.glyph, size: 13.5)
                .foregroundStyle(grant == .granted ? Crenel.Palette.success : Crenel.Palette.textPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title.lowercased(with: Locale(identifier: "tr_TR"))).crenelText(.bodyEmphasis)
                Text(capability.detail.lowercased(with: Locale(identifier: "tr_TR")))
                    .crenelText(.caption, color: Crenel.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Crenel.Space.s)
            switch grant {
            case .granted:
                HStack(spacing: 6) {
                    CrenelIcon(.check, size: 9)
                    Text("hazır")
                }
                .crenelText(.callout, color: Crenel.Palette.success)
                .transition(.crenelPixel)
                .accessibilityLabel("\(capability.title) hazır")
            case .notAsked:
                Button(capability.usesSystemPrompt ? "izin ver" : "aç", action: action)
                    .buttonStyle(CrenelButtonStyle(kind: .secondary, size: .small))
                    .accessibilityLabel("\(capability.title) iznini ver")
            case .blocked:
                Button(action: action) {
                    HStack(spacing: 6) {
                        Text("ayarlar’da aç")
                        CrenelIcon(.arrowUpRight, size: 9)
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.warning), size: .small))
                .help("Bu izin daha önce kapatılmış; yalnızca Sistem Ayarları’ndan açılabilir.")
                .accessibilityLabel("\(capability.title) iznini Sistem Ayarları’nda aç")
            }
        }
        .padding(.horizontal, Crenel.Space.m)
        .frame(minHeight: 52)
    }
}

/// The crenel mark resolving pixel by pixel inside a frame of travelling light.
private struct WelcomeMark: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PixelCornerShape(step: 4, steps: 3)
                .fill(Crenel.Palette.layer1)
            if shown {
                CrenelIcon(.logo, size: 90)
                    .foregroundStyle(Crenel.Palette.brand)
                    .transition(.crenelPixel)
            }
        }
        .frame(width: 180, height: 180)
        .crenelBeam(true, tint: Crenel.Palette.brand, level: 0.4, speed: 0.35, lineWidth: 1.5, shape: PixelCornerShape(step: 4, steps: 3))
        .onAppear {
            withAnimation(Crenel.Motion.resolve(.easeOut(duration: 0.9).delay(0.15), reduceMotion: reduceMotion)) {
                shown = true
            }
        }
        .accessibilityHidden(true)
    }
}
