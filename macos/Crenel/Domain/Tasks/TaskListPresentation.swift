import Foundation

/// Groups one flat task list into sections. Users never pick a section; it follows from
/// the task's state and due date.
struct TaskListPresentation: Equatable, Sendable {
    enum SectionKind: String, CaseIterable, Sendable {
        case inProgress
        case blocked
        case overdue
        case today
        case upcoming
        case someday
        case completedToday

        var title: String {
            switch self {
            case .inProgress: "In progress"
            case .blocked: "Blocked"
            case .overdue: "Overdue"
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .someday: "No date"
            case .completedToday: "Done today"
            }
        }
    }

    struct Section: Equatable, Identifiable, Sendable {
        let kind: SectionKind
        let tasks: [TaskItem]
        var id: SectionKind { kind }
    }

    struct HistoryDay: Equatable, Identifiable, Sendable {
        let day: Date
        let tasks: [TaskItem]
        var id: Date { day }
    }

    let sections: [Section]
    let history: [HistoryDay]
    let activeCount: Int
    let inProgress: TaskItem?

    init(tasks: [TaskItem], now: Date, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        var buckets: [SectionKind: [TaskItem]] = [:]
        var historyTasks: [TaskItem] = []

        for task in tasks {
            if task.isArchived {
                historyTasks.append(task)
                continue
            }
            if task.isCompleted {
                if let completedAt = task.completedAt, completedAt >= startOfToday {
                    buckets[.completedToday, default: []].append(task)
                } else {
                    historyTasks.append(task)
                }
                continue
            }
            if task.status == .inProgress {
                buckets[.inProgress, default: []].append(task)
                continue
            }
            if task.status == .blocked {
                buckets[.blocked, default: []].append(task)
                continue
            }
            guard let due = task.dueDate else {
                buckets[.someday, default: []].append(task)
                continue
            }
            let isOverdue = task.dueHasTime ? due < now : due < startOfToday
            if isOverdue {
                buckets[.overdue, default: []].append(task)
            } else if due < startOfTomorrow {
                buckets[.today, default: []].append(task)
            } else {
                buckets[.upcoming, default: []].append(task)
            }
        }

        sections = SectionKind.allCases.compactMap { kind in
            guard let tasks = buckets[kind], !tasks.isEmpty else { return nil }
            return Section(kind: kind, tasks: Self.sorted(tasks, in: kind))
        }

        let groupedHistory = Dictionary(grouping: historyTasks) { task in
            calendar.startOfDay(for: task.archivedAt ?? task.completedAt ?? task.createdAt)
        }
        history = groupedHistory
            .map { day, tasks in
                HistoryDay(
                    day: day,
                    tasks: tasks.sorted {
                        ($0.completedAt ?? $0.archivedAt ?? $0.createdAt)
                            > ($1.completedAt ?? $1.archivedAt ?? $1.createdAt)
                    }
                )
            }
            .sorted { $0.day > $1.day }

        activeCount = tasks.lazy.filter(\.isActive).count
        inProgress = buckets[.inProgress]?.max { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    var isEmpty: Bool { sections.isEmpty }

    private static func sorted(_ tasks: [TaskItem], in kind: SectionKind) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if kind == .completedToday {
                return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }
            if let lhsOrder = lhs.sortOrder, let rhsOrder = rhs.sortOrder, lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            if (lhs.sortOrder == nil) != (rhs.sortOrder == nil) {
                return lhs.sortOrder != nil
            }
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.createdAt < rhs.createdAt
            }
        }
    }
}

/// Short labels for a task's due date: "Today", "Tomorrow 09:00", "Fri 20 Nov".
enum TaskDueFormatter {
    static func label(for task: TaskItem, now: Date, calendar: Calendar = .current) -> String? {
        guard let due = task.dueDate else { return nil }
        return label(due: due, hasTime: task.dueHasTime, now: now, calendar: calendar)
    }

    static func label(due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let time = hasTime ? " " + NotchAgendaFormatter.clockText(due, calendar: calendar) : ""
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue = calendar.startOfDay(for: due)
        let dayOffset = calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0

        switch dayOffset {
        case 0: return "Today" + time
        case 1: return "Tomorrow" + time
        case -1: return "Yesterday" + time
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = AppLanguage.locale
            let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
            if (2...6).contains(dayOffset) {
                formatter.dateFormat = "EEE d MMM"
            } else {
                formatter.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
            }
            return formatter.string(from: due) + time
        }
    }
}
