import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
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
        VStack(alignment: .leading, spacing: 12) {
            header
            addField

            ScrollView {
                LazyVStack(spacing: 8) {
                    if appState.activeTasks.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.activeTasks) { task in
                            TaskRowView(
                                task: task,
                                onUpdate: onUpdate,
                                onPrimaryAction: { onComplete(task) },
                                onDelete: { taskPendingDeletion = task }
                            )
                        }
                    }

                    if !appState.archivedTasks.isEmpty {
                        archiveSection
                    }
                }
            }
            .frame(maxHeight: 330)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        }
        .alert("Görev silinsin mi?", isPresented: deleteTaskAlertBinding, presenting: taskPendingDeletion) { task in
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(width: 42, height: 42)
                .background(.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("Görevler")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(appState.activeTaskCount) aktif · \(appState.archivedTasks.count) arşiv")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            TextField("Yeni görev ekle", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .onSubmit(addTask)
                .accessibilityLabel("Yeni görev başlığı")

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAdd ? Color.white : Color.secondary)
            .background(canAdd ? Color.accentColor : Color.white.opacity(0.06), in: Circle())
            .disabled(!canAdd)
            .accessibilityLabel("Görevi ekle")
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(minHeight: 42)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.mint)
            Text("Aktif görev yok — yenisini yukarıdan ekleyebilirsiniz.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var archiveSection: some View {
        DisclosureGroup(isExpanded: $showsArchive) {
            LazyVStack(spacing: 7) {
                ForEach(appState.archivedTasks) { task in
                    TaskRowView(
                        task: task,
                        onUpdate: onUpdate,
                        onPrimaryAction: { onRestore(task) },
                        onDelete: { taskPendingDeletion = task }
                    )
                }

                Button(role: .destructive) {
                    showsDeleteArchiveConfirmation = true
                } label: {
                    Label("Arşivi temizle", systemImage: "trash")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)
        } label: {
            Label("Arşiv (\(appState.archivedTasks.count))", systemImage: "archivebox")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
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
        HStack(spacing: 7) {
            Button(action: onPrimaryAction) {
                Image(systemName: task.isArchived ? "arrow.uturn.backward.circle" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(task.isArchived ? Color.secondary : Color.mint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isArchived ? "Aktife geri al" : "Tamamla ve arşivle")

            if isEditing {
                TextField("Görev başlığı", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(commitEdit)
            } else {
                Button {
                    isEditing = true
                } label: {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(task.isArchived ? .secondary : .primary)
                        .strikethrough(task.isArchived)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Düzenlemek için tıklayın")
            }

            if isEditing {
                Button(action: commitEdit) {
                    Image(systemName: "checkmark")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(TaskItem.normalizedTitle(draftTitle) == nil)
                .accessibilityLabel("Düzenlemeyi kaydet")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.75))
            .accessibilityLabel("\(task.title) görevini sil")
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 42)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .onChange(of: task.title) { _, newValue in
            if !isEditing { draftTitle = newValue }
        }
    }

    private func commitEdit() {
        guard let title = TaskItem.normalizedTitle(draftTitle) else { return }
        onUpdate(task, title)
        draftTitle = title
        isEditing = false
    }
}
