import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newTaskTitle = ""
    @FocusState private var newTaskFocused: Bool
    @State private var showsArchive = false
    @State private var taskPendingDeletion: TaskItem?
    @State private var showsDeleteArchiveConfirmation = false

    let onAdd: (String) -> Void
    let onUpdate: (TaskItem, String) -> Void
    let onChangeStatus: (TaskItem, TaskStatus) -> Void
    let onArchive: (TaskItem) -> Void
    let onRestore: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onDeleteArchive: () -> Void

    init(
        onAdd: @escaping (String) -> Void,
        onUpdate: @escaping (TaskItem, String) -> Void,
        onChangeStatus: @escaping (TaskItem, TaskStatus) -> Void,
        onArchive: @escaping (TaskItem) -> Void,
        onRestore: @escaping (TaskItem) -> Void,
        onDelete: @escaping (TaskItem) -> Void,
        onDeleteArchive: @escaping () -> Void,
        initiallyShowsArchive: Bool = false
    ) {
        self.onAdd = onAdd
        self.onUpdate = onUpdate
        self.onChangeStatus = onChangeStatus
        self.onArchive = onArchive
        self.onRestore = onRestore
        self.onDelete = onDelete
        self.onDeleteArchive = onDeleteArchive
        _showsArchive = State(initialValue: initiallyShowsArchive)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.MainPanel.contentSpacing) {
            header

            if showsArchive {
                archiveContent
                    .transition(contentTransition)
            } else {
                addField
                activeContent
                    .transition(contentTransition)
            }
        }
        .alert(
            "Görev silinsin mi?",
            isPresented: deleteTaskAlertBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Sil", role: .destructive) { onDelete(task) }
            Button("Vazgeç", role: .cancel) {}
        } message: { task in
            Text("“\(task.title)” kalıcı olarak silinecek.")
        }
        .alert("Arşiv temizlensin mi?", isPresented: $showsDeleteArchiveConfirmation) {
            Button("Tümünü Sil", role: .destructive, action: onDeleteArchive)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(appState.archivedTasks.count) arşivlenmiş görev kalıcı olarak silinecek.")
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: showsArchive)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showsArchive ? "Arşiv" : "Yapılacaklar")
                .font(MeetingNotchTheme.MainPanel.sectionTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !showsArchive {
                ViewThatFits(in: .horizontal) {
                    statusSummary
                    Text("\(appState.activeTasks.count)").font(MeetingNotchTheme.metadataFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                }
            }

            Button {
                showsArchive.toggle()
            } label: {
                if showsArchive {
                    HStack(spacing: 4) {
                        Image("FigmaTasks")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 16, height: 16)
                        Text("Görevler")
                    }
                } else {
                    HStack(spacing: 0) {
                        Text("\(appState.archivedTasks.count)")
                            .padding(.horizontal, 2)
                        Image("FigmaArchive")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .buttonStyle(FigmaTaskArchiveButtonStyle(isActive: showsArchive))
            .help(showsArchive ? "Aktif görevlere dön" : "Görev arşivini aç")
            .accessibilityLabel(showsArchive ? "Aktif görevlere dön" : "Görev arşivini aç")
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 8) {
            ForEach(TaskStatus.allCases.filter { $0 != .completed && statusCount(for: $0) > 0 }) { status in
                let count = statusCount(for: status)
                HStack(spacing: 0) {
                    Text("\(count)")
                        .padding(.horizontal, 2)
                    Image(status.figmaAssetName)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                .font(MeetingNotchTheme.MainPanel.smallFont.monospacedDigit())
                .foregroundStyle(MeetingNotchTheme.MainPanel.counterText)
                .opacity(count == 0 ? 0.62 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(status.title): \(count)")
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 4) {
            TextField("Yeni görev ekle", text: $newTaskTitle)
                .font(MeetingNotchTheme.MainPanel.bodyFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .textFieldStyle(.plain)
                .padding(.leading, 8)
                .frame(height: 40)
                .focused($newTaskFocused)
                .onSubmit(addTask)
                .accessibilityLabel("Yeni görev başlığı")

            Button(action: addTask) {
                Image("FigmaArrowUp")
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(FigmaTaskSubmitButtonStyle())
            .disabled(!canAdd)
            .accessibilityLabel("Yeni görev ekle")
        }
        .padding(4)
        .frame(minHeight: 48)
        .background(
            MeetingNotchTheme.MainPanel.surface,
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(
            newTaskFocused ? MeetingNotchTheme.cyan : MeetingNotchTheme.hairline, lineWidth: newTaskFocused ? 2 : 1))
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: newTaskFocused)
    }

    @ViewBuilder
    private var activeContent: some View {
        if appState.activeTasks.isEmpty {
            emptyState(assetName: "FigmaTaskCompleted", text: "Aktif görev yok")
        } else {
            taskList(appState.activeTasks)
        }
    }

    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.MainPanel.contentSpacing) {
            HStack(spacing: 8) {
                Text("Arşivlenmiş görevler")
                    .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)

                Spacer(minLength: 8)

                if !appState.archivedTasks.isEmpty {
                    Menu {
                        Button("Arşivi temizle", systemImage: "trash", role: .destructive) {
                            showsDeleteArchiveConfirmation = true
                        }
                    } label: {
                        Image("FigmaMore")
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 40, height: 40)
                    .meetingControlFeedback(radius: 12)
                    .accessibilityLabel("Arşiv seçenekleri")
                }
            }

            if appState.archivedTasks.isEmpty {
                emptyState(assetName: "FigmaArchive", text: "Arşiv boş")
            } else {
                taskList(appState.archivedTasks)
            }
        }
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

    private func taskList(_ tasks: [TaskItem]) -> some View {
        LazyVStack(spacing: MeetingNotchTheme.MainPanel.rowSpacing) {
            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    onUpdate: onUpdate,
                    onChangeStatus: { onChangeStatus(task, $0) },
                    onArchive: { onArchive(task) },
                    onRestore: { onRestore(task) },
                    onDelete: { taskPendingDeletion = task }
                )
            }
        }
    }

    private func statusCount(for status: TaskStatus) -> Int {
        if status == .completed {
            return appState.archivedTasks.filter { $0.status == .completed }.count
        }
        return appState.activeTaskCount(for: status)
    }

    private var canAdd: Bool {
        TaskItem.normalizedTitle(newTaskTitle) != nil
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

    private func addTask() {
        guard let title = TaskItem.normalizedTitle(newTaskTitle) else { return }
        onAdd(title)
        newTaskTitle = ""
        newTaskFocused = true
    }
}

private struct TaskRowView: View {
    let task: TaskItem
    let onUpdate: (TaskItem, String) -> Void
    let onChangeStatus: (TaskStatus) -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
    @State private var isEditing = false
    @State private var isHovering = false
    @State private var draftTitle: String

    init(
        task: TaskItem,
        onUpdate: @escaping (TaskItem, String) -> Void,
        onChangeStatus: @escaping (TaskStatus) -> Void,
        onArchive: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.task = task
        self.onUpdate = onUpdate
        self.onChangeStatus = onChangeStatus
        self.onArchive = onArchive
        self.onRestore = onRestore
        self.onDelete = onDelete
        _draftTitle = State(initialValue: task.title)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            statusMenu

            if isEditing {
                editingContent
            } else {
                titleContent
            }

            actionsMenu
        }
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            minHeight: MeetingNotchTheme.MainPanel.rowHeight,
            alignment: .top
        )
        .padding(.horizontal, MeetingNotchTheme.MainPanel.listRowHorizontalInset)
        .background(
            isHovering ? MeetingNotchTheme.MainPanel.surface : .clear,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.MainPanel.compactRadius,
                style: .continuous
            )
        )
        .onHover { isHovering = $0 }
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: isHovering)
        .onChange(of: isEditing) { _, editing in editorFocused = editing }
        .onChange(of: task.title) { _, newValue in
            if !isEditing { draftTitle = newValue }
        }
        .contextMenu { taskActions }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button(status.title, systemImage: status.symbolName) {
                    onChangeStatus(status)
                }
                .disabled(status == task.status)
            }
        } label: {
            Image(task.status.figmaAssetName)
                .resizable().renderingMode(.template).foregroundStyle(task.status.tint)
                .frame(width: 20, height: 20)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 40, height: 40)
        .meetingControlFeedback(radius: 12)
        .help("Durum: \(task.status.title)")
        .accessibilityLabel("Görev durumu")
        .accessibilityValue(task.status.title)
    }

    private var editingContent: some View {
        HStack(spacing: 4) {
            TextField("Görev başlığı", text: $draftTitle)
                .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                .focused($editorFocused)
                .meetingFieldSurface(focused: editorFocused)
                .onExitCommand(perform: cancelEdit)
                .onSubmit(commitEdit)

            Button(action: cancelEdit) {
                Image("FigmaStop")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(MeetingNotchIconButtonStyle())
            .accessibilityLabel("Düzenlemeyi iptal et")

            Button(action: commitEdit) {
                Image("FigmaRecentCheck")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(
                MeetingNotchIconButtonStyle(
                    tint: MeetingNotchTheme.MainPanel.success,
                    isActive: true
                )
            )
            .disabled(TaskItem.normalizedTitle(draftTitle) == nil)
            .accessibilityLabel("Düzenlemeyi kaydet")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleContent: some View {
        Button {
            isEditing = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(MeetingNotchTheme.MainPanel.rowTitleFont)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if task.assignee != nil || task.dueDate != nil {
                    Text([task.assignee, task.dueDate.map { "Son tarih: " + $0.formatted(date: .abbreviated, time: .omitted) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(MeetingNotchTheme.secondaryText)
                }
                Text(metadataText)
                    .font(MeetingNotchTheme.metadataFont)
                    .foregroundStyle(MeetingNotchTheme.MainPanel.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Düzenlemek için tıklayın")
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
        Menu("Durumu değiştir", systemImage: task.status.symbolName) {
            ForEach(TaskStatus.allCases) { status in
                Button(status.title, systemImage: status.symbolName) {
                    onChangeStatus(status)
                }
                .disabled(status == task.status)
            }
        }

        if task.isArchived {
            Button("Aktife geri al", systemImage: "arrow.uturn.backward", action: onRestore)
        } else {
            Button("Arşivle", systemImage: "archivebox", action: onArchive)
            Button("Düzenle", systemImage: "pencil") {
                isEditing = true
            }
        }

        Divider()
        Button("Görevi sil", systemImage: "trash", role: .destructive, action: onDelete)
    }

    private var metadataText: String {
        let date = task.archivedAt ?? task.createdAt
        return "\(task.status.title) · \(date.formatted(date: .abbreviated, time: .omitted)) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func commitEdit() {
        guard let title = TaskItem.normalizedTitle(draftTitle) else { return }
        onUpdate(task, title)
        draftTitle = title
        isEditing = false
    }

    private func cancelEdit() {
        draftTitle = task.title
        isEditing = false
    }
}

private extension TaskStatus {
    var tint: Color {
        switch self {
        case .backlog, .todo: MeetingNotchTheme.secondaryText
        case .inProgress: MeetingNotchTheme.cyan
        case .completed: MeetingNotchTheme.success
        case .blocked: MeetingNotchTheme.warning
        }
    }

    var symbolName: String {
        switch self {
        case .backlog: "tray"
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .blocked: "exclamationmark.octagon.fill"
        }
    }

    var figmaAssetName: String {
        switch self {
        case .backlog: "FigmaTaskBacklog"
        case .todo: "FigmaTaskTodo"
        case .inProgress: "FigmaTaskProgress"
        case .completed: "FigmaTaskCompleted"
        case .blocked: "FigmaTaskBlocked"
        }
    }
}

private struct FigmaTaskArchiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.MainPanel.smallFont.monospacedDigit())
            .foregroundStyle(
                isActive
                    ? MeetingNotchTheme.MainPanel.primaryText
                    : MeetingNotchTheme.MainPanel.counterText
            )
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 40)
            .background(
                MeetingNotchTheme.MainPanel.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.MainPanel.compactRadius,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
            .meetingControlFeedback(radius: 12)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct FigmaTaskSubmitButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
            .frame(width: 40, height: 40)
            .background(
                MeetingNotchTheme.MainPanel.primaryText,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
