import SwiftUI

/// One flat task list with the input on top. Sections follow from state and due date;
/// the user only types. Tapping a task's mark picks its state; tapping the task opens
/// its card. One hover highlight glides between rows.
struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsHistory: Bool
    @State private var openTaskID: UUID?
    @State private var pickerTaskID: UUID?
    @State private var taskPendingDeletion: TaskItem?
    @State private var showsClearHistoryConfirmation = false
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    init(initiallyShowsHistory: Bool = false) {
        _showsHistory = State(initialValue: initiallyShowsHistory)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let presentation = appState.taskPresentation(now: context.date)
            VStack(alignment: .leading, spacing: Hud.Space.x3) {
                if showsHistory {
                    historyContent(presentation)
                        .transition(.opacity.combined(with: .offset(x: 14)))
                } else {
                    TaskQuickAddField(
                        knownTitles: appState.tasks.map(\.title),
                        onSubmit: actions.tasks.add
                    )
                    activeContent(presentation, now: context.date)
                        .transition(.opacity.combined(with: .offset(x: -14)))
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
            quietRow(.queue, "Nothing to do")
        } else {
            // Two groups, like Today: what is on now (state marks already tell in
            // progress and blocked apart) and what comes later; done tasks last.
            VStack(alignment: .leading, spacing: Hud.Space.x3) {
                ForEach(Self.groups(presentation.sections), id: \.id) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HudGroupHeader(title: group.title)
                        ForEach(group.rows, id: \.task.id) { item in
                            row(item.task, now: now, isOverdue: item.isOverdue)
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
            .transition(.opacity)
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
            .hudGlide(task.id, hovered: $hovered, in: glide, forced: pickerTaskID == task.id ? task.id : nil)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
        }
    }

    private func quietRow(_ glyph: HudGlyph, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: Hud.Space.x3) {
            HudIcon(glyph).foregroundStyle(Hud.Ink.text3)
            Text(title).hud(.body, Hud.Ink.text2)
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
    }

    // MARK: History

    @ViewBuilder
    private func historyContent(_ presentation: TaskListPresentation) -> some View {
        if presentation.history.isEmpty {
            quietRow(.history, "No finished tasks yet")
        } else {
            VStack(alignment: .leading, spacing: Hud.Space.x3) {
                ForEach(presentation.history) { day in
                    VStack(alignment: .leading, spacing: 0) {
                        HudGroupHeader(title: Self.historyTitle(for: day.day))
                        ForEach(day.tasks) { task in
                            row(task, now: Date(), isOverdue: false)
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private func footer(_ presentation: TaskListPresentation) -> some View {
        HStack(spacing: Hud.Space.x1) {
            Button {
                openTaskID = nil
                pickerTaskID = nil
                showsHistory.toggle()
            } label: {
                HStack(spacing: 6) {
                    CrenelIcon(showsHistory ? .chevronLeft : .history, size: Hud.Size.smallIcon)
                    Text(showsHistory ? "Tasks" : "Finished")
                }
            }
            .buttonStyle(HudButtonStyle(kind: .ghost))

            if showsHistory, !presentation.history.isEmpty {
                Button("Clear") {
                    showsClearHistoryConfirmation = true
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
            }

            Spacer(minLength: Hud.Space.x2)

            storageLabel
                .padding(.trailing, Hud.Size.rowInset)
        }
    }

    @ViewBuilder
    private var storageLabel: some View {
        switch appState.taskStorageStatus {
        case .reminders:
            Text("Reminders")
                .hud(.meta, Hud.Ink.text4)
            .help("Tasks live in the “Crenel” list in Apple Reminders, so they also show on iPhone and Apple Watch.")
        case .localDenied, .localAfterError, .localNotConnected:
            Button {
                actions.tasks.connectReminders()
            } label: {
                Text("On this Mac")
                    .hud(.meta, Hud.Ink.text4)
            }
            .buttonStyle(.plain)
            .help("Tasks sync automatically once you allow Reminders access.")
        case .localByChoice:
            EmptyView()
        }
    }

    // MARK: Helpers

    private struct Group {
        let id: String
        let title: LocalizedStringKey
        var rows: [(task: TaskItem, isOverdue: Bool)]
    }

    private static func groups(_ sections: [TaskListPresentation.Section]) -> [Group] {
        var now = Group(id: "now", title: "Today", rows: [])
        var later = Group(id: "later", title: "Later", rows: [])
        var done = Group(id: "done", title: "Done", rows: [])
        for section in sections {
            let rows = section.tasks.map { (task: $0, isOverdue: section.kind == .overdue) }
            switch section.kind {
            case .inProgress, .blocked, .overdue, .today: now.rows += rows
            case .upcoming, .someday: later.rows += rows
            case .completedToday: done.rows += rows
            }
        }
        return [now, later, done].filter { !$0.rows.isEmpty }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Hud.Space.x3) {
                Button(action: onTogglePicker) {
                    TaskStateGlyph(status: task.status)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -4)
                .help("Change status")
                .accessibilityLabel("Status: \(task.status.title)")
                .accessibilityHint("Opens status options")

                Button(action: onOpen) {
                    HStack(spacing: Hud.Space.x2) {
                        Text(task.title)
                            .hud(.body, task.isCompleted ? Hud.Ink.text3 : Hud.Ink.text1)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TaskMetaLine(task: task, now: now, isOverdue: isOverdue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the task card")
            }
            .frame(height: 38)

            if showsPicker {
                TaskStatePicker(current: task.status, onSelect: onPick)
                    .padding(.leading, 26)
                    .padding(.bottom, Hud.Space.x2)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .contextMenu { contextActions }
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
        HStack(spacing: Hud.Space.x2) {
            if task.recurrence != nil {
                HudIcon(.history, size: 11).foregroundStyle(Hud.Ink.text4)
                    .help(task.recurrence?.displayText ?? "")
            }
            if let meetingID = task.sourceMeetingID {
                Button {
                    actions.tasks.openSourceMeeting(meetingID)
                } label: {
                    HudIcon(.transcript, size: 11).foregroundStyle(Hud.Ink.text4)
                }
                .buttonStyle(.plain)
                .help("Open the meeting this task came from")
            }
            if task.priority == .high || task.priority == .medium {
                HudIcon(.bell, size: 11)
                    .foregroundStyle(task.priority == .high ? Hud.Ink.signal : Hud.Ink.text3)
                    .help(task.priority.displayText)
            }
            if let due = TaskDueFormatter.label(for: task, now: now),
               task.dueHasTime || !Calendar.current.isDate(task.dueDate ?? .distantPast, inSameDayAs: now) {
                Text(due)
                    .hud(.meta, isOverdue ? Hud.Ink.live : Hud.Ink.text3)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
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
        VStack(alignment: .leading, spacing: Hud.Space.x4) {
            HStack(alignment: .top, spacing: Hud.Space.x3) {
                TaskStateGlyph(status: task.status)
                    .padding(.top, 3)
                TextField("Task", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .hud(.title)
                    .lineLimit(1...4)
                    .focused($focus, equals: .title)
                    .onSubmit(commit)
                Button(action: close) {
                    HudIcon(.close, size: Hud.Size.smallIcon)
                }
                .buttonStyle(HudButtonStyle(kind: .icon))
                .keyboardShortcut(.cancelAction)
                .help("Close card")
                .accessibilityLabel("Close card")
            }

            TaskStatePicker(current: task.status) { actions.tasks.setStatus(task, $0) }

            VStack(alignment: .leading, spacing: Hud.Space.x2) {
                Text("Date").hud(.label, Hud.Ink.text3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Hud.Space.x1) {
                        dateOption("Today", date: startOfDay(0))
                        dateOption("Tomorrow", date: startOfDay(1))
                        dateOption("Weekend", date: nextWeekend)
                        dateOption("Next week", date: startOfDay(7))
                        if task.dueDate != nil {
                            Button("No date") { actions.tasks.reschedule(task, nil, false) }
                                .buttonStyle(HudButtonStyle(kind: .ghost))
                        }
                    }
                }
                if let due = TaskDueFormatter.label(for: task, now: now) {
                    HStack(spacing: Hud.Space.x2) {
                        HudIcon(.calendar, size: 11)
                        Text(due)
                        if let recurrence = task.recurrence {
                            HudIcon(.history, size: 11).padding(.leading, Hud.Space.x1)
                            Text(recurrence.displayText)
                        }
                    }
                    .hud(.meta, Hud.Ink.text2)
                }
            }

            VStack(alignment: .leading, spacing: Hud.Space.x2) {
                Text("Priority").hud(.label, Hud.Ink.text3)
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

            TextField("Note", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .hud(.body, Hud.Ink.text2)
                .lineLimit(2...8)
                .focused($focus, equals: .notes)
                .padding(Hud.Size.rowInset)
                .background(RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous).fill(Hud.Ink.hover))

            HStack(spacing: Hud.Space.x1) {
                if let meetingID = task.sourceMeetingID {
                    Button {
                        actions.tasks.openSourceMeeting(meetingID)
                    } label: {
                        HStack(spacing: 6) {
                            HudIcon(.transcript, size: Hud.Size.smallIcon)
                            Text("Meeting")
                        }
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                }
                if task.isCompleted && !task.isArchived {
                    Button("Remove from list") { actions.tasks.archive(task); onClose() }
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                }
                Spacer()
                Button(action: onRequestDelete) {
                    Text("Delete").foregroundStyle(Hud.Ink.live)
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        }
        .padding(Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x1)
        .background(RoundedRectangle(cornerRadius: Hud.Size.corner + 2, style: .continuous).fill(Color(white: 1, opacity: 0.04)))
        .padding(.vertical, Hud.Space.x1)
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
        .buttonStyle(HudButtonStyle(kind: isSelected ? .iconFilled : .ghost))
        .fixedSize()
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

/// Type and press Return. While typing, dates, repeats and priority are recognised live
/// and shown under the field; Return saves the task with them. A title used before is
/// completed inline (Tab accepts). When nothing is recognised yet, quick picks offer
/// the common dates. Clicking a recognised value drops it.
struct TaskQuickAddField: View {
    var knownTitles: [String] = []
    let onSubmit: (TaskInputParseResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var text = ""
    /// Recognised values the user dismissed for the current text.
    @State private var dismissed: Set<String> = []
    private let parser = TaskInputParser()

    var body: some View {
        let suggestions = currentSuggestions
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Hud.Space.x3) {
                HudIcon(.plus).foregroundStyle(text.isEmpty && !focused ? Hud.Ink.text3 : Hud.Ink.text1)
                ZStack(alignment: .leading) {
                    // Ghost completion sits behind the field, aligned to the typed text.
                    (Text(text).foregroundColor(.clear) + Text(completion ?? "").foregroundColor(Hud.Ink.text4))
                        .font(Hud.Style.body.font)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                    TextField("", text: $text, prompt: Text("Add task").foregroundColor(Hud.Ink.text3))
                        .textFieldStyle(.plain)
                        .font(Hud.Style.body.font)
                        .foregroundStyle(Hud.Ink.text1)
                        .focused($focused)
                        .onSubmit(submit)
                        .onKeyPress(.tab) {
                            guard let completion else { return .ignored }
                            text += completion
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            guard !text.isEmpty else { return .ignored }
                            reset()
                            return .handled
                        }
                        .accessibilityLabel("New task")
                        .accessibilityHint("Dates like tomorrow 3pm are recognised. Press Return to add.")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                    .fill(focused ? Hud.Ink.selected : Hud.Ink.hover)
            )
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty { dismissed = [] }
            }

            // Below the field: what was recognised, or quick picks while nothing is.
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: Hud.Space.x1) {
                    if suggestions.isEmpty {
                        ForEach(QuickPick.allCases, id: \.self) { pick in
                            Button {
                                text = text.trimmingCharacters(in: .whitespaces) + " " + pick.token
                                focused = true
                            } label: {
                                chip(pick.title, glyph: pick.glyph, tint: Hud.Ink.text3, outlined: true)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    } else {
                        ForEach(suggestions) { suggestion in
                            Button {
                                dismissed.insert(suggestion.matchedText)
                            } label: {
                                chip(label(for: suggestion), glyph: glyph(for: suggestion.kind), tint: tint(for: suggestion.kind))
                            }
                            .buttonStyle(.plain)
                            .help("Click to drop")
                            .accessibilityLabel("Recognised: \(label(for: suggestion)). Remove")
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .padding(.top, Hud.Space.x2)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(reduceMotion ? nil : Hud.Motion.glide, value: suggestions.map(\.id))
        .animation(reduceMotion ? nil : Hud.Motion.change, value: text.isEmpty)
        .animation(reduceMotion ? nil : Hud.Motion.hover, value: focused)
    }

    private enum QuickPick: CaseIterable {
        case today, tomorrow, priority

        var token: String {
            switch self {
            case .today: "today"
            case .tomorrow: "tomorrow"
            case .priority: "!!"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .priority: "Priority"
            }
        }

        var glyph: HudGlyph { self == .priority ? .bell : .calendar }
    }

    private var currentSuggestions: [TaskInputSuggestion] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return parser.suggestions(for: text, now: Date())
            .filter { !dismissed.contains($0.matchedText) }
    }

    /// Inline completion from titles used before.
    private var completion: String? {
        guard text.count >= 2 else { return nil }
        let lower = text.lowercased()
        return knownTitles.first { $0.lowercased().hasPrefix(lower) && $0.count > text.count }
            .map { String($0.dropFirst(text.count)) }
    }

    private func chip(_ label: some StringProtocol, glyph: HudGlyph, tint: Color, outlined: Bool = false) -> some View {
        chip(Text(label), glyph: glyph, tint: tint, outlined: outlined)
    }

    private func chip(_ label: LocalizedStringKey, glyph: HudGlyph, tint: Color, outlined: Bool = false) -> some View {
        chip(Text(label), glyph: glyph, tint: tint, outlined: outlined)
    }

    private func chip(_ label: Text, glyph: HudGlyph, tint: Color, outlined: Bool) -> some View {
        HStack(spacing: 5) {
            HudIcon(glyph, size: 11)
            label.font(Hud.Style.meta.font).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background {
            if outlined {
                Capsule().strokeBorder(Hud.Ink.track, lineWidth: 1)
            } else {
                Capsule().fill(Hud.Ink.selected)
            }
        }
        .contentShape(Capsule())
    }

    private func label(for suggestion: TaskInputSuggestion) -> String {
        switch suggestion.kind {
        case .due(let date, let hasTime): TaskDueFormatter.label(due: date, hasTime: hasTime, now: Date())
        case .recurrence(let recurrence): recurrence.displayText
        case .priority(let priority): priority.displayText
        }
    }

    private func glyph(for kind: TaskInputSuggestion.Kind) -> HudGlyph {
        switch kind {
        case .due: .calendar
        case .recurrence: .history
        case .priority: .bell
        }
    }

    private func tint(for kind: TaskInputSuggestion.Kind) -> Color {
        if case .priority(let priority) = kind, priority == .high { return Hud.Ink.signal }
        return Hud.Ink.text1
    }

    private func submit() {
        let result = parser.apply(currentSuggestions, to: text)
        guard let title = TaskItem.normalizedTitle(result.title) else { return }
        var final = result
        final.title = title
        onSubmit(final)
        reset()
        focused = true
    }

    private func reset() {
        text = ""
        dismissed = []
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
