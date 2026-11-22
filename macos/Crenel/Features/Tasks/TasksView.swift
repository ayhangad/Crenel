import SwiftUI

/// One flat task list with the input on top. Groups follow from state and due date; the
/// user only types. A click on a task slides the row left and brings in its actions
/// (state, Edit, Delete); only Edit opens the task in place. One hover slab glides
/// between rows and steps aside for the row that holds its own background.
struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsHistory: Bool
    /// The row whose actions are in view.
    @State private var revealedID: UUID?
    /// Rows that carry their own background: the open one, and one still sliding home.
    @State private var heldIDs: Set<UUID>
    @State private var editingID: UUID?
    /// A picked state shown on the mark before the row has slid home and regrouped.
    @State private var pendingStatus: [UUID: TaskStatus] = [:]
    @State private var taskPendingDeletion: TaskItem?
    @State private var showsClearHistoryConfirmation = false
    @State private var hovered: AnyHashable?
    @Namespace private var glide
    private let initialInput: String

    /// The extra parameters open the view in a given state (offscreen renders, tests).
    init(
        initiallyShowsHistory: Bool = false,
        initialInput: String = "",
        initiallyRevealedTaskID: UUID? = nil,
        initiallyEditingTaskID: UUID? = nil
    ) {
        _showsHistory = State(initialValue: initiallyShowsHistory)
        _revealedID = State(initialValue: initiallyRevealedTaskID)
        _heldIDs = State(initialValue: initiallyRevealedTaskID.map { [$0] } ?? [])
        _editingID = State(initialValue: initiallyEditingTaskID)
        self.initialInput = initialInput
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let presentation = appState.taskPresentation(now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                if showsHistory {
                    historyContent(presentation, now: context.date)
                        .transition(.opacity.combined(with: .offset(x: 14)))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        TaskQuickAddField(
                            knownTitles: appState.tasks.map(\.title),
                            initialText: initialInput,
                            onSubmit: actions.tasks.add
                        )
                                                .padding(.bottom, Hud.Layout.section)
                        activeContent(presentation, now: context.date)
                    }
                    .transition(.opacity.combined(with: .offset(x: -14)))
                }
                footer(presentation)
                    .padding(.top, HudRowKind.icon.sectionGap)
            }
        }
        .animation(motion(Hud.Motion.enter), value: showsHistory)
        .animation(motion(Hud.Motion.card), value: editingID)
        .animation(motion(Hud.Motion.enter), value: appState.tasks)
        .onChange(of: appState.tasks) { _, tasks in settlePendingStatus(tasks) }
        .alert(
            "Delete task?",
            isPresented: deleteTaskAlertBinding,
            presenting: taskPendingDeletion
        ) { task in
            Button("Delete", role: .destructive) {
                if editingID == task.id { editingID = nil }
                revealedID = nil
                heldIDs.remove(task.id)
                actions.tasks.delete(task)
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text(appState.taskStorageStatus.isReminders
                 ? "“\(task.title)” will be deleted from Reminders and all your devices."
                 : "“\(task.title)” will be deleted permanently.")
        }
        .alert("Clear finished tasks?", isPresented: $showsClearHistoryConfirmation) {
            Button("Delete all", role: .destructive, action: actions.tasks.clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finished tasks will be deleted permanently.")
        }
    }

    // MARK: Open tasks

    @ViewBuilder
    private func activeContent(_ presentation: TaskListPresentation, now: Date) -> some View {
        if presentation.isEmpty {
            quietRow("Nothing left to do") { HudLamp(.teal) }
        } else {
            // Two groups, like Today: what is on now (the marks already tell doing and
            // blocked apart) and what comes later; tasks finished today last.
            let groups = Self.groups(presentation.sections)
            let doneToday = groups.first { $0.id == .done }?.rows.count ?? 0
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    VStack(alignment: .leading, spacing: 0) {
                        switch group.id {
                        case .today:
                            HudGroupHeader(title: "Today", count: group.rows.count) {
                                HudCells(done: doneToday, total: group.rows.count + doneToday)
                                    .accessibilityElement()
                                    .accessibilityLabel("\(doneToday) of \(group.rows.count + doneToday) done")
                                    .help("\(doneToday) of \(group.rows.count + doneToday) done")
                            }
                        case .later:
                            HudGroupHeader(title: "Later", count: group.rows.count)
                        case .done:
                            HudGroupHeader(title: "Done", count: group.rows.count)
                        }
                        ForEach(group.rows, id: \.task.id) { item in
                            row(item.task, now: now, isOverdue: item.isOverdue)
                        }
                    }
                    .padding(.top, index == 0 ? 0 : HudRowKind.icon.sectionGap)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ task: TaskItem, now: Date, isOverdue: Bool, showsFinishedTime: Bool = false) -> some View {
        if editingID == task.id {
            TaskEditCard(
                task: task,
                now: now,
                sourceMeetingTitle: task.sourceMeetingID.flatMap { id in
                    appState.storedMeetings.first { $0.id == id }?.title
                },
                onClose: { editingID = nil }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
        } else {
            let isHeld = heldIDs.contains(task.id)
            TaskRowView(
                task: task,
                now: now,
                isOverdue: isOverdue,
                showsFinishedTime: showsFinishedTime,
                displayStatus: pendingStatus[task.id] ?? task.status,
                isRevealed: revealedID == task.id,
                isHeld: isHeld,
                onToggle: { toggleTray(task.id) },
                onLeave: {
                    closeTray(task.id)
                    if hovered == AnyHashable(task.id) {
                        withAnimation(Hud.Motion.slab) { hovered = nil }
                    }
                },
                onPick: { pick($0, for: task) },
                onEdit: { edit(task.id) },
                onRequestDelete: { taskPendingDeletion = task }
            )
            // The list's hover slab steps aside while the row carries its own background.
            .hudGlide(
                task.id,
                hovered: Binding(get: { isHeld ? nil : hovered }, set: { hovered = $0 }),
                in: glide
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -10)),
                removal: .modifier(active: TaskRowCollapse(progress: 1), identity: TaskRowCollapse(progress: 0))
            ))
        }
    }

    private func quietRow<Leading: View>(_ title: LocalizedStringKey, @ViewBuilder leading: () -> Leading) -> some View {
        HStack(spacing: Hud.Row.gap) {
            leading()
            Text(title).hudTrimmed(.body, Hud.Ink.ink2)
        }
        .hudRow(.icon)
    }

    // MARK: Finished

    @ViewBuilder
    private func historyContent(_ presentation: TaskListPresentation, now: Date) -> some View {
        if presentation.history.isEmpty {
            quietRow("Nothing finished yet") {
                HudIcon(.history, size: 14).foregroundStyle(Hud.Ink.ink3)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(presentation.history.enumerated()), id: \.element.id) { index, day in
                    VStack(alignment: .leading, spacing: 0) {
                        HudGroupHeader(title: TaskRowFormat.historyTitle(for: day.day, now: now), count: day.tasks.count)
                        ForEach(day.tasks) { task in
                            row(task, now: now, isOverdue: false, showsFinishedTime: true)
                        }
                    }
                    .padding(.top, index == 0 ? 0 : HudRowKind.icon.sectionGap)
                }
            }
        }
    }

    // MARK: Footer

    /// Where the list lives on the left (a lamp, not a button); what you can do with it
    /// on the right.
    private func footer(_ presentation: TaskListPresentation) -> some View {
        HudActions {
            if showsHistory {
                HudLamp(.dim).frame(width: 13)
                Text(appState.taskStorageStatus.isReminders ? "Finished in the last 30 days" : "Finished tasks")
            } else if appState.taskStorageStatus.isReminders {
                HudLamp(.teal).frame(width: 13)
                Text("Synced with Reminders")
                    .help("Tasks live in the “Crenel” list in Apple Reminders, so they also show on iPhone and Apple Watch.")
            } else {
                HudLamp(.off).frame(width: 13)
                Text("On this Mac only")
            }
        } buttons: {
            if showsHistory {
                if !presentation.history.isEmpty {
                    HudButton("Clear", glyph: .trash, kind: .danger, size: .small) {
                        showsClearHistoryConfirmation = true
                    }
                }
                HudButton("Open tasks", glyph: .chevronLeft, size: .small) { showHistory(false) }
            } else {
                HudButton("Finished", glyph: .history, size: .small) { showHistory(true) }
                if canConnectReminders {
                    HudButton("Connect Reminders", size: .small, action: actions.tasks.connectReminders)
                        .help("Tasks sync automatically once you allow Reminders access.")
                }
            }
        }
        .padding(.horizontal, Hud.Layout.rowPad)
    }

    private var canConnectReminders: Bool {
        switch appState.taskStorageStatus {
        case .localDenied, .localAfterError, .localNotConnected: true
        case .reminders, .localByChoice: false
        }
    }

    // MARK: Row actions

    private func toggleTray(_ id: UUID) {
        if revealedID == id {
            closeTray(id)
            return
        }
        if let open = revealedID { closeTray(open) }
        // The row takes its own background first, then everything slides together.
        heldIDs.insert(id)
        withAnimation(motion(Hud.Motion.rowSlide)) { revealedID = id }
    }

    private func closeTray(_ id: UUID) {
        guard revealedID == id else { return }
        withAnimation(motion(Hud.Motion.rowSlide)) { revealedID = nil }
        // The background lifts only once the row is home.
        after(reduceMotion ? 0 : 0.38) {
            if revealedID != id { heldIDs.remove(id) }
        }
    }

    /// The mark changes in place first, then the row slides home and moves group.
    private func pick(_ status: TaskStatus, for task: TaskItem) {
        guard status != task.status || task.isArchived else {
            closeTray(task.id)
            return
        }
        guard revealedID == task.id, !reduceMotion else {
            closeTray(task.id)
            apply(status, to: task)
            return
        }
        pendingStatus[task.id] = status
        after(0.24) {
            closeTray(task.id)
            after(0.4) {
                apply(status, to: task)
                // If the store never answers, don't leave the mark ahead of the truth.
                after(2) { pendingStatus[task.id] = nil }
            }
        }
    }

    private func apply(_ status: TaskStatus, to task: TaskItem) {
        guard task.isArchived else {
            actions.tasks.setStatus(task, status)
            return
        }
        // A finished task taken off the list comes back to it with the picked state.
        guard status != .completed else { return }
        if status == .open {
            actions.tasks.restore(task)
        } else {
            var restored = task
            restored.restore()
            actions.tasks.setStatus(restored, status)
        }
    }

    private func settlePendingStatus(_ tasks: [TaskItem]) {
        guard !pendingStatus.isEmpty else { return }
        for (id, status) in pendingStatus {
            guard let task = tasks.first(where: { $0.id == id }) else {
                pendingStatus[id] = nil
                continue
            }
            if task.status == status { pendingStatus[id] = nil }
        }
    }

    /// Only Edit opens the row in place: the row slides home, then becomes the card.
    private func edit(_ id: UUID) {
        closeTray(id)
        after(reduceMotion ? 0 : 0.36) {
            heldIDs.remove(id)
            editingID = id
        }
    }

    private func showHistory(_ shows: Bool) {
        editingID = nil
        revealedID = nil
        heldIDs = []
        showsHistory = shows
    }

    // MARK: Helpers

    private enum GroupID: Hashable { case today, later, done }

    private struct Group {
        let id: GroupID
        var rows: [(task: TaskItem, isOverdue: Bool)]
    }

    private static func groups(_ sections: [TaskListPresentation.Section]) -> [Group] {
        var today = Group(id: .today, rows: [])
        var later = Group(id: .later, rows: [])
        var done = Group(id: .done, rows: [])
        for section in sections {
            let rows = section.tasks.map { (task: $0, isOverdue: section.kind == .overdue) }
            switch section.kind {
            case .inProgress, .blocked, .overdue, .today: today.rows += rows
            case .upcoming, .someday: later.rows += rows
            case .completedToday: done.rows += rows
            }
        }
        return [today, later, done].filter { !$0.rows.isEmpty }
    }

    private var deleteTaskAlertBinding: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { if !$0 { taskPendingDeletion = nil } }
        )
    }

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        guard seconds > 0 else {
            work()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}

/// A removed row closes by height and fades (`deleteRow`): 0.26 s in the prototype; here
/// it rides the list's own animation.
private struct TaskRowCollapse: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: Hud.Row.task * (1 - progress), alignment: .top)
            .clipped()
            .opacity(1 - progress)
    }
}
