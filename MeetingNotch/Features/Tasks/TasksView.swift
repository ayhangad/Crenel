import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newTaskTitle = ""
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

    var body: some View {
        LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.sectionSpacing) {
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
            Text(showsArchive ? "Arşiv" : "Görevler")
                .font(MeetingNotchTheme.titleFont)

            Spacer(minLength: 4)

            if !showsArchive {
                statusSummary
            }

            Button {
                showsArchive.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showsArchive ? "arrow.left" : "archivebox")
                    Text(showsArchive ? "Görevler" : "Arşiv")
                    if !showsArchive, !appState.archivedTasks.isEmpty {
                        Text("\(appState.archivedTasks.count)")
                            .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                    }
                }
            }
            .buttonStyle(
                MeetingNotchCompactButtonStyle(
                    tint: showsArchive ? MeetingNotchTheme.accent : .secondary,
                    isActive: showsArchive
                )
            )
            .help(showsArchive ? "Aktif görevlere dön" : "Görev arşivini aç")
            .accessibilityLabel(showsArchive ? "Aktif görevlere dön" : "Görev arşivini aç")
        }
        .padding(.horizontal, 2)
    }

    private var statusSummary: some View {
        HStack(spacing: 7) {
            ForEach(TaskStatus.activeCases) { status in
                let count = appState.activeTaskCount(for: status)
                HStack(spacing: 3) {
                    Image(systemName: status.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(count)")
                        .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                }
                .foregroundStyle(count == 0 ? Color.secondary.opacity(0.42) : status.tint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(status.title): \(count)")
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(canAdd ? MeetingNotchTheme.accent : Color.secondary.opacity(0.45))
                .frame(width: 16)

            TextField("Yeni görev ekle", text: $newTaskTitle)
                .font(MeetingNotchTheme.bodyFont)
                .textFieldStyle(.plain)
                .onSubmit(addTask)
                .accessibilityLabel("Yeni görev başlığı")

            Button(action: addTask) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(
                MeetingNotchIconButtonStyle(
                    tint: MeetingNotchTheme.accent,
                    isActive: canAdd
                )
            )
            .disabled(!canAdd)
            .accessibilityLabel("Görevi backlog'a ekle")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: 40)
        .background(
            MeetingNotchTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
            .stroke(MeetingNotchTheme.hairline, lineWidth: 1)
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.activeTasks.isEmpty {
                emptyState(symbol: "checkmark.circle", text: "Aktif görev yok")
            } else {
                taskList(appState.activeTasks)
            }
        }
    }

    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Arşivlenmiş görevler")
                    .font(MeetingNotchTheme.sectionTitleFont)
                    .foregroundStyle(.secondary)

                Spacer()

                if !appState.archivedTasks.isEmpty {
                    Menu {
                        Button("Arşivi temizle", systemImage: "trash", role: .destructive) {
                            showsDeleteArchiveConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 32, height: 32)
                    .help("Arşiv seçenekleri")
                    .accessibilityLabel("Arşiv seçenekleri")
                }
            }
            .padding(.horizontal, 2)

            if appState.archivedTasks.isEmpty {
                emptyState(symbol: "archivebox", text: "Arşiv boş")
            } else {
                taskList(appState.archivedTasks)
            }
        }
    }

    private func emptyState(symbol: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text(text)
                .font(MeetingNotchTheme.bodyFont)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 46)
    }

    private func taskList(_ tasks: [TaskItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRowView(
                    task: task,
                    onUpdate: onUpdate,
                    onChangeStatus: { onChangeStatus(task, $0) },
                    onArchive: { onArchive(task) },
                    onRestore: { onRestore(task) },
                    onDelete: { taskPendingDeletion = task }
                )

                if index < tasks.count - 1 {
                    Divider()
                        .overlay(MeetingNotchTheme.subtleHairline)
                        .padding(.leading, 38)
                }
            }
        }
        .padding(.horizontal, 2)
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
    }
}

private struct TaskRowView: View {
    let task: TaskItem
    let onUpdate: (TaskItem, String) -> Void
    let onChangeStatus: (TaskStatus) -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

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
        HStack(spacing: 8) {
            Menu {
                ForEach(TaskStatus.allCases) { status in
                    Button(status.title, systemImage: status.symbolName) {
                        onChangeStatus(status)
                    }
                    .disabled(status == task.status)
                }
            } label: {
                Image(systemName: task.status.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(task.status.tint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 32, height: 32)
            .help("Durum: \(task.status.title)")
            .accessibilityLabel("Görev durumu")
            .accessibilityValue(task.status.title)

            if isEditing {
                TextField("Görev başlığı", text: $draftTitle)
                    .font(MeetingNotchTheme.rowTitleFont)
                    .textFieldStyle(.plain)
                    .onSubmit(commitEdit)

                Button(action: cancelEdit) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MeetingNotchIconButtonStyle())
                .accessibilityLabel("Düzenlemeyi iptal et")

                Button(action: commitEdit) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(
                    MeetingNotchIconButtonStyle(
                        tint: MeetingNotchTheme.success,
                        isActive: true
                    )
                )
                .disabled(TaskItem.normalizedTitle(draftTitle) == nil)
                .accessibilityLabel("Düzenlemeyi kaydet")
            } else {
                Button {
                    isEditing = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(MeetingNotchTheme.rowTitleFont)
                            .foregroundStyle(task.status == .completed ? .secondary : .primary)
                            .strikethrough(task.status == .completed)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(metadataText.uppercased())
                            .font(MeetingNotchTheme.metadataFont.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Düzenlemek için tıklayın")
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(minHeight: 50)
        .background(
            isHovering ? MeetingNotchTheme.surface : .clear,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.controlRadius,
                style: .continuous
            )
        )
        .onHover { isHovering = $0 }
        .onChange(of: task.title) { _, newValue in
            if !isEditing { draftTitle = newValue }
        }
        .contextMenu {
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
    }

    private var metadataText: String {
        if let archivedAt = task.archivedAt {
            return "\(task.status.title) · Arşivlendi \(archivedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(task.status.title) · Eklendi \(task.createdAt.formatted(date: .abbreviated, time: .shortened))"
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
    var symbolName: String {
        switch self {
        case .backlog: "tray"
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .blocked: "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .backlog: .secondary
        case .todo: .blue
        case .inProgress: MeetingNotchTheme.accent
        case .completed: MeetingNotchTheme.success
        case .blocked: .red
        }
    }
}

private struct MeetingNotchCompactButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isActive ? tint : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                isActive ? tint.opacity(0.14) : MeetingNotchTheme.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
                .stroke(isActive ? tint.opacity(0.24) : MeetingNotchTheme.subtleHairline)
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
