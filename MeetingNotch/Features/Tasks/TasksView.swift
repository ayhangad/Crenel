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
    let onComplete: (TaskItem) -> Void
    let onRestore: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onDeleteArchive: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.sectionSpacing) {
            header
            addField
            activeSection

            if !appState.archivedTasks.isEmpty {
                archiveSection
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
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.2),
            value: showsArchive
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Görevler")
                .font(MeetingNotchTheme.titleFont)

            Spacer()

            HStack(spacing: 6) {
                Text("\(appState.activeTaskCount)")
                    .foregroundStyle(MeetingNotchTheme.success)
                Text("AKTİF")
                    .foregroundStyle(.secondary)
                Text("/")
                    .foregroundStyle(.quaternary)
                Text("\(appState.archivedTasks.count)")
                    .foregroundStyle(.secondary)
                Text("ARŞİV")
                    .foregroundStyle(.tertiary)
            }
            .font(MeetingNotchTheme.metadataFont.monospacedDigit())
        }
        .padding(.horizontal, 2)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(
                    canAdd
                        ? MeetingNotchTheme.accent
                        : Color.secondary.opacity(0.45)
                )
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
            .accessibilityLabel("Görevi ekle")
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

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                title: "Aktif görevler",
                count: appState.activeTasks.count
            )

            if appState.activeTasks.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18)

                    Text("Aktif görev yok")
                        .font(MeetingNotchTheme.bodyFont)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 46)
            } else {
                taskList(
                    appState.activeTasks,
                    primaryAction: onComplete
                )
            }
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    showsArchive.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(showsArchive ? 90 : 0))

                        Text("Arşiv")
                            .font(MeetingNotchTheme.sectionTitleFont)

                        Text("\(appState.archivedTasks.count)")
                            .font(MeetingNotchTheme.dataFont.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    showsArchive
                        ? "Görev arşivini daralt"
                        : "Görev arşivini genişlet"
                )

                Menu {
                    Button("Arşivi temizle", systemImage: "trash", role: .destructive) {
                        showsDeleteArchiveConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .help("Arşiv seçenekleri")
                .accessibilityLabel("Arşiv seçenekleri")
            }
            .padding(.horizontal, 2)

            if showsArchive {
                taskList(
                    appState.archivedTasks,
                    primaryAction: onRestore
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(y: -6))
                )
            }
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(MeetingNotchTheme.sectionTitleFont)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(MeetingNotchTheme.dataFont.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
    }

    private func taskList(
        _ tasks: [TaskItem],
        primaryAction: @escaping (TaskItem) -> Void
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRowView(
                    task: task,
                    onUpdate: onUpdate,
                    onPrimaryAction: { primaryAction(task) },
                    onDelete: { taskPendingDeletion = task }
                )

                if index < tasks.count - 1 {
                    Divider()
                        .overlay(MeetingNotchTheme.subtleHairline)
                        .padding(.leading, 30)
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

    private func addTask() {
        guard let title = TaskItem.normalizedTitle(newTaskTitle) else { return }
        onAdd(title)
        newTaskTitle = ""
    }
}

private struct TaskRowView: View {
    let task: TaskItem
    let onUpdate: (TaskItem, String) -> Void
    let onPrimaryAction: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var isHovering = false
    @State private var draftTitle: String

    init(
        task: TaskItem,
        onUpdate: @escaping (TaskItem, String) -> Void,
        onPrimaryAction: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.task = task
        self.onUpdate = onUpdate
        self.onPrimaryAction = onPrimaryAction
        self.onDelete = onDelete
        _draftTitle = State(initialValue: task.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrimaryAction) {
                Image(systemName: task.isArchived ? "arrow.uturn.backward" : "circle")
                    .font(.system(size: task.isArchived ? 10 : 13, weight: .semibold))
                    .foregroundStyle(task.isArchived ? Color.secondary : MeetingNotchTheme.success)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isArchived ? "Aktife geri al" : "Tamamla ve arşivle")
            .accessibilityLabel(task.isArchived ? "Görevi aktife geri al" : "Görevi tamamla")

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
                            .foregroundStyle(task.isArchived ? .secondary : .primary)
                            .strikethrough(task.isArchived)
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
        .padding(.horizontal, 4)
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
            Button(
                task.isArchived ? "Aktife geri al" : "Tamamla",
                systemImage: task.isArchived ? "arrow.uturn.backward" : "checkmark",
                action: onPrimaryAction
            )

            if !task.isArchived {
                Button("Düzenle", systemImage: "pencil") {
                    isEditing = true
                }
            }

            Divider()

            Button("Görevi sil", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var metadataText: String {
        if let completedAt = task.completedAt {
            return "Tamamlandı \(completedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Eklendi \(task.createdAt.formatted(date: .abbreviated, time: .shortened))"
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
