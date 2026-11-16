import SwiftUI

/// One flat task list. Sections follow from state and due date; the user only types.
struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsHistory: Bool
    @State private var taskPendingDeletion: TaskItem?
    @State private var showsClearHistoryConfirmation = false

    init(initiallyShowsHistory: Bool = false) {
        _showsHistory = State(initialValue: initiallyShowsHistory)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let presentation = appState.taskPresentation(now: context.date)
            LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.MainPanel.contentSpacing) {
                header(presentation)

                if showsHistory {
                    historyContent(presentation)
                        .transition(contentTransition)
                } else {
                    TaskQuickAddField(onSubmit: actions.tasks.add)
                    storageNotice
                    activeContent(presentation, now: context.date)
                        .transition(contentTransition)
                }
            }
        }
        .alert(
            "Görev silinsin mi?",
            isPresented: deleteTaskAlertBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Sil", role: .destructive) { actions.tasks.delete(task) }
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: showsHistory)
    }

    // MARK: Header

    private func header(_ presentation: TaskListPresentation) -> some View {
        HStack(spacing: 8) {
            Text(showsHistory ? "Tamamlananlar" : "Görevler")
                .font(MeetingNotchTheme.MainPanel.sectionTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .lineLimit(1)

            if !showsHistory, appState.taskStorageStatus.isReminders {
                Image(systemName: "icloud")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                    .help("Apple Hatırlatıcılar’daki “Crenel” listesiyle senkronlanıyor")
                    .accessibilityLabel("Hatırlatıcılar ile senkronlanıyor")
            }

            Spacer(minLength: 8)

            if !showsHistory, presentation.activeCount > 0 {
                Text("\(presentation.activeCount)")
                    .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                    .foregroundStyle(MeetingNotchTheme.MainPanel.counterText)
                    .accessibilityLabel("\(presentation.activeCount) açık görev")
            }

            Button {
                showsHistory.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(showsHistory ? "FigmaTasks" : "FigmaArchive")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 16, height: 16)
                    Text(showsHistory ? "Görevler" : "Geçmiş")
                }
            }
            .buttonStyle(TaskHeaderButtonStyle(isActive: showsHistory))
            .help(showsHistory ? "Görevlere dön" : "Tamamlanan görevleri göster")
            .accessibilityLabel(showsHistory ? "Görevlere dön" : "Tamamlanan görevleri göster")
        }
    }

    // MARK: Storage

    @ViewBuilder
    private var storageNotice: some View {
        switch appState.taskStorageStatus {
        case .localNotConnected:
            TaskNoticeRow(
                symbol: "icloud",
                text: "Görevleriniz iPhone ve Watch’ta da görünsün",
                actionTitle: "Hatırlatıcılar’a bağla",
                action: actions.tasks.connectReminders
            )
        case .localDenied:
            TaskNoticeRow(
                symbol: "lock",
                text: "Hatırlatıcılar izni kapalı; görevler bu Mac’te tutuluyor. Sistem Ayarları › Gizlilik › Hatırlatıcılar’dan açabilirsiniz.",
                actionTitle: nil,
                action: {}
            )
        case .localAfterError(let message):
            TaskNoticeRow(
                symbol: "exclamationmark.triangle",
                text: message,
                actionTitle: "Tekrar dene",
                action: actions.tasks.connectReminders
            )
        case .reminders, .localByChoice:
            EmptyView()
        }
    }

    // MARK: Active list

    @ViewBuilder
    private func activeContent(_ presentation: TaskListPresentation, now: Date) -> some View {
        if presentation.isEmpty {
            emptyState(assetName: "FigmaTaskCompleted", text: "Yapılacak bir şey yok. Yazıp Enter’a basın.")
        } else {
            ForEach(presentation.sections) { section in
                VStack(alignment: .leading, spacing: 2) {
                    TaskSectionHeader(kind: section.kind, count: section.tasks.count)
                    LazyVStack(spacing: MeetingNotchTheme.MainPanel.rowSpacing) {
                        ForEach(section.tasks) { task in
                            TaskRowView(
                                task: task,
                                now: now,
                                isOverdue: section.kind == .overdue,
                                onRequestDelete: { taskPendingDeletion = task }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private func historyContent(_ presentation: TaskListPresentation) -> some View {
        if presentation.history.isEmpty {
            emptyState(assetName: "FigmaArchive", text: "Henüz geçmiş yok. Tamamlanan görevler gün bitince buraya taşınır.")
        } else {
            HStack {
                Spacer()
                Button("Geçmişi temizle", systemImage: "trash") {
                    showsClearHistoryConfirmation = true
                }
                .buttonStyle(MeetingNotchActionButtonStyle())
            }
            ForEach(presentation.history) { day in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.historyTitle(for: day.day))
                        .font(MeetingNotchTheme.MainPanel.smallFont)
                        .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                        .padding(.horizontal, MeetingNotchTheme.MainPanel.listRowHorizontalInset)
                    LazyVStack(spacing: MeetingNotchTheme.MainPanel.rowSpacing) {
                        ForEach(day.tasks) { task in
                            TaskRowView(
                                task: task,
                                now: Date(),
                                isOverdue: false,
                                onRequestDelete: { taskPendingDeletion = task }
                            )
                        }
                    }
                }
            }
        }
    }

    private static func historyTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Bugün" }
        if calendar.isDateInYesterday(day) { return "Dün" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR")))
    }

    private func emptyState(assetName: String, text: String) -> some View {
        HStack(spacing: MeetingNotchTheme.MainPanel.itemSpacing) {
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                .frame(width: 20, height: 20)
            Text(text)
                .font(MeetingNotchTheme.MainPanel.bodyFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: MeetingNotchTheme.MainPanel.rowHeight)
    }

    private var deleteTaskAlertBinding: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { if !$0 { taskPendingDeletion = nil } }
        )
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                TextField("Görev ekle — “yarın 15te raporu gönder”", text: $text)
                    .font(MeetingNotchTheme.MainPanel.bodyFont)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                    .textFieldStyle(.plain)
                    .padding(.leading, 8)
                    .frame(height: 40)
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

                Button(action: submit) {
                    Image("FigmaArrowUp")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(TaskSubmitButtonStyle())
                .disabled(!canSubmit)
                .accessibilityLabel("Görevi ekle")
            }
            .padding(4)
            .frame(minHeight: 48)
            .background(
                MeetingNotchTheme.MainPanel.surface,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        focused ? MeetingNotchTheme.cyan : MeetingNotchTheme.hairline,
                        lineWidth: focused ? 2 : 1
                    )
            )

            if !accepted.isEmpty || !suggestions.isEmpty {
                HStack(spacing: 6) {
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
                        Text("⇥ ekle")
                            .font(MeetingNotchTheme.metadataFont)
                            .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
        }
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: focused)
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: suggestions.map(\.id))
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
                Image(systemName: isAccepted ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .lineLimit(1)
            }
            .font(MeetingNotchTheme.metadataFont)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(isAccepted ? MeetingNotchTheme.MainPanel.primaryText : MeetingNotchTheme.cyan)
            .background(
                (isAccepted ? MeetingNotchTheme.MainPanel.surface : MeetingNotchTheme.cyan.opacity(0.12)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .help(isAccepted ? "Kaldırmak için tıklayın" : "Eklemek için tıklayın veya Tab’a basın")
        .accessibilityLabel(isAccepted ? "\(label), eklendi. Kaldır" : "\(label) öner. Ekle")
    }
}

// MARK: - Sections and rows

private struct TaskSectionHeader: View {
    let kind: TaskListPresentation.SectionKind
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(kind.title)
            if count > 1 {
                Text("\(count)").monospacedDigit()
            }
        }
        .font(MeetingNotchTheme.MainPanel.smallFont)
        .foregroundStyle(kind == .overdue ? MeetingNotchTheme.MainPanel.danger : MeetingNotchTheme.MainPanel.secondaryText)
        .padding(.horizontal, MeetingNotchTheme.MainPanel.listRowHorizontalInset)
        .padding(.top, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct TaskRowView: View {
    let task: TaskItem
    let now: Date
    let isOverdue: Bool
    let onRequestDelete: () -> Void

    @Environment(\.crenelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var draftTitle: String

    init(task: TaskItem, now: Date, isOverdue: Bool, onRequestDelete: @escaping () -> Void) {
        self.task = task
        self.now = now
        self.isOverdue = isOverdue
        self.onRequestDelete = onRequestDelete
        _draftTitle = State(initialValue: task.title)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            completionButton

            if isEditing {
                editingContent
            } else {
                titleContent
            }

            if !isEditing, !task.isCompleted, isHovering || task.status == .inProgress {
                focusButton
            }
            actionsMenu
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
        .padding(.horizontal, MeetingNotchTheme.MainPanel.listRowHorizontalInset)
        .background(
            isHovering ? MeetingNotchTheme.MainPanel.surface : .clear,
            in: RoundedRectangle(cornerRadius: MeetingNotchTheme.MainPanel.compactRadius, style: .continuous)
        )
        .onHover { isHovering = $0 }
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: isHovering)
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: task.status)
        .onChange(of: isEditing) { _, editing in editorFocused = editing }
        .onChange(of: task.title) { _, newValue in
            if !isEditing { draftTitle = newValue }
        }
        .contextMenu { taskActions }
    }

    private var completionButton: some View {
        Button {
            actions.tasks.setStatus(task, task.isCompleted ? .open : .completed)
        } label: {
            Image(statusAssetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(statusTint)
                .frame(width: 20, height: 20)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .meetingControlFeedback(radius: 12)
        .help(task.isCompleted ? "Tamamlanmadı olarak işaretle" : "Tamamlandı olarak işaretle")
        .accessibilityLabel(task.isCompleted ? "Tamamlanmadı olarak işaretle" : "Tamamla")
        .accessibilityValue(task.status.title)
    }

    private var focusButton: some View {
        Button {
            actions.tasks.setStatus(task, task.status == .inProgress ? .open : .inProgress)
        } label: {
            Image(systemName: task.status == .inProgress ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(task.status == .inProgress ? MeetingNotchTheme.cyan : MeetingNotchTheme.MainPanel.secondaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .meetingControlFeedback(radius: 10)
        .help(task.status == .inProgress ? "Çalışmayı bırak" : "Üzerinde çalış")
        .accessibilityLabel(task.status == .inProgress ? "Çalışmayı bırak" : "Üzerinde çalış")
        .transition(.opacity)
    }

    private var editingContent: some View {
        HStack(spacing: 4) {
            TextField("Görev", text: $draftTitle)
                .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .focused($editorFocused)
                .meetingFieldSurface(focused: editorFocused)
                .onExitCommand(perform: cancelEdit)
                .onSubmit(commitEdit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleContent: some View {
        Button {
            guard !task.isCompleted else { return }
            isEditing = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                    .foregroundStyle(
                        task.isCompleted
                            ? MeetingNotchTheme.MainPanel.secondaryText
                            : MeetingNotchTheme.MainPanel.primaryText
                    )
                    .strikethrough(task.isCompleted, color: MeetingNotchTheme.MainPanel.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let metadata = metadataLine {
                    metadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.isCompleted ? "" : "Düzenlemek için tıklayın")
    }

    private var metadataLine: (some View)? {
        let dueLabel = TaskDueFormatter.label(for: task, now: now)
        let hasMetadata = dueLabel != nil || task.recurrence != nil || task.priority != .none
            || task.sourceMeetingID != nil || task.assignee != nil || task.status == .inProgress
        guard hasMetadata else { return nil as AnyView? }
        return AnyView(
            HStack(spacing: 8) {
                if task.status == .inProgress {
                    Text("Çalışılıyor")
                        .foregroundStyle(MeetingNotchTheme.cyan)
                }
                if let dueLabel {
                    Label(dueLabel, systemImage: task.dueHasTime ? "clock" : "calendar")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(isOverdue ? MeetingNotchTheme.MainPanel.danger : MeetingNotchTheme.MainPanel.secondaryText)
                }
                if let recurrence = task.recurrence {
                    Label(recurrence.displayText, systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                if task.priority != .none {
                    Text(String(repeating: "!", count: task.priority.rawValue))
                        .foregroundStyle(task.priority == .high ? MeetingNotchTheme.MainPanel.warning : MeetingNotchTheme.MainPanel.secondaryText)
                        .accessibilityLabel(task.priority.displayText)
                }
                if let assignee = task.assignee {
                    Label(assignee, systemImage: "person")
                        .labelStyle(.titleAndIcon)
                }
                if let meetingID = task.sourceMeetingID {
                    Button {
                        actions.tasks.openSourceMeeting(meetingID)
                    } label: {
                        Label("Toplantı", systemImage: "waveform")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .help("Görevin geldiği toplantıyı aç")
                }
            }
            .font(MeetingNotchTheme.metadataFont)
            .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
            .lineLimit(1)
        )
    }

    private var actionsMenu: some View {
        Menu { taskActions } label: {
            Image("FigmaMore")
                .resizable()
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 40, height: 40)
        .meetingControlFeedback(radius: 12)
        .accessibilityLabel("Görev seçenekleri")
    }

    @ViewBuilder
    private var taskActions: some View {
        if task.isArchived {
            Button("Listeye geri al", systemImage: "arrow.uturn.backward") { actions.tasks.restore(task) }
        } else if task.isCompleted {
            Button("Tamamlanmadı", systemImage: "arrow.uturn.backward") { actions.tasks.setStatus(task, .open) }
            Button("Listeden kaldır", systemImage: "archivebox") { actions.tasks.archive(task) }
        } else {
            if task.status == .inProgress {
                Button("Çalışmayı bırak", systemImage: "pause") { actions.tasks.setStatus(task, .open) }
            } else {
                Button("Üzerinde çalış", systemImage: "play") { actions.tasks.setStatus(task, .inProgress) }
            }
            Button("Tamamla", systemImage: "checkmark") { actions.tasks.setStatus(task, .completed) }
            Divider()
            Button("Bugüne al", systemImage: "sun.max") {
                actions.tasks.reschedule(task, Calendar.current.startOfDay(for: Date()), false)
            }
            Button("Yarına ertele", systemImage: "arrow.right") { actions.tasks.postponeToTomorrow(task) }
            if task.dueDate != nil {
                Button("Tarihi kaldır", systemImage: "calendar.badge.minus") {
                    actions.tasks.reschedule(task, nil, false)
                }
            }
            Menu("Öncelik", systemImage: "exclamationmark") {
                ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                    Button(priority.displayText) { actions.tasks.setPriority(task, priority) }
                        .disabled(priority == task.priority)
                }
            }
            Button("Düzenle", systemImage: "pencil") { isEditing = true }
        }
        Divider()
        Button("Sil", systemImage: "trash", role: .destructive, action: onRequestDelete)
    }

    private var statusAssetName: String {
        switch task.status {
        case .open: "FigmaTaskTodo"
        case .inProgress: "FigmaTaskProgress"
        case .completed: "FigmaTaskCompleted"
        }
    }

    private var statusTint: Color {
        switch task.status {
        case .open: isOverdue ? MeetingNotchTheme.MainPanel.danger : MeetingNotchTheme.secondaryText
        case .inProgress: MeetingNotchTheme.cyan
        case .completed: MeetingNotchTheme.success
        }
    }

    private func commitEdit() {
        guard let title = TaskItem.normalizedTitle(draftTitle) else { return }
        actions.tasks.rename(task, title)
        draftTitle = title
        isEditing = false
    }

    private func cancelEdit() {
        draftTitle = task.title
        isEditing = false
    }
}

private struct TaskNoticeRow: View {
    let symbol: String
    let text: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
            Text(text)
                .font(MeetingNotchTheme.MainPanel.smallFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(MeetingNotchActionButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            MeetingNotchTheme.MainPanel.surface.opacity(0.6),
            in: RoundedRectangle(cornerRadius: MeetingNotchTheme.MainPanel.compactRadius, style: .continuous)
        )
    }
}

private struct TaskHeaderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.MainPanel.smallFont)
            .foregroundStyle(isActive ? MeetingNotchTheme.MainPanel.primaryText : MeetingNotchTheme.MainPanel.counterText)
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 40)
            .background(
                MeetingNotchTheme.MainPanel.surface,
                in: RoundedRectangle(cornerRadius: MeetingNotchTheme.MainPanel.compactRadius, style: .continuous)
            )
            .contentShape(Rectangle())
            .meetingControlFeedback(radius: 12)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TaskSubmitButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
            .frame(width: 40, height: 40)
            .background(MeetingNotchTheme.MainPanel.primaryText, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
