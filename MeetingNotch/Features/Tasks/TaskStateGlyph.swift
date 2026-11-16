import SwiftUI

/// A task's state as a pixel box: empty (to do), half lit (in progress), crossed
/// (blocked), lit with a check cut out (done).
struct TaskStateGlyph: View {
    let status: TaskStatus
    var tint: Color = Crenel.Palette.textTertiary
    var size: CGFloat = 13.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TaskStateShape(status: status)
            .fill(TaskStateGlyph.color(for: status, idle: tint))
            .frame(width: CrenelIcon.snapped(size), height: CrenelIcon.snapped(size))
            .id(status)
            .transition(.crenelPixel)
            .animation(Crenel.Motion.resolve(.easeOut(duration: 0.18), reduceMotion: reduceMotion), value: status)
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

struct TaskStateShape: Shape {
    let status: TaskStatus

    static func bitmap(for status: TaskStatus) -> [String] {
        switch status {
        case .open: [
            ".#######.",
            "#.......#",
            "#.......#",
            "#.......#",
            "#.......#",
            "#.......#",
            "#.......#",
            "#.......#",
            ".#######."]
        case .inProgress: [
            ".#######.",
            "#.......#",
            "#.###...#",
            "#.###...#",
            "#.###...#",
            "#.###...#",
            "#.###...#",
            "#.......#",
            ".#######."]
        case .blocked: [
            ".#######.",
            "#.......#",
            "#.....#.#",
            "#....#..#",
            "#...#...#",
            "#..#....#",
            "#.#.....#",
            "#.......#",
            ".#######."]
        case .completed: [
            ".#######.",
            "#########",
            "######.##",
            "#####..##",
            "#.##..###",
            "##...####",
            "###.#####",
            "#########",
            ".#######."]
        }
    }

    func path(in rect: CGRect) -> Path {
        PixelBitmap.path(pixels: PixelBitmap.pixels(Self.bitmap(for: status)), grid: 9, in: rect)
    }
}

/// The four states laid out in a row. Used inside a task row (sliding in from the
/// left, replacing the title) and in the task detail.
struct TaskStatePicker: View {
    let current: TaskStatus
    var showsShortcuts = false
    let onSelect: (TaskStatus) -> Void
    @State private var hovered: TaskStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(TaskStatus.allCases.enumerated()), id: \.element) { index, status in
                let isCurrent = status == current
                Button {
                    onSelect(status)
                } label: {
                    HStack(spacing: 6) {
                        TaskStateGlyph(status: status, tint: Crenel.Palette.textSecondary, size: 9)
                        Text(status.title.lowercased(with: Locale(identifier: "tr_TR")))
                        if showsShortcuts {
                            Text("\(index + 1)").foregroundStyle(Crenel.Palette.textQuaternary)
                        }
                    }
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCurrent ? TaskStateGlyph.color(for: status, idle: Crenel.Palette.textPrimary) : Crenel.Palette.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(PixelCornerShape().fill(
                        isCurrent ? Crenel.Palette.layer3 : (hovered == status ? Crenel.Palette.layer2 : .clear)
                    ))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? status : (hovered == status ? nil : hovered) }
                .accessibilityLabel(status.title)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovered)
    }
}
