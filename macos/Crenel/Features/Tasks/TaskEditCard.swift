import SwiftUI

/// The task opened in place by Edit (`.task-card`): title, what a blocked task is waiting
/// on, When, Priority, note and the source meeting. State and delete are not here — they
/// live in the row's actions. The single exit is Done ↩. Title, reason and note save when
/// a field loses focus and on Done; nothing saves on every keystroke.
struct TaskEditCard: View {
    let task: TaskItem
    let now: Date
    /// Title of the meeting the task came from, when it is still stored.
    var sourceMeetingTitle: String?
    let onClose: () -> Void

    @Environment(\.crenelActions) private var actions
    @State private var title: String
    @State private var notes: String
    @State private var blockedReason: String
    @FocusState private var focus: Field?

    private enum Field { case title, blockedReason, notes }

    init(task: TaskItem, now: Date, sourceMeetingTitle: String? = nil, onClose: @escaping () -> Void) {
        self.task = task
        self.now = now
        self.sourceMeetingTitle = sourceMeetingTitle
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _blockedReason = State(initialValue: task.blockedReason ?? "")
    }

    var body: some View {
        // The card is the row opened in place: the same 10 around its ink as a row, so
        // the list keeps its 20 rhythm; groups inside are 20 apart, a label 10 above its
        // control.
        VStack(alignment: .leading, spacing: Hud.Layout.item) {
            HStack(alignment: .top, spacing: Hud.Row.gap) {
                HudStateMark(state: task.status)
                    .frame(width: 16, height: 16)
                    .padding(-Hud.Layout.glyphInset)
                    .padding(.top, 2)
                TextField("Task", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .hud(.title)
                    .lineLimit(1...4)
                    .focused($focus, equals: .title)
                    .onSubmit(close)
                    .accessibilityLabel("Title")
            }

            if task.status == .blocked {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blocked").hudTrimmed(.meta)
                    TextField("", text: $blockedReason, prompt: Text("Waiting on…").foregroundColor(Hud.Ink.ink3))
                        .textFieldStyle(.plain)
                        .hud(.body, Hud.Ink.ink2)
                        .lineLimit(1)
                        .focused($focus, equals: .blockedReason)
                        .onSubmit(close)
                        .padding(.horizontal, Hud.Layout.rowPad)
                        .frame(maxWidth: .infinity, minHeight: Hud.Layout.field, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Hud.Layout.hitRadius, style: .continuous).fill(Color(white: 1, opacity: 0.04)))
                        .contentShape(Rectangle())
                        .onTapGesture { focus = .blockedReason }
                        .accessibilityLabel("Waiting on")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("When").hudTrimmed(.meta)
                HStack(spacing: 4) {
                    whenOption("Today", date: startOfDay(0))
                    whenOption("Tomorrow", date: startOfDay(1))
                    whenOption("Weekend", date: nextWeekend)
                    whenOption("Next week", date: startOfDay(7))
                    whenOption("No date", date: nil, clears: true)
                }
                if let due = TaskDueFormatter.label(for: task, now: now) {
                    HStack(spacing: 8) {
                        HudIcon(.calendar, size: 12)
                        Text(due)
                        if let recurrence = task.recurrence {
                            HudIcon(.repeats, size: 12).padding(.leading, 8)
                            Text(recurrence.displayText)
                        }
                    }
                    .hud(.meta, Hud.Ink.ink2)
                    .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Priority").hudTrimmed(.meta)
                HudSegmented(
                    items: [TaskPriority.none, .low, .medium, .high].map { (value: $0, title: $0.shortText) },
                    selection: Binding(
                        get: { task.priority },
                        set: { actions.tasks.setPriority(task, $0) }
                    )
                ) { priority in
                    if priority != .none {
                        HudPriorityBars(
                            level: priority.barLevel,
                            tint: priority == .high ? Hud.Ink.signal : (priority == task.priority ? Hud.Ink.ink1 : Hud.Ink.ink2)
                        )
                    }
                }
            }

            TextField("", text: $notes, prompt: Text("Note").foregroundColor(Hud.Ink.ink3), axis: .vertical)
                .textFieldStyle(.plain)
                .hud(.body, Hud.Ink.ink2)
                .lineLimit(1...8)
                .focused($focus, equals: .notes)
                .padding(Hud.Layout.rowPad)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: Hud.Layout.hitRadius, style: .continuous).fill(Color(white: 1, opacity: 0.04)))
                .contentShape(Rectangle())
                .onTapGesture { focus = .notes }
                .accessibilityLabel("Note")

            HudActions {
                if let meetingID = task.sourceMeetingID {
                    Button {
                        actions.tasks.openSourceMeeting(meetingID)
                    } label: {
                        HudChip(sourceMeetingTitle.map { "From \($0)" } ?? "From a meeting", glyph: .transcript)
                    }
                    .buttonStyle(.plain)
                    .help("Open the meeting this task came from")
                }
            } buttons: {
                HudButton("Done", key: "↩", kind: .primary, size: .small, action: close)
                    .hudShortcut(.defaultAction)
            }
        }
        .padding(Hud.Layout.rowPad)
        .background(RoundedRectangle(cornerRadius: Hud.Layout.hitRadius + 2, style: .continuous).fill(Color(white: 1, opacity: 0.045)))
        .onExitCommand(perform: close)
        .onChange(of: focus) { previous, _ in
            if previous != nil { commit() }
        }
        .onChange(of: task.title) { _, newValue in
            if focus != .title { title = newValue }
        }
        .onChange(of: task.blockedReason) { _, newValue in
            if focus != .blockedReason { blockedReason = newValue ?? "" }
        }
        .onDisappear(perform: commit)
    }

    /// One "When" choice: the chosen day is a raised key, the others are words.
    private func whenOption(_ label: LocalizedStringKey, date: Date?, clears: Bool = false) -> some View {
        let isSelected: Bool = if let date {
            task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        } else {
            clears && task.dueDate == nil
        }
        return Button(label) {
            if clears || date != nil { actions.tasks.reschedule(task, date, false) }
        }
        .buttonStyle(HudButtonStyle(kind: isSelected ? .secondary : .ghost, size: .small))
        .fixedSize()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func startOfDay(_ offset: Int) -> Date? {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
    }

    private var nextWeekend: Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        return calendar.nextDate(after: start, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
    }

    private func close() {
        commit()
        onClose()
    }

    private func commit() {
        var updated = task
        var changed = false
        if let normalized = TaskItem.normalizedTitle(title), normalized != task.title {
            updated.title = normalized
            changed = true
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if newNotes != task.notes {
            updated.notes = newNotes
            changed = true
        }
        if task.status == .blocked {
            let newReason = TaskItem.normalizedBlockedReason(blockedReason)
            if newReason != task.blockedReason {
                updated.setBlockedReason(newReason)
                changed = true
            }
        }
        if changed { actions.tasks.save(updated) }
    }
}
