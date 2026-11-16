import SwiftUI

/// One flat task list. Rows have a fixed height and only change colour under the
/// pointer. Tapping a task's box slides its four states in, in place of the title;
/// tapping the task slides to a compact detail page.
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
            ZStack(alignment: .topLeading) {
                if let id = openTaskID, let task = appState.tasks.first(where: { $0.id == id }) {
                    TaskDetailPage(
                        task: task,
                        now: context.date,
                        onBack: { openTaskID = nil },
                        onRequestDelete: { taskPendingDeletion = task }
                    )
                    .transition(push(from: .trailing))
                } else {
                    listPage(presentation, now: context.date)
                        .transition(push(from: .leading))
                }
            }
        }
        .animation(motion(Crenel.Motion.slide), value: openTaskID)
        .animation(motion(Crenel.Motion.slide), value: showsHistory)
        .alert(
            "Görev silinsin mi?",
            isPresented: deleteTaskAlertBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Sil", role: .destructive) {
                if openTaskID == task.id { openTaskID = nil }
                actions.tasks.delete(task)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { task in
            Text(appState.taskStorageStatus.isReminders
                 ? "“\(task.title)” Hatırlatıcılar’dan ve tüm cihazlarınızdan silinecek."
                 : "“\(task.title)” kalıcı olarak silinecek.")
        }
        .alert("Geçmiş temizlensin mi?", isPresented: $showsClearHistoryConfirmation) {
            Button("Tümünü Sil", role: .destructive, action: actions.tasks.clearHistory)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Tamamlanan görevler kalıcı olarak silinecek.")
        }
    }

    // MARK: List

    private func listPage(_ presentation: TaskListPresentation, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Crenel.Space.l) {
            if !showsHistory {
                TaskQuickAddField(onSubmit: actions.tasks.add)
            }
            if showsHistory {
                historyContent(presentation)
            } else {
                activeContent(presentation, now: now)
            }
            footer(presentation)
        }
    }

    @ViewBuilder
    private func activeContent(_ presentation: TaskListPresentation, now: Date) -> some View {
        if presentation.isEmpty {
            CrenelEmptyState(
                glyph: .tasks,
                title: "liste boş",
                detail: "yazıp enter’a basın. “yarın 15:00”, “her pzt”, “!” anlaşılır.",
                tint: Crenel.Palette.tasks
            )
        } else {
            VStack(alignment: .leading, spacing: Crenel.Space.m) {
                ForEach(presentation.sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        CrenelSectionHeader(
                            title: section.kind.title,
                            count: section.tasks.count > 1 ? section.tasks.count : nil,
                            tint: Self.sectionTint(section.kind)
                        )
                        .padding(.horizontal, Crenel.Space.s)
                        ForEach(section.tasks) { task in
                            row(task, now: now, isOverdue: section.kind == .overdue)
                        }
                    }
                }
            }
        }
    }

    private func row(_ task: TaskItem, now: Date, isOverdue: Bool) -> some View {
        TaskRow(
            task: task,
            now: now,
            isOverdue: isOverdue,
            showsPicker: pickerTaskID == task.id,
            onTogglePicker: {
                withAnimation(motion(Crenel.Motion.slide)) {
                    pickerTaskID = pickerTaskID == task.id ? nil : task.id
                }
            },
            onPick: { status in
                actions.tasks.setStatus(task, status)
                withAnimation(motion(Crenel.Motion.slide)) { pickerTaskID = nil }
            },
            onOpen: {
                pickerTaskID = nil
                openTaskID = task.id
            },
            onRequestDelete: { taskPendingDeletion = task }
        )
    }

    @ViewBuilder
    private func historyContent(_ presentation: TaskListPresentation) -> some View {
        if presentation.history.isEmpty {
            CrenelEmptyState(glyph: .history, title: "geçmiş boş", detail: "biten görevler gün sonunda buraya taşınır.")
        } else {
            VStack(alignment: .leading, spacing: Crenel.Space.m) {
                ForEach(presentation.history) { day in
                    VStack(alignment: .leading, spacing: 0) {
                        CrenelSectionHeader(title: Self.historyTitle(for: day.day), count: day.tasks.count)
                            .padding(.horizontal, Crenel.Space.s)
                        ForEach(day.tasks) { task in
                            row(task, now: Date(), isOverdue: false)
                        }
                    }
                }
            }
        }
    }

    private func footer(_ presentation: TaskListPresentation) -> some View {
        HStack(spacing: Crenel.Space.xs) {
            Button {
                pickerTaskID = nil
                showsHistory.toggle()
            } label: {
                HStack(spacing: 6) {
                    CrenelIcon(showsHistory ? .chevronLeft : .history, size: 9)
                    Text(showsHistory ? "görevler" : "geçmiş")
                }
            }
            .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))

            if showsHistory, !presentation.history.isEmpty {
                Button {
                    showsClearHistoryConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        CrenelIcon(.trash, size: 9)
                        Text("temizle")
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
            }
            Spacer(minLength: Crenel.Space.s)
            storageLabel
        }
    }

    @ViewBuilder
    private var storageLabel: some View {
        switch appState.taskStorageStatus {
        case .reminders:
            HStack(spacing: 6) {
                CrenelDot(color: Crenel.Palette.success, size: 4)
                Text("hatırlatıcılar")
            }
            .crenelText(.caption, color: Crenel.Palette.textQuaternary)
            .help("Görevler Apple Hatırlatıcılar’daki “Crenel” listesinde; iPhone ve Watch’ta da görünür.")
        case .localDenied, .localAfterError, .localNotConnected:
            Button {
                actions.tasks.connectReminders()
            } label: {
                HStack(spacing: 6) {
                    CrenelDot(color: Crenel.Palette.textQuaternary, size: 4)
                    Text("bu mac’te")
                }
                .crenelText(.caption, color: Crenel.Palette.textQuaternary)
            }
            .buttonStyle(.plain)
            .help("Hatırlatıcılar izni verildiğinde görevler otomatik eşitlenir.")
        case .localByChoice:
            EmptyView()
        }
    }

    // MARK: Helpers

    private func push(from edge: Edge) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private static func sectionTint(_ kind: TaskListPresentation.SectionKind) -> Color {
        switch kind {
        case .inProgress: Crenel.Palette.focus
        case .blocked, .overdue: Crenel.Palette.danger
        default: Crenel.Palette.textTertiary
        }
    }

    private static func historyTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "bugün" }
        if calendar.isDateInYesterday(day) { return "dün" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))
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
    static let height: CGFloat = 34

    let task: TaskItem
    let now: Date
    let isOverdue: Bool
    let showsPicker: Bool
    let onTogglePicker: () -> Void
    let onPick: (TaskStatus) -> Void
    let onOpen: () -> Void
    let onRequestDelete: () -> Void

    @Environment(\.crenelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Crenel.Space.s) {
            Button(action: onTogglePicker) {
                Group {
                    if showsPicker {
                        CrenelIcon(.chevronLeft, size: 9)
                            .foregroundStyle(Crenel.Palette.textSecondary)
                    } else {
                        TaskStateGlyph(status: task.status, tint: ringTint, size: 13.5)
                    }
                }
                .frame(width: 26, height: Self.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showsPicker ? "Kapat" : "Durumu değiştir")
            .accessibilityLabel(showsPicker ? "Durum seçiciyi kapat" : "Durum: \(task.status.title)")

            ZStack(alignment: .leading) {
                if showsPicker {
                    TaskStatePicker(current: task.status, onSelect: onPick)
                        .transition(slideIn)
                } else {
                    Button(action: onOpen) {
                        HStack(spacing: Crenel.Space.m) {
                            Text(task.title)
                                .crenelText(.body, color: task.isCompleted ? Crenel.Palette.textTertiary : Crenel.Palette.textPrimary)
                                .strikethrough(task.isCompleted, color: Crenel.Palette.textTertiary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            TaskMeta(task: task, now: now, isOverdue: isOverdue)
                        }
                        .frame(height: Self.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Görevi açar")
                    .transition(slideOut)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .padding(.trailing, Crenel.Space.s)
        .frame(height: Self.height)
        .background(PixelCornerShape().fill(hovering || showsPicker ? Crenel.Palette.layer1 : .clear))
        .onHover { hovering = $0 }
        .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: hovering)
        .contextMenu { contextActions }
    }

    private var slideIn: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    private var slideOut: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var ringTint: Color {
        isOverdue ? Crenel.Palette.danger : Crenel.Palette.textTertiary
    }

    @ViewBuilder
    private var contextActions: some View {
        ForEach(TaskStatus.allCases) { status in
            Button(status.title) { actions.tasks.setStatus(task, status) }
                .disabled(status == task.status)
        }
        Divider()
        if !task.isCompleted {
            Button("Bugüne al") {
                actions.tasks.reschedule(task, Calendar.current.startOfDay(for: Date()), false)
            }
            Button("Yarına ertele") { actions.tasks.postponeToTomorrow(task) }
        }
        if task.isArchived {
            Button("Listeye geri al") { actions.tasks.restore(task) }
        } else if task.isCompleted {
            Button("Listeden kaldır") { actions.tasks.archive(task) }
        }
        Divider()
        Button("Sil", role: .destructive, action: onRequestDelete)
    }
}

/// Right-aligned metadata on one line: due, repeat, priority, note, meeting.
private struct TaskMeta: View {
    let task: TaskItem
    let now: Date
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: Crenel.Space.s) {
            if task.notes?.isEmpty == false {
                CrenelIcon(.note, size: 9).foregroundStyle(Crenel.Palette.textQuaternary)
            }
            if task.sourceMeetingID != nil {
                CrenelIcon(.waveform, size: 9).foregroundStyle(Crenel.Palette.calendar)
            }
            if task.recurrence != nil {
                CrenelIcon(.repeatGlyph, size: 9).foregroundStyle(Crenel.Palette.textTertiary)
            }
            if task.priority != .none {
                Text(task.priority.marks)
                    .crenelText(.callout, color: task.priority == .high ? Crenel.Palette.record : Crenel.Palette.tasks)
            }
            if let due = TaskDueFormatter.label(for: task, now: now) {
                Text(due.lowercased(with: Locale(identifier: "tr_TR")))
                    .crenelText(.caption, color: isOverdue ? Crenel.Palette.danger : Crenel.Palette.textTertiary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Detail page

/// A task opened as a compact page of labelled lines. Edits save when a field loses
/// focus or on Enter.
private struct TaskDetailPage: View {
    let task: TaskItem
    let now: Date
    let onBack: () -> Void
    let onRequestDelete: () -> Void

    @Environment(\.crenelActions) private var actions
    @State private var title: String
    @State private var notes: String
    @FocusState private var focus: Field?

    private enum Field { case title, notes }

    init(task: TaskItem, now: Date, onBack: @escaping () -> Void, onRequestDelete: @escaping () -> Void) {
        self.task = task
        self.now = now
        self.onBack = onBack
        self.onRequestDelete = onRequestDelete
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Crenel.Space.m) {
            HStack(spacing: Crenel.Space.s) {
                Button(action: back) {
                    HStack(spacing: 6) {
                        CrenelIcon(.chevronLeft, size: 9)
                        Text("görevler")
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: onRequestDelete) {
                    CrenelIcon(.trash, size: 9)
                }
                .buttonStyle(CrenelIconButtonStyle(diameter: 24, tint: Crenel.Palette.textTertiary))
                .help("Görevi sil")
                .accessibilityLabel("Görevi sil")
            }

            TextField("görev", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .crenelText(.title)
                .lineLimit(1...3)
                .focused($focus, equals: .title)
                .onSubmit(commit)
                .padding(.horizontal, Crenel.Space.s)

            VStack(spacing: 0) {
                line("durum") {
                    TaskStatePicker(current: task.status) { actions.tasks.setStatus(task, $0) }
                }
                line("tarih") {
                    HStack(spacing: 2) {
                        dateOption("bugün", offset: 0)
                        dateOption("yarın", offset: 1)
                        dateOption("+1 hafta", offset: 7)
                        dateChoice("yok", isSelected: task.dueDate == nil) {
                            actions.tasks.reschedule(task, nil, false)
                        }
                        if let due = TaskDueFormatter.label(for: task, now: now), !isPreset {
                            Text(due.lowercased(with: Locale(identifier: "tr_TR")))
                                .crenelText(.caption, color: Crenel.Palette.textSecondary)
                                .padding(.leading, Crenel.Space.xs)
                        }
                    }
                }
                if let recurrence = task.recurrence {
                    line("tekrar") {
                        Text(recurrence.displayText.lowercased(with: Locale(identifier: "tr_TR")))
                            .crenelText(.callout, color: Crenel.Palette.textSecondary)
                    }
                }
                line("öncelik") {
                    HStack(spacing: 2) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            dateChoice(priority == .none ? "—" : priority.marks, isSelected: task.priority == priority) {
                                actions.tasks.setPriority(task, priority)
                            }
                        }
                    }
                }
                line("not", alignment: .firstTextBaseline) {
                    TextField("ekle…", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .crenelText(.callout, color: Crenel.Palette.textSecondary)
                        .lineLimit(1...6)
                        .focused($focus, equals: .notes)
                }
                if let meetingID = task.sourceMeetingID {
                    line("kaynak") {
                        Button {
                            actions.tasks.openSourceMeeting(meetingID)
                        } label: {
                            HStack(spacing: 6) {
                                CrenelIcon(.waveform, size: 9)
                                Text("toplantıyı aç")
                            }
                        }
                        .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.calendar), size: .small))
                    }
                }
            }
            .crenelSurface()
        }
        .onChange(of: focus) { previous, _ in
            if previous != nil { commit() }
        }
        .onChange(of: task.title) { _, newValue in
            if focus != .title { title = newValue }
        }
        .onDisappear(perform: commit)
    }

    private func line<Content: View>(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: Crenel.Space.m) {
            Text(label)
                .crenelText(.caption, color: Crenel.Palette.textTertiary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Crenel.Space.m)
        .frame(minHeight: 36)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Crenel.Palette.hairline).frame(height: 1).padding(.leading, Crenel.Space.m)
        }
    }

    private var isPreset: Bool {
        guard let due = task.dueDate, !task.dueHasTime else { return task.dueDate == nil }
        let calendar = Calendar.current
        return [0, 1, 7].contains { offset in
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
                .map { calendar.isDate($0, inSameDayAs: due) } ?? false
        }
    }

    private func dateOption(_ label: String, offset: Int) -> some View {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        let isSelected = day.map { day in task.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false } ?? false
        return dateChoice(label, isSelected: isSelected) {
            if let day { actions.tasks.reschedule(task, day, false) }
        }
    }

    private func dateChoice(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSelected ? Crenel.Palette.tasks : Crenel.Palette.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(PixelCornerShape().fill(isSelected ? Crenel.Palette.tasks.opacity(0.14) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func back() {
        commit()
        onBack()
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

/// Single-line capture, prompt style. Detected dates, repeats and priorities appear as
/// suggestions under the field; Tab accepts them, Enter saves.
struct TaskQuickAddField: View {
    let onSubmit: (TaskInputParseResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var accepted: [TaskInputSuggestion.Kind] = []
    private let parser = TaskInputParser()

    var body: some View {
        let suggestions = currentSuggestions
        VStack(alignment: .leading, spacing: Crenel.Space.xs) {
            HStack(spacing: Crenel.Space.s) {
                Text("›")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(focused ? Crenel.Palette.brand : Crenel.Palette.textTertiary)
                TextField(
                    "Görev ekle",
                    text: $text,
                    prompt: Text("görev ekle — “yarın 15te rapor”").foregroundStyle(Crenel.Palette.textQuaternary)
                )
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
                .accessibilityLabel("Yeni görev")
                .accessibilityHint("Tarih yazarsanız öneri çıkar; Tab ile ekleyin.")
                CrenelKeyCap(label: "↵")
                    .opacity(canSubmit ? 1 : 0.4)
            }
            .padding(.horizontal, Crenel.Space.m)
            .frame(height: 36)
            .background(PixelCornerShape(steps: 3).fill(Crenel.Palette.layer1))
            .overlay(PixelCornerShape(steps: 3).stroke(focused ? Crenel.Palette.brand.opacity(0.6) : Crenel.Palette.hairline, lineWidth: 1))

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
                            Text("ekle")
                        }
                        .crenelText(.caption, color: Crenel.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Crenel.Space.xs)
                .transition(.opacity)
            }
        }
        .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: focused)
        .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: suggestions.map(\.id))
        .animation(Crenel.Motion.resolve(Crenel.Motion.fade, reduceMotion: reduceMotion), value: accepted.count)
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
            HStack(spacing: 5) {
                CrenelIcon(isAccepted ? .check : .plus, size: 9)
                Text(label.lowercased(with: Locale(identifier: "tr_TR"))).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .foregroundStyle(isAccepted ? Crenel.Palette.textPrimary : Crenel.Palette.brand)
            .background(PixelCornerShape(step: 1.5).fill(isAccepted ? Crenel.Palette.layer3 : Crenel.Palette.brand.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(isAccepted ? "Kaldırmak için tıklayın" : "Eklemek için tıklayın veya Tab’a basın")
        .accessibilityLabel(isAccepted ? "\(label), eklendi. Kaldır" : "\(label) öner. Ekle")
    }
}

extension TaskPriority {
    /// "!", "!!", "!!!" — priority as typed.
    var marks: String {
        String(repeating: "!", count: rawValue)
    }

    var shortText: String {
        switch self {
        case .none: ""
        case .low: "Düşük"
        case .medium: "Orta"
        case .high: "Yüksek"
        }
    }
}
