import EventKit
import Foundation

/// Owns task persistence and the user's task actions. Keeps AppState in sync with
/// Apple Reminders (or the local fallback) including edits made on other devices.
@MainActor
final class TaskCoordinator {
    let repository: TaskRepositoryRouter
    private let appState: AppState
    private let calendar: Calendar
    private let now: () -> Date
    private var reminderChangeTask: Task<Void, Never>?
    private var dayChangeTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    init(
        appState: AppState,
        repository: TaskRepositoryRouter,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.appState = appState
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    static func live(appState: AppState) -> TaskCoordinator {
        let store = EventKitReminderStore()
        let sidecarURL = (try? TaskSidecarFile.defaultURL())
            ?? FileManager.default.temporaryDirectory.appending(path: "crenel-reminders-sidecar.json")
        let reminders = RemindersTaskRepository(store: store, sidecar: TaskSidecarFile(url: sidecarURL))
        let router = TaskRepositoryRouter(local: FileTaskRepository(), reminders: reminders, store: store)
        return TaskCoordinator(appState: appState, repository: router)
    }

    // MARK: - Lifecycle

    func start(preferReminders: Bool) {
        observeExternalChanges()
        Task { await activate(preferReminders: preferReminders) }
    }

    func activate(preferReminders: Bool) async {
        let status = await repository.activate(preferReminders: preferReminders)
        appState.updateTaskStorageStatus(status)
        await reload()
    }

    func connectReminders() {
        Task {
            let status = await repository.connectReminders()
            appState.updateTaskStorageStatus(status)
            await reload()
        }
    }

    func reload() async {
        do {
            try await repository.prepare()
            appState.replaceTasks(try await repository.loadAll())
        } catch {
            AppLogger.persistenceFailed(operation: "load-tasks", error: error)
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            // EventKit posts bursts of change notifications; coalesce them.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    private func observeExternalChanges() {
        reminderChangeTask?.cancel()
        reminderChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                guard let self, !Task.isCancelled else { return }
                if await self.repository.backend == .reminders {
                    self.scheduleReload()
                }
            }
        }
        dayChangeTask?.cancel()
        dayChangeTask = Task { [weak self] in
            // Sections ("Bugün", "Gecikmiş") depend on the date; republish at midnight.
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                guard let self, !Task.isCancelled else { return }
                self.appState.replaceTasks(self.appState.tasks)
            }
        }
    }

    // MARK: - Actions

    func add(_ parsed: TaskInputParseResult) {
        guard let title = TaskItem.normalizedTitle(parsed.title) else { return }
        var dueDate = parsed.dueDate
        var hasTime = parsed.dueHasTime
        if dueDate == nil, let recurrence = parsed.recurrence {
            // A repeating task without a date starts at its next occurrence.
            let start = calendar.startOfDay(for: now())
            let first = recurrence.nextOccurrence(after: start.addingTimeInterval(-1), calendar: calendar)
            dueDate = first
            hasTime = false
        }
        let task = TaskItem(
            title: title,
            createdAt: now(),
            dueDate: dueDate,
            dueHasTime: hasTime,
            recurrence: parsed.recurrence,
            priority: parsed.priority
        )
        persist(task, operation: "add-task")
    }

    func rename(_ task: TaskItem, to title: String) {
        guard let title = TaskItem.normalizedTitle(title) else { return }
        var updated = task
        updated.title = title
        persist(updated, operation: "update-task")
    }

    func save(_ task: TaskItem) {
        persist(task, operation: "update-task")
    }

    func setStatus(_ task: TaskItem, to status: TaskStatus) {
        let date = now()
        if status == .completed,
           let (history, next) = task.completingRecurrence(at: date, calendar: calendar) {
            persist(history, operation: "complete-recurring-task")
            persist(next, operation: "advance-recurring-task")
            return
        }
        // States are explicit: changing one task never silently changes another.
        var updated = task
        updated.setStatus(status, at: date)
        persist(updated, operation: "change-task-status")
    }

    func reschedule(_ task: TaskItem, to date: Date?, hasTime: Bool = false) {
        var updated = task
        updated.setDue(date, hasTime: hasTime)
        persist(updated, operation: "reschedule-task")
    }

    func postponeToTomorrow(_ task: TaskItem) {
        let start = calendar.startOfDay(for: now())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        if task.dueHasTime, let due = task.dueDate {
            let time = calendar.dateComponents([.hour, .minute], from: due)
            let target = calendar.date(
                bySettingHour: time.hour ?? 9,
                minute: time.minute ?? 0,
                second: 0,
                of: tomorrow
            ) ?? tomorrow
            reschedule(task, to: target, hasTime: true)
        } else {
            reschedule(task, to: tomorrow, hasTime: false)
        }
    }

    func setPriority(_ task: TaskItem, to priority: TaskPriority) {
        var updated = task
        updated.priority = priority
        persist(updated, operation: "prioritize-task")
    }

    func archive(_ task: TaskItem) {
        var updated = task
        updated.archive(at: now())
        persist(updated, operation: "archive-task")
    }

    func restore(_ task: TaskItem) {
        var updated = task
        updated.restore()
        persist(updated, operation: "restore-task")
    }

    func delete(_ task: TaskItem) {
        Task {
            do {
                try await repository.delete(id: task.id)
                appState.removeTask(id: task.id)
            } catch {
                AppLogger.persistenceFailed(operation: "delete-task", error: error)
            }
        }
    }

    func clearHistory() {
        let history = appState.taskPresentation(now: now(), calendar: calendar).history.flatMap(\.tasks)
        guard !history.isEmpty else { return }
        Task {
            for task in history {
                do {
                    try await repository.delete(id: task.id)
                    appState.removeTask(id: task.id)
                } catch {
                    AppLogger.persistenceFailed(operation: "delete-task-history", error: error)
                }
            }
        }
    }

    private func persist(_ task: TaskItem, operation: String) {
        // Optimistic: the list updates immediately, persistence follows.
        appState.upsertTask(task)
        Task {
            do {
                try await repository.save(task)
            } catch {
                AppLogger.persistenceFailed(operation: operation, error: error)
                await reload()
            }
        }
    }
}
