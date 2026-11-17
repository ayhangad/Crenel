import EventKit
import Foundation

enum ReminderAccessState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum ReminderStoreError: LocalizedError, Equatable {
    case accessDenied
    case noReminderSource
    case listUnavailable
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "No access to Reminders. Tasks are stored on this Mac."
        case .noReminderSource:
            "No iCloud or local account found for Reminders."
        case .listUnavailable:
            "Couldn't open the Crenel list in Reminders."
        case .reminderNotFound:
            "Reminder not found. It may have been deleted on another device."
        }
    }
}

/// Reads and writes reminders in one list. Everything EventKit-specific lives here;
/// callers only see `ReminderRecord` values.
protocol ReminderStore: Sendable {
    func accessState() async -> ReminderAccessState
    func requestAccess() async throws -> Bool
    /// Resolves (or creates) the list and returns its identifier.
    func prepareList(preferredIdentifier: String?, title: String) async throws -> String
    func fetch(listIdentifier: String, completedSince: Date) async throws -> [ReminderRecord]
    @discardableResult
    func save(_ record: ReminderRecord, listIdentifier: String) async throws -> String
    func remove(identifier: String) async throws
}

actor EventKitReminderStore: ReminderStore {
    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func accessState() -> ReminderAccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .authorized
        case .restricted: .restricted
        case .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToReminders()
        if granted { eventStore.reset() }
        return granted
    }

    func prepareList(preferredIdentifier: String?, title: String) throws -> String {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        eventStore.refreshSourcesIfNecessary()
        if let preferredIdentifier, let existing = eventStore.calendar(withIdentifier: preferredIdentifier),
           existing.allowedEntityTypes.contains(.reminder) {
            return existing.calendarIdentifier
        }
        let lists = eventStore.calendars(for: .reminder)
        if let existing = lists.first(where: { $0.title == title && $0.allowsContentModifications }) {
            return existing.calendarIdentifier
        }

        guard let source = preferredSource(existingLists: lists) else {
            throw ReminderStoreError.noReminderSource
        }
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = title
        list.source = source
        list.cgColor = CGColor(red: 0.37, green: 0.85, blue: 0.59, alpha: 1)
        try eventStore.saveCalendar(list, commit: true)
        return list.calendarIdentifier
    }

    func fetch(listIdentifier: String, completedSince: Date) async throws -> [ReminderRecord] {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        guard let list = eventStore.calendar(withIdentifier: listIdentifier) else {
            throw ReminderStoreError.listUnavailable
        }
        let incomplete = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: [list]
        )
        let completed = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: completedSince,
            ending: nil,
            calendars: [list]
        )
        let open = await fetchRecords(matching: incomplete)
        let done = await fetchRecords(matching: completed)
        return open + done
    }

    func save(_ record: ReminderRecord, listIdentifier: String) throws -> String {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        guard let list = eventStore.calendar(withIdentifier: listIdentifier) else {
            throw ReminderStoreError.listUnavailable
        }
        let reminder: EKReminder
        if let identifier = record.identifier {
            guard let existing = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
                throw ReminderStoreError.reminderNotFound
            }
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = list
        }
        apply(record, to: reminder)
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(identifier: String) throws {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }
        try eventStore.remove(reminder, commit: true)
    }

    // MARK: - Mapping

    private func fetchRecords(matching predicate: NSPredicate) async -> [ReminderRecord] {
        // EKReminder is not Sendable; convert inside the completion handler.
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let records = (reminders ?? []).map(Self.record(from:))
                continuation.resume(returning: records)
            }
        }
    }

    private static func record(from reminder: EKReminder) -> ReminderRecord {
        ReminderRecord(
            identifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDateComponents: reminder.dueDateComponents,
            priority: reminder.priority,
            recurrence: reminder.recurrenceRules?.first.flatMap(recurrence(from:)),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            creationDate: reminder.creationDate,
            url: reminder.url,
            alarmDate: reminder.alarms?.first?.absoluteDate
        )
    }

    private func apply(_ record: ReminderRecord, to reminder: EKReminder) {
        reminder.title = record.title
        reminder.notes = record.notes
        reminder.dueDateComponents = record.dueDateComponents
        reminder.startDateComponents = nil
        reminder.priority = record.priority
        reminder.url = record.url
        if reminder.isCompleted != record.isCompleted {
            reminder.isCompleted = record.isCompleted
        }
        if record.isCompleted, let completionDate = record.completionDate {
            reminder.completionDate = completionDate
        }

        let desiredRule = record.recurrence.map(Self.rule(from:))
        let currentRecurrence = reminder.recurrenceRules?.first.flatMap(Self.recurrence(from:))
        if currentRecurrence != record.recurrence {
            reminder.recurrenceRules?.forEach { reminder.removeRecurrenceRule($0) }
            if let desiredRule { reminder.addRecurrenceRule(desiredRule) }
        }

        let currentAlarm = reminder.alarms?.first?.absoluteDate
        if currentAlarm != record.alarmDate {
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
            if let alarmDate = record.alarmDate {
                reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
            }
        }
    }

    private static func rule(from recurrence: TaskRecurrence) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch recurrence.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = recurrence.weekdays?.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, recurrence.interval),
            daysOfTheWeek: days?.isEmpty == false ? days : nil,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }

    private static func recurrence(from rule: EKRecurrenceRule) -> TaskRecurrence? {
        let frequency: TaskRecurrence.Frequency = switch rule.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        @unknown default: .weekly
        }
        let weekdays = rule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue }.sorted()
        return TaskRecurrence(
            frequency: frequency,
            interval: max(1, rule.interval),
            weekdays: weekdays?.isEmpty == false ? weekdays : nil
        )
    }

    private func preferredSource(existingLists: [EKCalendar]) -> EKSource? {
        if let source = eventStore.defaultCalendarForNewReminders()?.source { return source }
        let sources = eventStore.sources.filter { !$0.calendars(for: .reminder).isEmpty }
        return sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? sources.first { $0.sourceType == .local }
            ?? sources.first
            ?? existingLists.first?.source
    }
}
