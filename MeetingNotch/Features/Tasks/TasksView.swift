import SwiftUI

/// One flat task list. Sections follow from state and due date; the user only types.
/// Tapping a task's ring picks its state; tapping the task opens its card.
struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsHistory: Bool
    @State private var openTaskID: UUID?
    @State private var pickerTaskID: UUID?
    @State private var taskPendingDeletion: TaskItem?
    @State private var showsClearHistoryConfirmation = false

    init(initiallyShowsHistory: Bool = false) {
        _showsHistory = State(initialValue: initiallyShowsHistory)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let presentation = appState.taskPresentation(now: context.date)
            VStack(alignment: .leading, spacing: Crenel.Space.l) {
                if showsHistory {
                    historyContent(presentation)
                        .transition(.crenelRise)
                } else {
                    TaskQuickAddField(onSubmit: actions.tasks.add)
                    activeContent(presentation, now: context.date)
                        .transition(.crenelRise)
                }
                footer(presentation)
            }
        }
        .animation(motion(Crenel.Motion.gentle), value: showsHistory)
        .animation(motion(Crenel.Motion.morph), value: openTaskID)
        .animation(motion(Crenel.Motion.snappy), value: pickerTaskID)
        .animation(motion(Crenel.Motion.gentle), value: appState.tasks)
        .alert(
            "Delete task?",
            isPresented: deleteTaskAlertBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Delete", role: .destructive) {
                if openTaskID == task.id { openTaskID = nil }
                actions.tasks.delete(task)
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text(appState.taskStorageStatus.isReminders
                 ? "“\(task.title)” will be deleted from Reminders and all your devices."
                 : "“\(task.title)” will be deleted permanently.")
        }
        .alert("Clear history?", isPresented: $showsClearHistoryConfirmation) {
            Button("Delete All", role: .destructive, action: actions.tasks.clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Completed tasks will be deleted permanently.")
        }
    }

    // MARK: Active list

    @ViewBuilder
    private func activeContent(_ presentation: TaskListPresentation, now: Date) -> some View {
        if presentation.isEmpty {
            CrenelEmptyState(
                glyph: .check,
                title: "Nothing to do",
                detail: "Type above and press Return. Crenel understands dates like “tomorrow 3pm”.",
                tint: Crenel.Palette.tasks
            )
        } else {
            VStack(alignment: .leading, spacing: Crenel.Space.l) {
                ForEach(presentation.sections) { section in
                    VStack(alignment: .leading, spacing: Crenel.Space.xxs) {
                        CrenelSectionHeader(
                            title: section.kind.title,
                            count: section.tasks.count > 1 ? section.tasks.count : nil,
                            tint: Self.sectionTint(section.kind)
                        )
                        .padding(.horizontal, Crenel.Space.xs)
                        .padding(.bottom, Crenel.Space.xxs)
                        VStack(spacing: 2) {
                            ForEach(section.tasks) { task in
                                row(task, now: now, isOverdue: section.kind == .overdue)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ task: TaskItem, now: Date, isOverdue: Bool) -> some View {
        if openTaskID == task.id {
            TaskDetailCard(
                task: task,
                now: now,
                onClose: { openTaskID = nil },
                onRequestDelete: { taskPendingDeletion = task }
            )
            .transition(.crenelMorph(anchor: .top))
        } else {
            TaskRow(
                task: task,
                now: now,
                isOverdue: isOverdue,
                showsPicker: pickerTaskID == task.id,
                onTogglePicker: {
                    pickerTaskID = pickerTaskID == task.id ? nil : task.id
                },
                onPick: { status in
                    actions.tasks.setStatus(task, status)
                    pickerTaskID = nil
                },
                onOpen: {
                    pickerTaskID = nil
                    openTaskID = task.id
                },
                onRequestDelete: { taskPendingDeletion = task }
            )
            .transition(.crenelMorph(anchor: .top))
        }
    }

    // MARK: History

    @ViewBuilder
    private func historyContent(_ presentation: TaskListPresentation) -> some View {
        if presentation.history.isEmpty {
            CrenelEmptyState(
                glyph: .history,
                title: "No history yet",
                detail: "Done tasks move here at the end of the day."
            )
        } else {
            VStack(alignment: .leading, spacing: Crenel.Space.l) {
                ForEach(presentation.history) { day in
                    VStack(alignment: .leading, spacing: Crenel.Space.xxs) {
                        CrenelSectionHeader(title: Self.historyTitle(for: day.day), count: day.tasks.count)
                            .padding(.horizontal, Crenel.Space.xs)
                            .padding(.bottom, Crenel.Space.xxs)
                        VStack(spacing: 2) {
                            ForEach(day.tasks) { task in
                                row(task, now: Date(), isOverdue: false)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private func footer(_ presentation: TaskListPresentation) -> some View {
        HStack(spacing: Crenel.Space.s) {
            Button {
                openTaskID = nil
                pickerTaskID = nil
                showsHistory.toggle()
            } label: {
                HStack(spacing: 6) {
                    CrenelIcon(showsHistory ? .chevronLeft : .history, size: 13)
                    Text(showsHistory ? "Tasks" : "History")
                }
            }
            .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))

            if showsHistory, !presentation.history.isEmpty {
                Button {
                    showsClearHistoryConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        CrenelIcon(.trash, size: 13)
                        Text("Clear")
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
            }

            Spacer(minLength: Crenel.Space.s)

            storageLabel
        }
        .padding(.top, Crenel.Space.xxs)
    }

    @ViewBuilder
    private var storageLabel: some View {
        switch appState.taskStorageStatus {
        case .reminders:
            HStack(spacing: 5) {
                Circle().fill(Crenel.Palette.success).frame(width: 5, height: 5)
                Text("Syncing with Reminders")
            }
            .crenelText(.caption, color: Crenel.Palette.textQuaternary)
            .help("Tasks live in the “Crenel” list in Apple Reminders, so they also show on iPhone and Apple Watch.")
        case .localDenied, .localAfterError, .localNotConnected:
            Button {
                actions.tasks.connectReminders()
            } label: {
                Text("Stored on this Mac")
                    .crenelText(.caption, color: Crenel.Palette.textQuaternary)
            }
            .buttonStyle(.plain)
            .help("Tasks sync automatically once you allow Reminders access.")
        case .localByChoice:
            EmptyView()
        }
    }

    // MARK: Helpers

    private static func sectionTint(_ kind: TaskListPresentation.SectionKind) -> Color {
        switch kind {
        case .inProgress: Crenel.Palette.focus
        case .blocked, .overdue: Crenel.Palette.danger
        case .today: Crenel.Palette.tasks
        default: Crenel.Palette.textTertiary
        }
    }

    private static func historyTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))
    }

    private var deleteTaskAlertBinding: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { if !$0 { taskPendingDeletion = nil } }
        )
    }

    private func motion(_ animation: Animation) -> Animation {
        Crenel.Motion.resolve(animation, reduceMotion: reduceMotion)
    }
}

// MARK: - Row

private struct TaskRow: View {
    let task: TaskItem
    let now: Date
    let isOverdue: Bool
    let showsPicker: Bool
    let onTogglePicker: () -> Void
    let onPick: (TaskStatus) -> Void
    let onOpen: () -> Void
    let onRequestDelete: () -> Void

    @Environment(\.crenelActions) private var actions
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Crenel.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Crenel.Space.m) {
                Button(action: onTogglePicker) {
                    TaskStateGlyph(status: task.status, tint: ringTint, size: 17)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
                }
                .buttonStyle(.plain)
                .help("Change status")
                .accessibilityLabel("Status: \(task.status.title)")
                .accessibilityHint("Opens status options")

                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .crenelText(.body, color: task.isCompleted ? Crenel.Palette.textTertiary : Crenel.Palette.textPrimary)
                            .strikethrough(task.isCompleted, color: Crenel.Palette.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TaskMetaLine(task: task, now: now, isOverdue: isOverdue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the task card")

                if hovering, !task.isCompleted {
                    Button {
                        onPick(.completed)
                    } label: {
                        CrenelIcon(.check, size: 13, weight: 2.2)
                    }
                    .buttonStyle(CrenelIconButtonStyle(diameter: 24, tint: Crenel.Palette.success))
                    .help("Mark as done")
                    .accessibilityLabel("Done")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            if showsPicker {
                TaskStatePicker(current: task.status, onSelect: onPick)
                    .padding(.leading, 36)
                    .transition(.crenelRise)
            }
        }
        .padding(.horizontal, Crenel.Space.s)
        .padding(.vertical, Crenel.Space.s + 1)
        .background {
            RoundedRectangle(cornerRadius: Crenel.Radius.m, style: .continuous)
                .fill(hovering || showsPicker ? Crenel.Palette.layer1 : .clear)
        }
        .onHover { hovering = $0 }
        .animation(Crenel.Motion.snappy, value: hovering)
        .contextMenu { contextActions }
    }

    private var ringTint: Color {
        if isOverdue { return Crenel.Palette.danger }
        switch task.priority {
        case .high: return Crenel.Palette.record
        case .medium: return Crenel.Palette.tasks
        case .low: return Crenel.Palette.dictation
        case .none: return Crenel.Palette.textTertiary
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        ForEach(TaskStatus.allCases) { status in
            Button(status.title) { actions.tasks.setStatus(task, status) }
                .disabled(status == task.status)
        }
        Divider()
        if !task.isCompleted {
            Button("Move to Today") {
                actions.tasks.reschedule(task, Calendar.current.startOfDay(for: Date()), false)
            }
            Button("Postpone to Tomorrow") { actions.tasks.postponeToTomorrow(task) }
        }
        if task.isArchived {
            Button("Restore to List") { actions.tasks.restore(task) }
        } else if task.isCompleted {
            Button("Remove from List") { actions.tasks.archive(task) }
        }
        Divider()
        Button("Delete", role: .destructive, action: onRequestDelete)
    }
}

private struct TaskMetaLine: View {
    let task: TaskItem
    let now: Date
    let isOverdue: Bool
    @Environment(\.crenelActions) private var actions

    var body: some View {
        let due = TaskDueFormatter.label(for: task, now: now)
        if due != nil || task.recurrence != nil || task.priority != .none || task.sourceMeetingID != nil || task.notes != nil {
            HStack(spacing: Crenel.Space.s) {
                if let due {
                    meta(task.dueHasTime ? .clock : .calendar, due,
                         color: isOverdue ? Crenel.Palette.danger : Crenel.Palette.textTertiary)
                }
                if let recurrence = task.recurrence {
                    meta(.history, recurrence.displayText)
                }
                if task.priority != .none {
                    meta(.flag, task.priority.shortText,
                         color: task.priority == .high ? Crenel.Palette.record : Crenel.Palette.textTertiary)
                }
                if task.notes?.isEmpty == false {
                    CrenelIcon(.copy, size: 10.5, weight: 2)
                        .foregroundStyle(Crenel.Palette.textQuaternary)
                        .help("Has a note")
                }
                if let meetingID = task.sourceMeetingID {
                    Button {
                        actions.tasks.openSourceMeeting(meetingID)
                    } label: {
                        meta(.waveform, "Meeting", color: Crenel.Palette.calendar)
                    }
                    .buttonStyle(.plain)
                    .help("Open the meeting this task came from")
                }
            }
            .lineLimit(1)
        }
    }

    private func meta(_ glyph: CrenelGlyph, _ text: String, color: Color = Crenel.Palette.textTertiary) -> some View {
        HStack(spacing: 4) {
            CrenelIcon(glyph, size: 10.5, weight: 2)
            Text(text)
        }
        .crenelText(.caption, color: color)
    }
}

// MARK: - Detail card

/// The task opened in place: title, state, date, priority, notes. Edits save when the
/// field loses focus or on Enter; nothing saves on every keystroke.
private struct TaskDetailCard: View {
    let task: TaskItem
    let now: Date
    let onClose: () -> Void
    let onRequestDelete: () -> Void

    @Environment(\.crenelActions) private var actions
    @State private var title: String
    @State private var notes: String
    @FocusState private var focus: Field?

    private enum Field { case title, notes }

    init(task: TaskItem, now: Date, onClose: @escaping () -> Void, onRequestDelete: @escaping () -> Void) {
        self.task = task
        self.now = now
        self.onClose = onClose
        self.onRequestDelete = onRequestDelete
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Crenel.Space.l) {
            HStack(alignment: .top, spacing: Crenel.Space.m) {
                TaskStateGlyph(status: task.status, tint: Crenel.Palette.textSecondary, size: 20)
                    .padding(.top, 2)
                TextField("Task", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .crenelText(.title)
                    .lineLimit(1...4)
                    .focused($focus, equals: .title)
                    .onSubmit(commit)
                Button(action: close) {
                    CrenelIcon(.chevronDown, size: 14, weight: 2)
                        .rotationEffect(.degrees(180))
                }
                .buttonStyle(CrenelIconButtonStyle(diameter: 26))
                .keyboardShortcut(.cancelAction)
                .help("Close card")
                .accessibilityLabel("Close card")
            }

            TaskStatePicker(current: task.status) { actions.tasks.setStatus(task, $0) }

            VStack(alignment: .leading, spacing: Crenel.Space.s) {
                Text("Date").eyebrow()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Crenel.Space.xs) {
                        dateOption("Today", date: startOfDay(0))
                        dateOption("Tomorrow", date: startOfDay(1))
                        dateOption("Weekend", date: nextWeekend)
                        dateOption("Next week", date: startOfDay(7))
                        if task.dueDate != nil {
                            Button("Remove Date") { actions.tasks.reschedule(task, nil, false) }
                                .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
                        }
                    }
                }
                if let due = TaskDueFormatter.label(for: task, now: now) {
                    HStack(spacing: 6) {
                        CrenelIcon(task.dueHasTime ? .clock : .calendar, size: 12)
                        Text(due)
                        if let recurrence = task.recurrence {
                            Text("·")
                            Text(recurrence.displayText)
                        }
                    }
                    .crenelText(.callout, color: Crenel.Palette.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: Crenel.Space.s) {
                Text("Priority").eyebrow()
                CrenelSegmented(
                    selection: Binding(
                        get: { task.priority },
                        set: { actions.tasks.setPriority(task, $0) }
                    ),
                    items: [
                        .init(value: TaskPriority.none, title: "None"),
                        .init(value: .low, title: "Low"),
                        .init(value: .medium, title: "Medium"),
                        .init(value: .high, title: "High")
                    ]
                )
            }

            VStack(alignment: .leading, spacing: Crenel.Space.s) {
                Text("Note").eyebrow()
                TextField("Add a note", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .crenelText(.body, color: Crenel.Palette.textSecondary)
                    .lineLimit(2...8)
                    .focused($focus, equals: .notes)
                    .padding(Crenel.Space.m)
                    .crenelSurface(Crenel.Palette.layer2, radius: Crenel.Radius.s, lit: false)
            }

            HStack(spacing: Crenel.Space.s) {
                if let meetingID = task.sourceMeetingID {
                    Button {
                        actions.tasks.openSourceMeeting(meetingID)
                    } label: {
                        HStack(spacing: 6) {
                            CrenelIcon(.waveform, size: 13)
                            Text("Open Meeting")
                        }
                    }
                    .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.calendar), size: .small))
                }
                if task.isCompleted && !task.isArchived {
                    Button("Remove from List") { actions.tasks.archive(task); onClose() }
                        .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
                }
                Spacer()
                Button(action: onRequestDelete) {
                    HStack(spacing: 6) {
                        CrenelIcon(.trash, size: 13)
                        Text("Delete")
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.danger), size: .small))
            }
        }
        .padding(Crenel.Space.l)
        .crenelSurface(Crenel.Palette.layer1, radius: Crenel.Radius.l)
        .padding(.vertical, Crenel.Space.xxs)
        .onChange(of: focus) { previous, _ in
            if previous != nil { commit() }
        }
        .onChange(of: task.title) { _, newValue in
            if focus != .title { title = newValue }
        }
        .onDisappear(perform: commit)
    }

    private func dateOption(_ label: LocalizedStringKey, date: Date?) -> some View {
        let isSelected = date.map { day in
            task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        } ?? false
        return Button(label) {
            if let date { actions.tasks.reschedule(task, date, false) }
        }
        .buttonStyle(CrenelButtonStyle(kind: isSelected ? .tinted(Crenel.Palette.tasks) : .secondary, size: .small))
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
        if changed { actions.tasks.save(updated) }
    }
}

// MARK: - Quick add

/// Single-line capture. Detected dates, repeats and priorities appear as suggestions
/// under the field while typing; Tab accepts them, Enter saves (with or without them).
struct TaskQuickAddField: View {
    let onSubmit: (TaskInputParseResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var accepted: [TaskInputSuggestion.Kind] = []
    private let parser = TaskInputParser()

    var body: some View {
        let suggestions = currentSuggestions
        VStack(alignment: .leading, spacing: Crenel.Space.s) {
            HStack(spacing: Crenel.Space.s) {
                CrenelIcon(.plus, size: 14, weight: 2)
                    .foregroundStyle(focused ? Crenel.Palette.tasks : Crenel.Palette.textTertiary)
                    .frame(width: 24, height: 24)

                TextField("Add task", text: $text, prompt: Text("Add task — “send the report tomorrow 3pm”").foregroundStyle(Crenel.Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .crenelText(.body)
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.tab) {
                        guard !suggestions.isEmpty else { return .ignored }
                        acceptAll(suggestions)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        guard !text.isEmpty || !accepted.isEmpty else { return .ignored }
                        reset()
                        return .handled
                    }
                    .accessibilityLabel("New task")
                    .accessibilityHint("Type a date to get a suggestion. Press Tab to add it.")

                if canSubmit {
                    Button(action: submit) {
                        CrenelIcon(.chevronRight, size: 13, weight: 2.4)
                            .rotationEffect(.degrees(-90))
                    }
                    .buttonStyle(CrenelIconButtonStyle(diameter: 26, tint: .black, fill: .white))
                    .accessibilityLabel("Add task")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    CrenelKeyCap(label: "↵")
                        .transition(.opacity)
                }
            }
            .padding(.leading, Crenel.Space.xs)
            .padding(.trailing, Crenel.Space.xs)
            .frame(minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: Crenel.Radius.m, style: .continuous)
                    .fill(focused ? Crenel.Palette.layer2 : Crenel.Palette.layer1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Crenel.Radius.m, style: .continuous)
                    .strokeBorder(focused ? Crenel.Palette.tasks.opacity(0.5) : Crenel.Palette.hairline, lineWidth: 1)
            }
            .shadow(color: focused ? Crenel.Palette.tasks.opacity(0.18) : .clear, radius: 12)

            if !accepted.isEmpty || !suggestions.isEmpty {
                HStack(spacing: Crenel.Space.xs) {
                    ForEach(Array(accepted.enumerated()), id: \.offset) { index, kind in
                        TaskTokenChip(label: Self.label(for: kind), isAccepted: true) {
                            accepted.remove(at: index)
                        }
                    }
                    ForEach(suggestions) { suggestion in
                        TaskTokenChip(label: suggestion.label, isAccepted: false) {
                            accept(suggestion)
                        }
                    }
                    if !suggestions.isEmpty {
                        HStack(spacing: 4) {
                            CrenelKeyCap(label: "⇥")
                            Text("add")
                        }
                        .crenelText(.caption, color: Crenel.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Crenel.Space.s)
                .transition(.crenelRise)
            }
        }
        .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: focused)
        .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: canSubmit)
        .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: suggestions.map(\.id))
        .animation(Crenel.Motion.resolve(Crenel.Motion.snappy, reduceMotion: reduceMotion), value: accepted.count)
    }

    /// Suggestions of a kind the user already accepted are not offered again.
    private var currentSuggestions: [TaskInputSuggestion] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let acceptedKinds = Set(accepted.map(Self.kindKey))
        return parser.suggestions(for: text, now: Date())
            .filter { !acceptedKinds.contains(Self.kindKey($0.kind)) }
    }

    private var canSubmit: Bool {
        TaskItem.normalizedTitle(text) != nil
    }

    /// Ranges come from the text the suggestion was computed for; never apply a stale one.
    private func isCurrent(_ suggestion: TaskInputSuggestion) -> Bool {
        suggestion.range.upperBound <= text.endIndex
            && String(text[suggestion.range]) == suggestion.matchedText
    }

    private func accept(_ suggestion: TaskInputSuggestion) {
        guard isCurrent(suggestion) else { return }
        accepted.append(suggestion.kind)
        var remaining = text
        remaining.removeSubrange(suggestion.range)
        text = remaining
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func acceptAll(_ suggestions: [TaskInputSuggestion]) {
        // Remove later ranges first so earlier indices stay valid.
        for suggestion in suggestions.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where isCurrent(suggestion) {
            accepted.append(suggestion.kind)
            text.removeSubrange(suggestion.range)
        }
        text = text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func submit() {
        guard let title = TaskItem.normalizedTitle(text) else { return }
        var result = TaskInputParseResult(
            title: title,
            dueDate: nil,
            dueHasTime: false,
            recurrence: nil,
            priority: .none
        )
        for kind in accepted {
            switch kind {
            case .due(let date, let hasTime):
                result.dueDate = date
                result.dueHasTime = hasTime
            case .recurrence(let recurrence):
                result.recurrence = recurrence
            case .priority(let priority):
                result.priority = priority
            }
        }
        onSubmit(result)
        reset()
        focused = true
    }

    private func reset() {
        text = ""
        accepted = []
    }

    private static func kindKey(_ kind: TaskInputSuggestion.Kind) -> Int {
        switch kind {
        case .due: 0
        case .recurrence: 1
        case .priority: 2
        }
    }

    private static func label(for kind: TaskInputSuggestion.Kind) -> String {
        switch kind {
        case .due(let date, let hasTime):
            TaskDueFormatter.label(due: date, hasTime: hasTime, now: Date())
        case .recurrence(let recurrence):
            recurrence.displayText
        case .priority(let priority):
            priority.displayText
        }
    }
}

private struct TaskTokenChip: View {
    let label: String
    let isAccepted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                CrenelIcon(isAccepted ? .check : .plus, size: 9, weight: 2.6)
                Text(label).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(isAccepted ? Crenel.Palette.textPrimary : Crenel.Palette.tasks)
            .background(
                isAccepted ? Crenel.Palette.layer3 : Crenel.Palette.tasks.opacity(0.14),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(isAccepted ? "Click to remove" : "Click or press Tab to add")
        .accessibilityLabel(isAccepted ? "\(label), added. Remove" : "Suggested: \(label). Add")
    }
}

extension TaskPriority {
    /// One-word label for metadata lines.
    var shortText: String {
        switch self {
        case .none: ""
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}
