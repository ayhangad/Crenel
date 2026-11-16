import Foundation

/// EventKit-free snapshot of an Apple Reminders item. The EventKit store converts
/// `EKReminder` to and from this record so the task mapping stays unit-testable.
struct ReminderRecord: Equatable, Sendable {
    var identifier: String?
    var title: String
    var notes: String?
    var dueDateComponents: DateComponents?
    /// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
    var priority: Int
    var recurrence: TaskRecurrence?
    var isCompleted: Bool
    var completionDate: Date?
    var creationDate: Date?
    var url: URL?
    var alarmDate: Date?
}

/// Crenel-only task data that Apple Reminders has no field for. Stored per Mac, keyed by
/// the reminder identifier. On iPhone the same task is a plain reminder.
struct TaskSidecarEntry: Codable, Equatable, Sendable {
    var taskID: UUID
    var isInProgress: Bool = false
    var startedAt: Date?
    var archivedAt: Date?
    var sortOrder: Double?
    var assignee: String?
    var sourceMeetingID: UUID?
    var sourceActionID: UUID?
    var sourceTime: TimeInterval?
    var sourceSpeakerID: String?
}

enum ReminderTaskMapper {
    static let meetingURLScheme = "crenel"

    static func record(
        from task: TaskItem,
        identifier: String?,
        calendar: Calendar = .current
    ) -> ReminderRecord {
        ReminderRecord(
            identifier: identifier,
            title: task.title,
            notes: task.notes,
            dueDateComponents: task.dueDate.map { dueComponents($0, hasTime: task.dueHasTime, calendar: calendar) },
            priority: eventKitPriority(task.priority),
            recurrence: task.recurrence,
            isCompleted: task.isCompleted,
            completionDate: task.completedAt,
            creationDate: task.createdAt,
            url: task.sourceMeetingID.map(meetingURL),
            alarmDate: task.dueHasTime ? task.dueDate : nil
        )
    }

    static func sidecar(from task: TaskItem) -> TaskSidecarEntry {
        TaskSidecarEntry(
            taskID: task.id,
            isInProgress: task.status == .inProgress,
            startedAt: task.startedAt,
            archivedAt: task.archivedAt,
            sortOrder: task.sortOrder,
            assignee: task.assignee,
            sourceMeetingID: task.sourceMeetingID,
            sourceActionID: task.sourceActionID,
            sourceTime: task.sourceTime,
            sourceSpeakerID: task.sourceSpeakerID
        )
    }

    static func task(
        from record: ReminderRecord,
        sidecar: TaskSidecarEntry?,
        calendar: Calendar = .current,
        fallbackCreationDate: Date = Date()
    ) -> TaskItem {
        let identifier = record.identifier ?? UUID().uuidString
        let createdAt = record.creationDate ?? fallbackCreationDate
        let status: TaskStatus = record.isCompleted
            ? .completed
            : (sidecar?.isInProgress == true ? .inProgress : .open)
        let due = record.dueDateComponents.flatMap { dueDate(from: $0, calendar: calendar) }

        return TaskItem(
            id: sidecar?.taskID ?? taskID(forReminderIdentifier: identifier),
            title: record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "İsimsiz görev"
                : record.title,
            notes: record.notes?.isEmpty == true ? nil : record.notes,
            createdAt: createdAt,
            status: status,
            startedAt: status == .inProgress ? sidecar?.startedAt : nil,
            completedAt: record.isCompleted ? (record.completionDate ?? createdAt) : nil,
            archivedAt: sidecar?.archivedAt,
            dueDate: due?.date,
            dueHasTime: due?.hasTime ?? false,
            recurrence: record.recurrence,
            priority: taskPriority(record.priority),
            sortOrder: sidecar?.sortOrder,
            reminderIdentifier: identifier,
            assignee: sidecar?.assignee,
            sourceMeetingID: sidecar?.sourceMeetingID ?? record.url.flatMap(meetingID),
            sourceActionID: sidecar?.sourceActionID,
            sourceTime: sidecar?.sourceTime,
            sourceSpeakerID: sidecar?.sourceSpeakerID
        )
    }

    /// Reminders created outside Crenel (iPhone, Siri) get a stable id from their identifier.
    static func taskID(forReminderIdentifier identifier: String) -> UUID {
        MeetingStableIdentifier.uuid(for: "reminder|\(identifier)")
    }

    static func eventKitPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .none: 0
        case .high: 1
        case .medium: 5
        case .low: 9
        }
    }

    static func taskPriority(_ value: Int) -> TaskPriority {
        switch value {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }

    static func dueComponents(_ date: Date, hasTime: Bool, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents(
            hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day],
            from: date
        )
        components.calendar = calendar
        if hasTime { components.timeZone = calendar.timeZone }
        return components
    }

    static func dueDate(from components: DateComponents, calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        let hasTime = components.hour != nil
        var resolved = components
        resolved.calendar = resolved.calendar ?? calendar
        if !hasTime {
            resolved.hour = 0
            resolved.minute = 0
            // Day-level reminders float with the user's current time zone.
            resolved.timeZone = calendar.timeZone
        }
        guard let date = resolved.calendar?.date(from: resolved) ?? calendar.date(from: resolved) else {
            return nil
        }
        return (date, hasTime)
    }

    static func meetingURL(_ meetingID: UUID) -> URL {
        URL(string: "\(meetingURLScheme)://meeting/\(meetingID.uuidString)")!
    }

    static func meetingID(from url: URL) -> UUID? {
        guard url.scheme == meetingURLScheme, url.host() == "meeting" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
