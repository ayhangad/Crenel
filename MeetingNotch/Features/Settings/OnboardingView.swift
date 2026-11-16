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
            Color.black
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
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .animation(Crenel.Motion.resolve(Crenel.Motion.morph, reduceMotion: reduceMotion), value: step)
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: Crenel.Space.xxl) {
            Spacer(minLength: 0)
            CrenelOrb(top: .white, bottom: Crenel.Palette.calendar, level: 0.25, density: 18)
                .frame(width: 220, height: 220)
            VStack(spacing: Crenel.Space.m) {
                CrenelIcon(.logo, size: 30)
                    .foregroundStyle(Crenel.Palette.textPrimary)
                Text("Notch’unuzda yaşayan yardımcı")
                    .crenelText(.title)
                    .font(.system(size: 26, weight: .semibold))
                Text("Takvim, görevler, dikte ve toplantı kaydı — hepsi tek bir yerde, tek seferde kurulur.")
                    .crenelText(.body, color: Crenel.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            Spacer(minLength: 0)
            Button {
                step = .setup
            } label: {
                Text("Başlayalım").frame(minWidth: 180)
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
                Text("Kurulum").eyebrow(color: Crenel.Palette.calendar)
                Text("Crenel’e ihtiyacı olanı verin")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Crenel.Palette.textPrimary)
                Text("Hepsi isteğe bağlı. Vermediğiniz izin yalnız o özelliği kapatır; diğerleri çalışır.")
                    .crenelText(.callout, color: Crenel.Palette.textTertiary)
            }
            .padding(.horizontal, Crenel.Space.xxl)
            .padding(.top, Crenel.Space.xxxl + Crenel.Space.s)
            .padding(.bottom, Crenel.Space.xl)

            ScrollView {
                VStack(spacing: Crenel.Space.l) {
                    group("Plan", [.calendar, .reminders, .notifications])
                    group("Ses", [.microphone, .systemAudio])
                    group("Klavye", [.inputMonitoring, .accessibility])
                    HStack(alignment: .top, spacing: Crenel.Space.s) {
                        CrenelIcon(.shield, size: 14)
                        Text("Dikte ve agent cihazda çalışır. Toplantı sesi yalnız transkript için, siz kayıt başlattığınızda işlenir.")
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
                    Button("Crenel’i aç", action: onComplete)
                        .buttonStyle(CrenelButtonStyle(kind: .primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Şimdilik bu kadar", action: onComplete)
                        .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .large))
                    Button {
                        Task { await setup.requestAll() }
                    } label: {
                        HStack(spacing: Crenel.Space.s) {
                            if setup.isRunningAll {
                                ProgressView().controlSize(.small).tint(.black)
                            }
                            Text("Hepsini aç")
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
            CrenelProgressRing(progress: Double(granted) / Double(total), tint: Crenel.Palette.success, lineWidth: 2.5)
                .frame(width: 18, height: 18)
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
                        Rectangle().fill(Crenel.Palette.hairline).frame(height: 1).padding(.leading, 56)
                    }
                }
            }
            .crenelSurface(Crenel.Palette.layer1, radius: Crenel.Radius.l)
        }
    }
}

private struct SetupRow: View {
    let capability: SetupCapability
    let grant: SetupGrant
    let action: () -> Void

    var body: some View {
        HStack(spacing: Crenel.Space.m) {
            CrenelIcon(capability.glyph, size: 16)
                .foregroundStyle(grant == .granted ? Crenel.Palette.success : Crenel.Palette.textPrimary)
                .frame(width: 32, height: 32)
                .background((grant == .granted ? Crenel.Palette.success : Color.white).opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title).crenelText(.bodyEmphasis)
                Text(capability.detail).crenelText(.caption, color: Crenel.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Crenel.Space.s)
            switch grant {
            case .granted:
                HStack(spacing: 4) {
                    CrenelIcon(.check, size: 12, weight: 2.4)
                    Text("Hazır")
                }
                .crenelText(.callout, color: Crenel.Palette.success)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .accessibilityLabel("\(capability.title) hazır")
            case .notAsked:
                Button(capability.usesSystemPrompt ? "İzin ver" : "Aç", action: action)
                    .buttonStyle(CrenelButtonStyle(kind: .secondary, size: .small))
                    .accessibilityLabel("\(capability.title) iznini ver")
            case .blocked:
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text("Ayarlar’da aç")
                        CrenelIcon(.arrowUpRight, size: 10, weight: 2.2)
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.warning), size: .small))
                .help("Bu izin daha önce kapatılmış; yalnızca Sistem Ayarları’ndan açılabilir.")
                .accessibilityLabel("\(capability.title) iznini Sistem Ayarları’nda aç")
            }
        }
        .padding(.horizontal, Crenel.Space.m)
        .padding(.vertical, Crenel.Space.m)
    }
}
