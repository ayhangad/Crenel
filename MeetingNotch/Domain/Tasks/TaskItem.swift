import Foundation

/// A task has one simple state: to do, in progress, blocked or done. There is no
/// "start" ceremony; the user picks the state. Raw values stay compatible with every
/// earlier build ("backlog" and "todo" decode as to do).
enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case open
    case inProgress
    case blocked
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "To do"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .completed: "Done"
        }
    }

    init(legacyRawValue: String) {
        switch legacyRawValue {
        case "inProgress": self = .inProgress
        case "blocked": self = .blocked
        case "completed": self = .completed
        default: self = .open
        }
    }
}

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    static let maximumTitleLength = 500

    let id: UUID
    var title: String
    var notes: String?
    let createdAt: Date
    private(set) var status: TaskStatus
    private(set) var startedAt: Date?
    private(set) var completedAt: Date?
    /// Set only by an explicit archive action; completing a task never archives it.
    private(set) var archivedAt: Date?
    var dueDate: Date?
    /// False when the task is due on a day rather than at a time.
    var dueHasTime: Bool
    var recurrence: TaskRecurrence?
    var priority: TaskPriority
    /// Manual order within a section; nil sorts after ordered tasks.
    var sortOrder: Double?
    /// `EKReminder.calendarItemIdentifier` when stored in Apple Reminders.
    var reminderIdentifier: String?
    var assignee: String?
    var sourceMeetingID: UUID?
    var sourceActionID: UUID?
    var sourceTime: TimeInterval?
    var sourceSpeakerID: String?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = Date(),
        status: TaskStatus = .open,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        dueDate: Date? = nil,
        dueHasTime: Bool = false,
        recurrence: TaskRecurrence? = nil,
        priority: TaskPriority = .none,
        sortOrder: Double? = nil,
        reminderIdentifier: String? = nil,
        assignee: String? = nil,
        sourceMeetingID: UUID? = nil,
        sourceActionID: UUID? = nil,
        sourceTime: TimeInterval? = nil,
        sourceSpeakerID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.status = completedAt == nil ? status : .completed
        self.startedAt = self.status == .inProgress ? (startedAt ?? createdAt) : nil
        self.completedAt = self.status == .completed ? (completedAt ?? createdAt) : nil
        self.archivedAt = archivedAt
        self.dueDate = dueDate
        self.dueHasTime = dueDate == nil ? false : dueHasTime
        self.recurrence = recurrence
        self.priority = priority
        self.sortOrder = sortOrder
        self.reminderIdentifier = reminderIdentifier
        self.assignee = assignee
        self.sourceMeetingID = sourceMeetingID
        self.sourceActionID = sourceActionID
        self.sourceTime = sourceTime
        self.sourceSpeakerID = sourceSpeakerID
    }

    var isArchived: Bool { archivedAt != nil }
    var isCompleted: Bool { status == .completed }
    var isActive: Bool { !isCompleted && !isArchived }

    mutating func setStatus(_ newStatus: TaskStatus, at date: Date = Date()) {
        guard newStatus != status else { return }
        status = newStatus
        switch newStatus {
        case .open, .blocked:
            startedAt = nil
            completedAt = nil
        case .inProgress:
            startedAt = date
            completedAt = nil
        case .completed:
            completedAt = date
            startedAt = nil
        }
    }

    mutating func archive(at date: Date = Date()) {
        archivedAt = date
    }

    mutating func restore() {
        archivedAt = nil
        if status == .completed {
            status = .open
            completedAt = nil
        }
    }

    mutating func setDue(_ date: Date?, hasTime: Bool) {
        dueDate = date
        dueHasTime = date == nil ? false : hasTime
    }

    /// Completing a recurring task records the finished occurrence and moves the task to
    /// its next due date, like Apple Reminders does.
    func completingRecurrence(
        at date: Date,
        historyID: UUID = UUID(),
        calendar: Calendar = .current
    ) -> (history: TaskItem, next: TaskItem)? {
        guard let recurrence, !isCompleted else { return nil }
        var history = TaskItem(
            id: historyID,
            title: title,
            notes: notes,
            createdAt: createdAt,
            dueDate: dueDate,
            dueHasTime: dueHasTime,
            priority: priority,
            sourceMeetingID: sourceMeetingID
        )
        history.setStatus(.completed, at: date)

        var next = self
        next.setStatus(.open, at: date)
        let anchor = dueDate ?? calendar.startOfDay(for: date)
        var nextDue = recurrence.nextOccurrence(after: anchor, calendar: calendar)
        // An overdue recurring task jumps to its first occurrence after the completion:
        // after today for day-based tasks, after the completion moment for timed ones.
        func isStale(_ candidate: Date) -> Bool {
            dueHasTime
                ? candidate <= date
                : calendar.startOfDay(for: candidate) <= calendar.startOfDay(for: date)
        }
        var guardCount = 0
        while isStale(nextDue), guardCount < 1_000 {
            let advanced = recurrence.nextOccurrence(after: nextDue, calendar: calendar)
            guard advanced > nextDue else { break }
            nextDue = advanced
            guardCount += 1
        }
        next.dueDate = nextDue
        return (history, next)
    }

    static func normalizedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumTitleLength))
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, createdAt, status, startedAt, completedAt, archivedAt
        case dueDate, dueHasTime, recurrence, priority, sortOrder, reminderIdentifier
        case assignee, sourceMeetingID, sourceActionID, sourceTime, sourceSpeakerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let legacyCompletedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        if let raw = try container.decodeIfPresent(String.self, forKey: .status) {
            status = TaskStatus(legacyRawValue: raw)
        } else {
            status = legacyCompletedAt == nil ? .open : .completed
        }
        startedAt = status == .inProgress
            ? try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? createdAt
            : nil
        completedAt = status == .completed ? (legacyCompletedAt ?? createdAt) : nil
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        dueHasTime = try container.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder)
        reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        sourceMeetingID = try container.decodeIfPresent(UUID.self, forKey: .sourceMeetingID)
        sourceActionID = try container.decodeIfPresent(UUID.self, forKey: .sourceActionID)
        sourceTime = try container.decodeIfPresent(TimeInterval.self, forKey: .sourceTime)
        sourceSpeakerID = try container.decodeIfPresent(String.self, forKey: .sourceSpeakerID)
    }
}

extension TaskItem {
    /// A task created from a meeting action item. Action dates are day-level.
    static func imported(from action: ActionItem, id: UUID, meetingID: UUID) -> TaskItem {
        TaskItem(
            id: id,
            title: action.title,
            dueDate: action.dueDate,
            assignee: action.assignee,
            sourceMeetingID: meetingID,
            sourceActionID: action.id,
            sourceTime: action.sourceTime,
            sourceSpeakerID: action.speakerID
        )
    }
}
