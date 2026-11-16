import SwiftUI

// MARK: - Surfaces

/// A layered surface lit from above: a fill plus a hairline whose top edge catches light.
private struct CrenelSurfaceModifier: ViewModifier {
    var fill: Color
    var radius: CGFloat
    var lit: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                if lit {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Crenel.Palette.highlight, Crenel.Palette.hairline.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func crenelSurface(
        _ fill: Color = Crenel.Palette.layer1,
        radius: CGFloat = Crenel.Radius.l,
        lit: Bool = true
    ) -> some View {
        modifier(CrenelSurfaceModifier(fill: fill, radius: radius, lit: lit))
    }
}

// MARK: - Buttons

struct CrenelButtonStyle: ButtonStyle {
    enum Kind: Equatable {
        /// Solid white pill: the one primary action on a surface.
        case primary
        /// Solid accent pill.
        case accent(Color)
        /// Quiet raised pill.
        case secondary
        /// Tinted glass pill.
        case tinted(Color)
        /// Text only, gains a surface on hover.
        case ghost
    }

    enum Size {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: 26
            case .regular: 32
            case .large: 40
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: 10
            case .regular: 14
            case .large: 20
            }
        }

        var font: Font {
            switch self {
            case .small: .system(size: 11.5, weight: .semibold)
            case .regular: .system(size: 12.5, weight: .semibold)
            case .large: .system(size: 13.5, weight: .semibold)
            }
        }
    }

    var kind: Kind = .secondary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        CrenelButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

private struct CrenelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CrenelButtonStyle.Kind
    let size: CrenelButtonStyle.Size
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(size.font)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size.padding)
            .frame(minHeight: size.height)
            .background(background, in: Capsule(style: .continuous))
            .overlay {
                if kind == .secondary {
                    Capsule(style: .continuous)
                        .strokeBorder(Crenel.Palette.hairline, lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .brightness(hovering && isEnabled ? 0.06 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: hovering)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .accent: .white
        case .secondary: Crenel.Palette.textPrimary
        case .tinted(let color): color
        case .ghost: hovering ? Crenel.Palette.textPrimary : Crenel.Palette.textSecondary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .white
        case .accent(let color): color
        case .secondary: Crenel.Palette.layer2
        case .tinted(let color): color.opacity(0.16)
        case .ghost: hovering ? Crenel.Palette.layer2 : .clear
        }
    }
}

/// Round icon-only button.
struct CrenelIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 30
    var tint: Color = Crenel.Palette.textSecondary
    var fill: Color? = nil
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        CrenelIconButtonBody(configuration: configuration, diameter: diameter, tint: tint, fill: fill, isActive: isActive)
    }
}

private struct CrenelIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let diameter: CGFloat
    let tint: Color
    let fill: Color?
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isActive || hovering ? activeForeground : tint)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(backgroundFill)
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: hovering)
    }

    private var activeForeground: Color {
        fill == nil ? (isActive ? tint : Crenel.Palette.textPrimary) : tint
    }

    private var backgroundFill: Color {
        if let fill { return hovering ? fill.opacity(0.9) : fill }
        if isActive { return tint.opacity(0.18) }
        return hovering ? Crenel.Palette.layer2 : .clear
    }
}

// MARK: - Row

/// A list row that lights up on hover; the whole row is the hit target.
struct CrenelRowStyle: ButtonStyle {
    var radius: CGFloat = Crenel.Radius.m
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        CrenelRowBody(configuration: configuration, radius: radius, isSelected: isSelected)
    }
}

private struct CrenelRowBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    let isSelected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? Crenel.Palette.layer2 : (hovering ? Crenel.Palette.layer1 : .clear))
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: hovering)
            .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Segmented control

/// A pill segmented control whose highlight slides between items.
struct CrenelSegmented<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var glyph: CrenelGlyph?
        var badge: Int?
        var id: Value { value }
    }

    @Binding var selection: Value
    let items: [Item]
    var compact = false
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    withAnimation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion)) {
                        selection = item.value
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let glyph = item.glyph {
                            CrenelIcon(glyph, size: 14)
                        }
                        if !compact || isSelected {
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                        }
                        if let badge = item.badge, badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(isSelected ? Crenel.Palette.textPrimary : Crenel.Palette.textTertiary)
                        }
                    }
                    .foregroundStyle(
                        isSelected
                            ? Crenel.Palette.textPrimary
                            : (hovered == item.value ? Crenel.Palette.textSecondary : Crenel.Palette.textTertiary)
                    )
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Crenel.Palette.layer3)
                                .overlay(Capsule(style: .continuous).strokeBorder(Crenel.Palette.hairline))
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Crenel.Palette.layer1, in: Capsule(style: .continuous))
        .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: hovered)
    }
}

// MARK: - Chip

struct CrenelChip: View {
    let title: String
    var glyph: CrenelGlyph?
    var tint: Color = Crenel.Palette.textSecondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let glyph {
                CrenelIcon(glyph, size: 11, weight: 2)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(tint.opacity(filled ? 0.18 : 0.10), in: Capsule(style: .continuous))
    }
}

// MARK: - Progress ring

struct CrenelProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 3
    var track: Color = Crenel.Palette.layer3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.55), radius: lineWidth * 1.4)
        }
        .padding(lineWidth / 2)
        .animation(Crenel.Motion.resolve(.smooth(duration: 0.6), reduceMotion: reduceMotion), value: progress)
    }
}

// MARK: - Key cap

/// A physical-looking key for shortcuts ("⌥ Space").
struct CrenelKeyCap: View {
    let label: String
    var large = false

    var body: some View {
        Text(label)
            .font(.system(size: large ? 26 : 10.5, weight: large ? .medium : .semibold, design: .rounded))
            .foregroundStyle(large ? Color.black.opacity(0.85) : Crenel.Palette.textSecondary)
            .padding(.horizontal, large ? 0 : 6)
            .frame(minWidth: large ? 64 : 18, minHeight: large ? 64 : 18)
            .background {
                RoundedRectangle(cornerRadius: large ? 16 : 5, style: .continuous)
                    .fill(large ? Color.white : Crenel.Palette.layer2)
                    .shadow(color: .black.opacity(large ? 0.5 : 0), radius: 0, y: large ? 4 : 0)
            }
            .overlay {
                if !large {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Crenel.Palette.hairline)
                }
            }
    }
}

// MARK: - Section header

struct CrenelSectionHeader<Trailing: View>: View {
    let title: String
    var count: Int?
    var tint: Color = Crenel.Palette.textTertiary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).eyebrow(color: tint)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Crenel.Palette.textQuaternary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Crenel.Space.xxs)
    }
}

extension CrenelSectionHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil, tint: Color = Crenel.Palette.textTertiary) {
        self.init(title: title, count: count, tint: tint) { EmptyView() }
    }
}

// MARK: - Living visuals (shaders)

/// The dot orb: Crenel's signature "alive" visual for listening, recording and setup.
struct CrenelOrb: View {
    var top: Color = .white
    var bottom: Color = Crenel.Palette.record
    var level: Double = 0
    var density: Double = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let time = Float(context.date.timeIntervalSince(start))
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .colorEffect(
                        ShaderLibrary.crenelDotOrb(
                            .float2(proxy.size),
                            .float(time),
                            .color(top),
                            .color(bottom),
                            .float(Float(max(0, min(1, level)))),
                            .float(Float(density))
                        )
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Soft drifting light behind hero content.
struct CrenelAura: View {
    var tint: Color
    var intensity: Double = 0.55
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = Float(context.date.timeIntervalSince(start))
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .colorEffect(
                        ShaderLibrary.crenelAura(
                            .float2(proxy.size),
                            .float(time),
                            .color(tint),
                            .float(Float(intensity))
                        )
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ShimmerModifier: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let time = Float(context.date.timeIntervalSince(start))
                content.visualEffect { view, proxy in
                    view.colorEffect(
                        ShaderLibrary.crenelShimmer(.float2(proxy.size), .float(time), .float(0.85))
                    )
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Sweeps a highlight across the view while work is in progress.
    func crenelShimmer(_ active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

/// A breathing status dot.
struct CrenelPulseDot: View {
    var color: Color
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color.opacity(0.5))
                    .scaleEffect(animating ? 2.4 : 1)
                    .opacity(animating ? 0 : 0.8)
            }
            .shadow(color: color.opacity(0.8), radius: 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Live level bars that rise like battlements.
struct CrenelLevelBars: View {
    var level: Double
    var tint: Color
    var barCount = 5
    var height: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = sin(t * 9 + Double(index) * 1.3) * 0.5 + 0.5
                    let shape = [0.55, 0.85, 1.0, 0.8, 0.5][index % 5]
                    let value = max(0.18, min(1, level * shape * (0.65 + 0.35 * phase) + 0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: height * value)
                }
            }
            .frame(height: height)
        }
        .animation(.smooth(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

struct CrenelEmptyState: View {
    let glyph: CrenelGlyph
    let title: String
    var detail: String?
    var tint: Color = Crenel.Palette.textTertiary

    var body: some View {
        VStack(spacing: Crenel.Space.s) {
            CrenelIcon(glyph, size: 22)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.1), in: Circle())
            Text(title).crenelText(.bodyEmphasis)
            if let detail {
                Text(detail)
                    .crenelText(.callout, color: Crenel.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Crenel.Space.xl)
    }
}
