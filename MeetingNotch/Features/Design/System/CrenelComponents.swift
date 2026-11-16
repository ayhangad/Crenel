import SwiftUI

// MARK: - The crenel corner

/// A rectangle whose corners are cut in pixel steps — the crenel, Crenel's shape for
/// every control and card.
struct PixelCornerShape: InsettableShape {
    /// Size of one step.
    var step: CGFloat = Crenel.Radius.step
    /// Number of steps per corner.
    var steps: Int = 2
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> PixelCornerShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in fullRect: CGRect) -> Path {
        let rect = fullRect.insetBy(dx: inset, dy: inset)
        let cut = min(step * CGFloat(steps), rect.width / 2, rect.height / 2)
        let s = cut / CGFloat(max(1, steps))
        var path = Path()
        func corner(_ start: CGPoint, dx: CGFloat, dy: CGFloat, horizontalFirst: Bool) {
            var point = start
            for _ in 0..<steps {
                if horizontalFirst {
                    point.x += dx * s; path.addLine(to: point)
                    point.y += dy * s; path.addLine(to: point)
                } else {
                    point.y += dy * s; path.addLine(to: point)
                    point.x += dx * s; path.addLine(to: point)
                }
            }
        }
        // Top edge, left to right, then each corner stepping inward-out.
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        corner(CGPoint(x: rect.maxX - cut, y: rect.minY), dx: 1, dy: 1, horizontalFirst: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        corner(CGPoint(x: rect.maxX, y: rect.maxY - cut), dx: -1, dy: 1, horizontalFirst: true)
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        corner(CGPoint(x: rect.minX + cut, y: rect.maxY), dx: -1, dy: -1, horizontalFirst: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        corner(CGPoint(x: rect.minX, y: rect.minY + cut), dx: 1, dy: -1, horizontalFirst: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Surfaces

private struct CrenelSurfaceModifier: ViewModifier {
    var fill: Color
    var stroke: Color
    var steps: Int

    func body(content: Content) -> some View {
        content
            .background(PixelCornerShape(steps: steps).fill(fill))
            .overlay(PixelCornerShape(steps: steps).stroke(stroke, lineWidth: 1).allowsHitTesting(false))
    }
}

extension View {
    /// A pixel-cornered panel with a 1 pt outline.
    func crenelSurface(
        _ fill: Color = Crenel.Palette.layer1,
        stroke: Color = Crenel.Palette.hairline,
        steps: Int = 3
    ) -> some View {
        modifier(CrenelSurfaceModifier(fill: fill, stroke: stroke, steps: steps))
    }
}

// MARK: - Buttons

struct CrenelButtonStyle: ButtonStyle {
    enum Kind: Equatable {
        /// Solid light block: the one primary action on a surface.
        case primary
        /// Solid colour block.
        case accent(Color)
        /// Outlined block.
        case secondary
        /// Colour-tinted block.
        case tinted(Color)
        /// Text only; gains a surface on hover.
        case ghost
    }

    enum Size {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: 24
            case .regular: 30
            case .large: 38
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: 8
            case .regular: 12
            case .large: 18
            }
        }

        var font: Font {
            switch self {
            case .small: .system(size: 11.5, weight: .semibold, design: .monospaced)
            case .regular: .system(size: 12.5, weight: .semibold, design: .monospaced)
            case .large: .system(size: 13.5, weight: .semibold, design: .monospaced)
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
            .background(PixelCornerShape().fill(background))
            .overlay {
                if kind == .secondary {
                    PixelCornerShape().stroke(hovering ? Crenel.Palette.textTertiary : Crenel.Palette.stroke, lineWidth: 1)
                }
            }
            .contentShape(PixelCornerShape())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovering)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Crenel.Palette.ink
        case .accent: Crenel.Palette.ink
        case .secondary: Crenel.Palette.textPrimary
        case .tinted(let color): color
        case .ghost: hovering ? Crenel.Palette.textPrimary : Crenel.Palette.textSecondary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: hovering ? .white : Crenel.Palette.textPrimary
        case .accent(let color): hovering ? color.opacity(0.88) : color
        case .secondary: hovering ? Crenel.Palette.layer2 : .clear
        case .tinted(let color): color.opacity(hovering ? 0.22 : 0.14)
        case .ghost: hovering ? Crenel.Palette.layer2 : .clear
        }
    }
}

/// Square icon-only button.
struct CrenelIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 28
    var tint: Color = Crenel.Palette.textSecondary
    var fill: Color? = nil
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        CrenelIconButtonBody(configuration: configuration, side: diameter, tint: tint, fill: fill, isActive: isActive)
    }
}

private struct CrenelIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let side: CGFloat
    let tint: Color
    let fill: Color?
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering && fill == nil && !isActive ? Crenel.Palette.textPrimary : tint)
            .frame(width: side, height: side)
            .background(PixelCornerShape().fill(backgroundFill))
            .contentShape(PixelCornerShape())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovering)
    }

    private var backgroundFill: Color {
        if let fill { return hovering ? fill.opacity(0.85) : fill }
        if isActive { return tint.opacity(0.16) }
        return hovering ? Crenel.Palette.layer2 : .clear
    }
}

// MARK: - Row

/// A list row that only changes colour under the pointer. No movement, no resizing.
struct CrenelRowStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        CrenelRowBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct CrenelRowBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .background(PixelCornerShape().fill(isSelected ? Crenel.Palette.layer2 : (hovering ? Crenel.Palette.layer1 : .clear)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovering)
    }
}

/// Hover highlight for rows that are not buttons.
struct CrenelHoverHighlight: ViewModifier {
    var isActive = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(PixelCornerShape().fill(isActive ? Crenel.Palette.layer2 : (hovering ? Crenel.Palette.layer1 : .clear)))
            .onHover { hovering = $0 }
            .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovering)
    }
}

// MARK: - Segmented control

/// Text tabs; the selected one sits on a lit block that glides between items.
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
    var tint: Color = Crenel.Palette.brand
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    withAnimation(Crenel.Motion.resolve(Crenel.Motion.slide, reduceMotion: reduceMotion)) {
                        selection = item.value
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let glyph = item.glyph {
                            CrenelIcon(glyph, size: 9)
                        }
                        if !compact || isSelected {
                            Text(item.title.lowercased(with: Locale(identifier: "tr_TR")))
                        }
                        if let badge = item.badge, badge > 0 {
                            Text("\(badge)")
                                .foregroundStyle(isSelected ? tint.opacity(0.7) : Crenel.Palette.textQuaternary)
                        }
                    }
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        isSelected ? tint : (hovered == item.value ? Crenel.Palette.textSecondary : Crenel.Palette.textTertiary)
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        if isSelected {
                            PixelCornerShape()
                                .fill(tint.opacity(0.14))
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovered)
    }
}

// MARK: - Chip and key cap

struct CrenelChip: View {
    let title: String
    var glyph: CrenelGlyph?
    var tint: Color = Crenel.Palette.textSecondary
    var filled = false

    var body: some View {
        HStack(spacing: 5) {
            if let glyph {
                CrenelIcon(glyph, size: 9)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(PixelCornerShape(step: 1.5).fill(tint.opacity(filled ? 0.2 : 0.12)))
    }
}

struct CrenelKeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Crenel.Palette.textTertiary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .overlay(PixelCornerShape(step: 1.5).stroke(Crenel.Palette.stroke, lineWidth: 1))
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
                Text("\(count)").crenelText(.eyebrow, color: Crenel.Palette.textQuaternary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: 20)
    }
}

extension CrenelSectionHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil, tint: Color = Crenel.Palette.textTertiary) {
        self.init(title: title, count: count, tint: tint) { EmptyView() }
    }
}

// MARK: - Meters and signals

/// Progress as a row of pixel blocks.
struct CrenelPixelMeter: View {
    var progress: Double
    var tint: Color
    var segments = 10
    var height: CGFloat = 6

    var body: some View {
        let lit = Int((min(1, max(0, progress)) * Double(segments)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < lit ? tint : Crenel.Palette.layer3)
                    .frame(height: height)
            }
        }
        .animation(.easeOut(duration: 0.2), value: lit)
        .accessibilityHidden(true)
    }
}

/// The voice meter: columns of pixel blocks rising like merlons on a wall.
struct CrenelMerlonMeter: View {
    var level: Double
    var tint: Color
    var columns = 5
    var rows = 4
    var pixel: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.09)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: pixel * 0.67) {
                ForEach(0..<columns, id: \.self) { column in
                    let shape = [0.6, 0.9, 1.0, 0.85, 0.55, 0.8, 0.95][column % 7]
                    let wobble = reduceMotion ? 1 : (0.7 + 0.3 * abs(sin(t * 7 + Double(column) * 1.7)))
                    let height = max(1, Int((min(1, level * 1.4) * shape * wobble * Double(rows)).rounded(.up)))
                    VStack(spacing: pixel * 0.33) {
                        ForEach((0..<rows).reversed(), id: \.self) { row in
                            Rectangle()
                                .fill(row < height ? tint : tint.opacity(0.16))
                                .frame(width: pixel, height: pixel)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A braille spinner for work in progress.
struct CrenelSpinner: View {
    var tint: Color = Crenel.Palette.textSecondary
    private static let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            let index = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count
            Text(String(Self.frames[index]))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

/// A pixel that blinks in hard steps, like a cursor — the recording light.
struct CrenelBlink: View {
    var glyph: CrenelGlyph = .record
    var tint: Color = Crenel.Palette.record
    var size: CGFloat = 13.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { context in
            let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
            CrenelIcon(glyph, size: size)
                .foregroundStyle(tint.opacity(on ? 1 : 0.28))
        }
        .accessibilityHidden(true)
    }
}

/// Small status dot.
struct CrenelDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Rectangle().fill(color).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Edge light

private struct BeamModifier<S: Shape>: ViewModifier {
    var active: Bool
    var tint: Color
    var level: Double
    var speed: Double
    var lineWidth: CGFloat
    var shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                    let time = Float(context.date.timeIntervalSince(start))
                    shape
                        .stroke(Color.white, lineWidth: lineWidth)
                        .visualEffect { view, proxy in
                            view.colorEffect(ShaderLibrary.crenelBeam(
                                .float2(proxy.size),
                                .float(time),
                                .color(tint),
                                .float(Float(speed)),
                                .float(Float(max(0, min(1, level))))
                            ))
                        }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    /// Light travelling along the edge of `shape` while `active`.
    func crenelBeam<S: Shape>(
        _ active: Bool,
        tint: Color,
        level: Double = 0.3,
        speed: Double = 0.45,
        lineWidth: CGFloat = 1.5,
        shape: S
    ) -> some View {
        modifier(BeamModifier(active: active, tint: tint, level: level, speed: speed, lineWidth: lineWidth, shape: shape))
    }
}

// MARK: - Empty state

struct CrenelEmptyState: View {
    let glyph: CrenelGlyph
    let title: String
    var detail: String?
    var tint: Color = Crenel.Palette.textTertiary

    var body: some View {
        HStack(alignment: .top, spacing: Crenel.Space.m) {
            CrenelIcon(glyph, size: 18)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).crenelText(.bodyEmphasis)
                if let detail {
                    Text(detail)
                        .crenelText(.callout, color: Crenel.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Crenel.Space.m)
    }
}
