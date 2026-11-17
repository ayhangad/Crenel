import SwiftUI

/// One task row (`.task-row`): chamfered mark, title, and on the right what matters now
/// — minutes on the task in progress, priority bars, repeat, due date, source meeting.
///
/// The row's actions (`.tray`) are attached to its right edge and wait off-screen. One
/// click on the row gives it its own background and slides content, background and
/// actions left as one piece by the width of the actions; the left part leaves the list
/// and is clipped. The list owns which row is open (`isRevealed`) and which rows still
/// hold their background (`isHeld`).
struct TaskRowView: View {
    let task: TaskItem
    let now: Date
    let isOverdue: Bool
    /// Finished list: the trailing meta is the time the task was finished.
    var showsFinishedTime = false
    /// The state shown on the mark; differs from `task.status` while a pick settles.
    let displayStatus: TaskStatus
    let isRevealed: Bool
    let isHeld: Bool
    let onToggle: () -> Void
    let onLeave: () -> Void
    let onPick: (TaskStatus) -> Void
    let onEdit: () -> Void
    let onRequestDelete: () -> Void

    @Environment(\.crenelActions) private var actions

    var body: some View {
        TaskSlideLayout(progress: isRevealed ? 1 : 0) {
            content
            TaskRowTray(current: displayStatus, onPick: onPick, onEdit: onEdit, onDelete: onRequestDelete)
                .allowsHitTesting(isRevealed)
                .accessibilityHidden(!isRevealed)
        }
        .frame(height: Hud.Row.task)
        .clipShape(RoundedRectangle(cornerRadius: Hud.Row.radius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { inside in
            if !inside { onLeave() }
        }
        .contextMenu { contextActions }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: Hud.Row.gap) {
                    HudStateMark(state: displayStatus)
                        .frame(width: 16, height: 16)
                    Text(task.title)
                        .hud(.body, displayStatus == .completed ? Hud.Ink.ink3 : Hud.Ink.ink1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TaskRowMeta(task: task, now: now, isOverdue: isOverdue, showsFinishedTime: showsFinishedTime)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title), \(displayStatus.shortTitle)")
            .accessibilityHint(isRevealed ? "Hides the task's actions" : "Shows the task's actions")
            .accessibilityActions {
                ForEach(TaskStatus.allCases) { status in
                    if status != displayStatus {
                        Button(status.shortTitle) { onPick(status) }
                    }
                }
                Button("Edit", action: onEdit)
                Button("Delete", action: onRequestDelete)
            }

            if let meetingID = task.sourceMeetingID {
                TaskSourceButton { actions.tasks.openSourceMeeting(meetingID) }
            }
        }
        .padding(.horizontal, Hud.Row.inset)
        .frame(height: Hud.Row.task)
        .background {
            if isHeld {
                UnevenRoundedRectangle(topLeadingRadius: Hud.Row.radius, bottomLeadingRadius: Hud.Row.radius,
                                       bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
                    .fill(Hud.Ink.hover)
            }
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        ForEach(TaskStatus.allCases) { status in
            Button(status.shortTitle) { onPick(status) }
                .disabled(status == task.status && !task.isArchived)
        }
        Divider()
        if !task.isCompleted {
            Button("Move to Today") {
                actions.tasks.reschedule(task, Calendar.current.startOfDay(for: Date()), false)
            }
            Button("Postpone to tomorrow") { actions.tasks.postponeToTomorrow(task) }
        }
        if task.isArchived {
            Button("Restore to list") { actions.tasks.restore(task) }
        } else if task.isCompleted {
            Button("Remove from list") { actions.tasks.archive(task) }
        }
        Divider()
        Button("Delete", role: .destructive, action: onRequestDelete)
    }
}

// MARK: - Slide

/// Places the row content and, attached to its right edge, the actions. `progress`
/// 0 → the actions wait outside the row; 1 → both have moved left by the actions' width.
private struct TaskSlideLayout: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0
        return CGSize(width: width, height: proposal.height ?? Hud.Row.task)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let trayWidth = subviews[1].sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)).width
        let shift = min(trayWidth, bounds.width) * progress
        subviews[0].place(at: CGPoint(x: bounds.minX - shift, y: bounds.minY),
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.maxX - shift, y: bounds.minY),
                          proposal: ProposedViewSize(width: trayWidth, height: bounds.height))
    }
}

// MARK: - Tray

/// The row's actions (`.tray`): four named states in a dark slot (the current one lit),
/// a thin divider, Edit and Delete. It shares the row's background; only its right
/// corners are round, so the seam with the row is invisible.
private struct TaskRowTray: View {
    let current: TaskStatus
    let onPick: (TaskStatus) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovered: TaskStatus?

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(TaskStatus.allCases) { status in
                    let isOn = status == current
                    Button {
                        onPick(status)
                    } label: {
                        HStack(spacing: 6) {
                            HudStateMark(state: status, size: 14)
                            Text(status.shortTitle)
                                .hud(.label, isOn || hovered == status ? Hud.Ink.ink1 : Hud.Ink.ink3)
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 6)
                        .padding(.trailing, 8)
                        .frame(height: 26)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                            if isOn {
                                shape.fill(Hud.Ink.selected)
                                shape.strokeBorder(Color(white: 1, opacity: 0.06), lineWidth: 1)
                            } else if hovered == status {
                                shape.fill(Color(white: 1, opacity: 0.06))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? status : (hovered == status ? nil : hovered) }
                    .accessibilityLabel(status.shortTitle)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(2)
            .background {
                let slot = RoundedRectangle(cornerRadius: 9, style: .continuous)
                slot.fill(Color.black.opacity(0.35))
                slot.strokeBorder(Color(white: 1, opacity: 0.05), lineWidth: 1)
            }

            Rectangle()
                .fill(Color(white: 1, opacity: 0.08))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 4)

            HudIconButton(.edit, framed: true, small: true, help: "Edit", action: onEdit)
            HudIconButton(.trash, framed: true, small: true, tint: Hud.Ink.danger, help: "Delete", action: onDelete)
        }
        .padding(.horizontal, 6)
        .frame(height: Hud.Row.task)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: Hud.Row.radius, topTrailingRadius: Hud.Row.radius, style: .continuous)
                .fill(Hud.Ink.hover)
        )
        .animation(Hud.Motion.hover, value: hovered)
    }
}

// MARK: - Meta

/// The right side of a row. Order: minutes on the task in progress (segment digits),
/// priority bars, repeat, due date.
private struct TaskRowMeta: View {
    let task: TaskItem
    let now: Date
    let isOverdue: Bool
    let showsFinishedTime: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsFinishedTime {
                if let finished = task.completedAt ?? task.archivedAt {
                    Text(HudFormat.clock(finished)).hud(.meta)
                }
            } else if !task.isCompleted {
                if task.status == .inProgress, let started = task.startedAt {
                    let spent = TaskRowFormat.spent(since: started, now: now)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        HudSegmentDigits(spent.digits, height: 10, color: Hud.Ink.signal)
                        Text(spent.unit).font(Hud.font(10, .medium)).foregroundStyle(Hud.Ink.signal.opacity(0.7))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(spent.digits) \(spent.unit) on this task")
                }
                if task.priority != .none {
                    HudPriorityBars(level: task.priority.barLevel, tint: task.priority == .high ? Hud.Ink.signal : Hud.Ink.ink2)
                        .help(task.priority.displayText)
                }
                if let recurrence = task.recurrence {
                    HudIcon(.repeats, size: 12).foregroundStyle(Hud.Ink.ink4)
                        .help(recurrence.displayText)
                }
                if let due = TaskRowFormat.due(for: task, now: now) {
                    Text(due.text)
                        .hud(.meta, isOverdue ? Hud.Ink.live : (due.isClock ? Hud.Ink.ink2 : Hud.Ink.ink3))
                        .help(TaskDueFormatter.label(for: task, now: now) ?? due.text)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// The source-meeting mark at the row's far right; opens the meeting the task came from.
private struct TaskSourceButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HudIcon(.transcript, size: 12)
                .foregroundStyle(isHovering ? Hud.Ink.ink2 : Hud.Ink.ink4)
                .frame(width: 16, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open the meeting this task came from")
        .accessibilityLabel("Open source meeting")
    }
}

enum TaskRowFormat {
    /// Time on the task in progress: minutes under 100, then hours and minutes.
    static func spent(since start: Date, now: Date) -> (digits: String, unit: String) {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 100 { return ("\(minutes)", "min") }
        return ("\(minutes / 60):" + String(format: "%02d", minutes % 60), "h")
    }

    /// Compact due label for a row: only the clock for a timed task due today, nothing
    /// for a task simply due today, the weekday inside a week, then "Mon 23" / "4 Jan".
    static func due(for task: TaskItem, now: Date, calendar: Calendar = .current) -> (text: String, isClock: Bool)? {
        guard let due = task.dueDate else { return nil }
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch offset {
        case 0:
            return task.dueHasTime ? (HudFormat.clock(due), true) : nil
        case -1:
            return ("Yesterday", false)
        case 1...6:
            return (format(due, "EEE", calendar), false)
        case 7...27:
            return (format(due, "EEE d", calendar), false)
        default:
            let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
            return (format(due, sameYear ? "d MMM" : "d MMM yyyy", calendar), false)
        }
    }

    /// Group title of a Finished day: "Today", "Yesterday", "Mon 16", "4 Jan".
    static func historyTitle(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0
        if offset == 1 { return "Yesterday" }
        if (2...27).contains(offset) { return format(day, "EEE d", calendar) }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return format(day, sameYear ? "d MMM" : "d MMM yyyy", calendar)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

extension TaskStatus {
    /// The state's name in row actions and menus: To do · Doing · Blocked · Done.
    var shortTitle: String {
        switch self {
        case .open: "To do"
        case .inProgress: "Doing"
        case .blocked: "Blocked"
        case .completed: "Done"
        }
    }
}
