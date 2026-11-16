import SwiftUI

// MARK: - Section label

/// MONO UPPERCASE label, a dotted leader, and an optional trailing value. Reads like an
/// instrument legend; the leader ties the label to its value across the width.
struct HudSectionLabel: View {
    let title: String
    var value: String?
    var tint: Color = Hud.Ink.text3

    var body: some View {
        HStack(spacing: Hud.Space.x2) {
            Text(title.uppercased(with: Locale(identifier: "tr_TR"))).hud(.label, tint)
            HudLeader()
            if let value {
                Text(value.uppercased(with: Locale(identifier: "tr_TR"))).hud(.label, tint == Hud.Ink.text3 ? Hud.Ink.text3 : tint)
            }
        }
        .frame(height: Hud.Size.label)
        .padding(.horizontal, Hud.Space.x2)
    }
}

/// A dotted rule: 1 pt dots every 3 pt, centred on the text's x-height.
struct HudLeader: View {
    var color: Color = Hud.Ink.dot

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            let y = (size.height / 2).rounded()
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(color))
                x += 3
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Meters

/// A segmented bar: discrete cells instead of a smooth fill, the HUD's way of showing
/// quantity. Cells change one at a time with a short fade.
struct HudSegmentMeter: View {
    let segments: Int
    let lit: Int
    var tint: Color = Hud.Ink.text1
    var height: CGFloat = 4
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - spacing * CGFloat(segments - 1)) / CGFloat(segments)
            HStack(spacing: spacing) {
                ForEach(0..<segments, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? tint : Hud.Ink.line)
                        .frame(width: max(1, width.rounded(.down)))
                }
            }
        }
        .frame(height: height)
        .animation(Hud.Motion.change, value: lit)
    }
}

/// A vertical level meter for voice: five cells per column, a few columns.
struct HudLevelMeter: View {
    let levels: [Double]
    var tint: Color = Hud.Ink.text1

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                VStack(spacing: 1.5) {
                    ForEach((0..<4).reversed(), id: \.self) { cell in
                        Rectangle()
                            .fill(Double(cell) < level * 4 ? tint : Hud.Ink.line)
                            .frame(width: 3, height: 2.5)
                    }
                }
            }
        }
    }
}

// MARK: - Task state mark

/// Task state as a fill level — empty, half, full — plus a bar for blocked. No ticks.
struct HudStateMark: View {
    let state: TaskStatus
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvas in
            let inset: CGFloat = 1
            let ring = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
            let line: CGFloat = 1.4
            let inner = ring.insetBy(dx: 2.6, dy: 2.6)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            switch state {
            case .open:
                context.stroke(Path(ellipseIn: ring), with: .color(Hud.Ink.text3), lineWidth: line)
            case .inProgress:
                context.stroke(Path(ellipseIn: ring), with: .color(Hud.Ink.signal), lineWidth: line)
                var half = Path()
                half.move(to: center)
                half.addArc(center: center, radius: inner.width / 2, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                half.closeSubpath()
                context.fill(half, with: .color(Hud.Ink.signal))
            case .blocked:
                context.stroke(Path(ellipseIn: ring), with: .color(Hud.Ink.live), lineWidth: line)
                context.fill(Path(CGRect(x: inner.minX + 0.5, y: center.y - 0.8, width: inner.width - 1, height: 1.6)), with: .color(Hud.Ink.live))
            case .completed:
                context.stroke(Path(ellipseIn: ring), with: .color(Hud.Ink.text3), lineWidth: line)
                context.fill(Path(ellipseIn: inner), with: .color(Hud.Ink.text3))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Row

/// The one list row. Fixed height, fixed insets; hover only lays a flat fill under it.
struct HudRow<Content: View>: View {
    var isEmphasised = false
    @ViewBuilder let content: () -> Content
    @State private var isHovering = false
    var forceHover = false

    var body: some View {
        HStack(spacing: Hud.Space.x3) { content() }
            .padding(.horizontal, Hud.Space.x2)
            .frame(height: Hud.Size.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                    .fill(isHovering || forceHover ? Hud.Ink.hover : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
    }
}

// MARK: - Buttons

struct HudButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, icon }
    var kind: Kind = .ghost

    func makeBody(configuration: Configuration) -> some View {
        HudButtonBody(kind: kind, configuration: configuration)
    }
}

private struct HudButtonBody: View {
    let kind: HudButtonStyle.Kind
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(kind == .primary ? Hud.Style.bodyStrong.font : Hud.Style.body.font)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .icon ? 0 : 10)
            .frame(width: kind == .icon ? 26 : nil, height: 26)
            .background(
                RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous).fill(background)
            )
            .contentShape(Rectangle())
            .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .ghost: isHovering ? Hud.Ink.text1 : Hud.Ink.text2
        case .icon: isHovering ? Hud.Ink.text1 : Hud.Ink.text3
        }
    }

    private var background: Color {
        switch kind {
        case .primary: configuration.isPressed ? Hud.Ink.text2 : Hud.Ink.text1
        case .ghost, .icon: configuration.isPressed ? Hud.Ink.press : (isHovering ? Hud.Ink.hover : .clear)
        }
    }
}

/// A keyboard hint shown next to an action, e.g. ⌘R.
struct HudKeyHint: View {
    let keys: String

    var body: some View {
        Text(keys).hud(.label, Hud.Ink.text4).tracking(0.4)
    }
}

// MARK: - Tabs in the notch ears

/// A tab label set in the space beside the camera housing. The selected tab is bright
/// with a short rule beneath; the shortcut number sits as a superscript.
struct HudEarTab: View {
    let title: String
    let key: String
    var count: Int?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            (Text(title).font(Hud.Style.bodyStrong.font).tracking(Hud.Style.bodyStrong.tracking)
                .foregroundColor(isSelected ? Hud.Ink.text1 : Hud.Ink.text3)
             + Text("\u{2009}\(key)").font(Hud.Style.key.font).baselineOffset(5)
                .foregroundColor(isSelected ? Hud.Ink.text3 : Hud.Ink.text4))
            if let count {
                Text("\(count)").hud(.numeral, Hud.Ink.text3)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(Hud.Ink.text1)
                .frame(width: 14, height: 1.5)
                .offset(y: 7)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(Hud.Motion.change, value: isSelected)
    }
}
