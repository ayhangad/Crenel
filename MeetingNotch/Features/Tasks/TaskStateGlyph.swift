import SwiftUI

/// The task's state as a fill level: empty (to do), half (in progress), a bar
/// (blocked), full (done). No check mark. Drawn by `HudStateMark`.
struct TaskStateGlyph: View {
    let status: TaskStatus
    /// Kept for call-site compatibility; state colours come from the mark itself.
    var tint: Color = Crenel.Palette.textTertiary
    var size: CGFloat = 14

    var body: some View {
        HudStateMark(state: status, size: size)
            .animation(Hud.Motion.glide, value: status)
    }

    static func color(for status: TaskStatus, idle: Color) -> Color {
        switch status {
        case .open: idle
        case .inProgress: Crenel.Palette.focus
        case .blocked: Crenel.Palette.danger
        case .completed: Crenel.Palette.success
        }
    }
}

private struct PieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0.001 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// The state picker that unfolds from a task's glyph: four states, one tap.
struct TaskStatePicker: View {
    let current: TaskStatus
    let onSelect: (TaskStatus) -> Void
    @State private var hovered: TaskStatus?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    onSelect(status)
                } label: {
                    HStack(spacing: 6) {
                        TaskStateGlyph(status: status, size: 12)
                        Text(status.title)
                            .font(Hud.Style.label.font)
                            .foregroundStyle(status == current ? Crenel.Palette.textPrimary : Crenel.Palette.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        Capsule(style: .continuous)
                            .fill(status == current ? Hud.Ink.selected : (hovered == status ? Hud.Ink.hover : .clear))
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? status : (hovered == status ? nil : hovered) }
                .accessibilityLabel(status.title)
                .accessibilityAddTraits(status == current ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(white: 1, opacity: 0.035), in: Capsule(style: .continuous))
    }
}
