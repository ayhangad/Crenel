import SwiftUI

// MARK: - Group header

/// A plain group title. No rule, no count, no letterspacing.
struct HudGroupHeader: View {
    let title: Text

    init(title: LocalizedStringKey) {
        self.title = Text(title)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S) {
        self.title = Text(title)
    }

    var body: some View {
        title
            .hud(.label, Hud.Ink.text3)
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: 22, alignment: .bottom)
            .padding(.bottom, Hud.Space.x1)
    }
}

// MARK: - Meters

/// A segmented bar: discrete cells instead of a smooth fill. The leading cell fades in
/// partially, so progress moves continuously while still reading as steps.
struct HudSegmentMeter: View {
    let segments: Int
    /// 0…1.
    let progress: Double
    var tint: Color = Hud.Ink.text1
    var height: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - spacing * CGFloat(segments - 1)) / CGFloat(segments)
            HStack(spacing: spacing) {
                ForEach(0..<segments, id: \.self) { index in
                    let fill = min(1, max(0, progress * Double(segments) - Double(index)))
                    ZStack {
                        Capsule().fill(Hud.Ink.track)
                        Capsule().fill(tint).opacity(fill)
                    }
                    .frame(width: max(1, width))
                }
            }
        }
        .frame(height: height)
        .animation(Hud.Motion.change, value: progress)
    }
}

/// A small voice meter: bars that rise with the level.
struct HudLevelMeter: View {
    let levels: [Double]
    var tint: Color = Hud.Ink.text1

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: 3 + 11 * max(0, min(1, level)))
            }
        }
        .frame(height: 14)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: levels)
    }
}

// MARK: - Task state mark

/// Task state as a fill level — empty, half, full — plus a bar for blocked. No ticks.
struct HudStateMark: View {
    let state: TaskStatus
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvas in
            let ring = CGRect(origin: .zero, size: canvas).insetBy(dx: 1, dy: 1)
            let line: CGFloat = 1.4
            let inner = ring.insetBy(dx: 2.7, dy: 2.7)
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
                context.fill(Path(roundedRect: CGRect(x: inner.minX + 0.5, y: center.y - 0.8, width: inner.width - 1, height: 1.6), cornerRadius: 0.8),
                             with: .color(Hud.Ink.live))
            case .completed:
                context.stroke(Path(ellipseIn: ring), with: .color(Hud.Ink.text4), lineWidth: line)
                context.fill(Path(ellipseIn: inner), with: .color(Hud.Ink.text4))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Glide highlight

/// One hover highlight per list that glides between rows instead of each row fading
/// its own fill. Rows report hover; the list owns the highlight.
struct HudGlide: ViewModifier {
    let id: AnyHashable
    @Binding var hovered: AnyHashable?
    let namespace: Namespace.ID
    var forced: AnyHashable?

    func body(content: Content) -> some View {
        content
            .background {
                if (forced ?? hovered) == id {
                    RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                        .fill(Hud.Ink.hover)
                        .matchedGeometryEffect(id: "hud.glide", in: namespace)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(Hud.Motion.glide) {
                    if inside { hovered = id } else if hovered == id { hovered = nil }
                }
            }
    }
}

extension View {
    func hudGlide(_ id: AnyHashable, hovered: Binding<AnyHashable?>, in namespace: Namespace.ID, forced: AnyHashable? = nil) -> some View {
        modifier(HudGlide(id: id, hovered: hovered, namespace: namespace, forced: forced))
    }
}

// MARK: - Buttons

struct HudButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, icon, iconFilled }
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
            .font(Hud.Style.label.font)
            .foregroundStyle(foreground)
            .padding(.horizontal, isIcon ? 0 : 12)
            .frame(width: isIcon ? Hud.Size.control : nil, height: Hud.Size.control)
            .background(
                RoundedRectangle(cornerRadius: Hud.Size.corner - 2, style: .continuous).fill(background)
            )
            .contentShape(Rectangle())
            .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
    }

    private var isIcon: Bool { kind == .icon || kind == .iconFilled }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .iconFilled: Hud.Ink.text1
        case .ghost: isHovering ? Hud.Ink.text1 : Hud.Ink.text2
        case .icon: isHovering ? Hud.Ink.text1 : Hud.Ink.text3
        }
    }

    private var background: Color {
        switch kind {
        case .primary: configuration.isPressed ? Hud.Ink.text2 : (isHovering ? Color(white: 1) : Hud.Ink.text1)
        case .ghost, .icon: configuration.isPressed ? Hud.Ink.press : (isHovering ? Hud.Ink.hover : .clear)
        case .iconFilled: configuration.isPressed ? Hud.Ink.press : (isHovering ? Hud.Ink.selected : Hud.Ink.hover)
        }
    }
}

// MARK: - Tabs

/// Centred switcher under the camera housing. Each tab is an icon and a word; the
/// selection is a soft plate that glides between them.
struct HudTabs<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let glyph: HudGlyph
        let title: String
        var badge: Int?
    }

    let items: [Item]
    @Binding var selection: Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.tab) { item in
                let isSelected = item.tab == selection
                Button {
                    withAnimation(Hud.Motion.glide) { selection = item.tab }
                } label: {
                    HStack(spacing: 7) {
                        HudIcon(item.glyph, size: Hud.Size.smallIcon)
                        Text(item.title).font(Hud.Style.label.font)
                        if let badge = item.badge {
                            Text("\(badge)").font(Hud.Style.meta.font).monospacedDigit()
                                .foregroundStyle(isSelected ? Hud.Ink.text2 : Hud.Ink.text4)
                        }
                    }
                    .foregroundStyle(isSelected ? Hud.Ink.text1 : Hud.Ink.text3)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background {
                        if isSelected {
                            Capsule().fill(Hud.Ink.selected)
                                .matchedGeometryEffect(id: "hud.tab", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(white: 1, opacity: 0.035)))
    }
}

// MARK: - Pulse

/// A dot that breathes while something is live (recording, listening).
struct HudPulse: View {
    let color: Color
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.35]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
            .frame(width: max(size, Hud.Size.smallIcon), height: max(size, Hud.Size.smallIcon))
            .accessibilityHidden(true)
    }
}

// MARK: - Ears

/// Places the two ears of the closed notch beside the camera housing. Both ears share
/// one width — the wider content plus padding — and each content is centred in its ear,
/// so the notch stays balanced and only as wide as the current state needs.
struct HudEarsLayout: Layout {
    var gap: CGFloat
    var padding: CGFloat

    private func side(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max().map { $0 + padding * 2 } ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: side(subviews) * 2 + gap, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let ear = side(subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX + ear / 2, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.maxX - ear / 2, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}

// MARK: - Formatting

enum HudFormat {
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Today", "Tomorrow", or a short weekday and day ("Tue 17").
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
