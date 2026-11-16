import SwiftUI

/// The task's state drawn as one morphing ring: an empty ring (to do), a half-filled
/// ring (in progress), a ring with a bar (blocked), a filled ring with a check (done).
struct TaskStateGlyph: View {
    let status: TaskStatus
    var tint: Color = Crenel.Palette.textTertiary
    var size: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = TaskStateGlyph.color(for: status, idle: tint)
        ZStack {
            Circle()
                .strokeBorder(color, lineWidth: size * 0.1)
                .opacity(status == .completed ? 0 : 1)

            Circle()
                .fill(color)
                .scaleEffect(status == .completed ? 1 : 0.2)
                .opacity(status == .completed ? 1 : 0)

            PieSlice(fraction: status == .inProgress ? 0.5 : 0)
                .fill(color)
                .padding(size * 0.22)

            Capsule()
                .fill(color)
                .frame(width: size * 0.5, height: size * 0.11)
                .rotationEffect(.degrees(-45))
                .scaleEffect(x: status == .blocked ? 1 : 0.01)
                .opacity(status == .blocked ? 1 : 0)

            CheckStroke()
                .trim(from: 0, to: status == .completed ? 1 : 0)
                .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .padding(size * 0.26)
        }
        .frame(width: size, height: size)
        .animation(Crenel.Motion.resolve(Crenel.Motion.bouncy, reduceMotion: reduceMotion), value: status)
        .accessibilityHidden(true)
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
                        TaskStateGlyph(status: status, tint: Crenel.Palette.textSecondary, size: 14)
                        Text(status.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(status == current ? Crenel.Palette.textPrimary : Crenel.Palette.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        Capsule(style: .continuous)
                            .fill(status == current ? Crenel.Palette.layer3 : (hovered == status ? Crenel.Palette.layer2 : .clear))
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
        .background(Crenel.Palette.layer1, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Crenel.Palette.hairline))
    }
}
