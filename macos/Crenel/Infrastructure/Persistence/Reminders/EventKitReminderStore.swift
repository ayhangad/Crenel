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
    case reminderMoved

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "No access to Reminders. Tasks are stored on this Mac."
        case .noReminderSource:
            "No iCloud or local account found for Reminders."
        case .listUnavailable:
            "Couldn't open the Crenel list in Reminders."
        case .reminderMoved:
            "This reminder was moved to another list."
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
    func remove(identifier: String, listIdentifier: String) async throws
}

actor EventKitReminderStore: ReminderStore {
    private var eventStore: EKEventStore
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.eventStore = EKEventStore()
        self.calendar = calendar
        let status = EKEventStore.authorizationStatus(for: .reminder)
        self.hasSeenAccess = status == .fullAccess || status == .authorized
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
        if granted {
            refreshAfterGrant()
        }
        return granted
    }

    struct ListCandidate: Equatable {
        let identifier: String
        let title: String
        let writable: Bool
        let isEmpty: Bool
        /// Carries the colour Crenel gives the lists it creates. It syncs with the list, so
        /// another Mac, or this one after "Delete all data", finds the same list again.
        var hasCrenelColor = false
    }

    /// The list Crenel created, else an empty list with the name. A list with the name that
    /// holds someone else's reminders (a shared list, say) is never taken over.
    static func selectList(_ lists: [ListCandidate], preferred: String?, title: String) -> String? {
        if let preferred, lists.contains(where: { $0.identifier == preferred && $0.writable }) { return preferred }
        let named = lists.filter { $0.title == title && $0.writable }
        return named.filter(\.hasCrenelColor).map(\.identifier).min()
            ?? named.filter(\.isEmpty).map(\.identifier).min()
    }

    static let listColor = (red: 0.37, green: 0.85, blue: 0.59)

    /// Earlier builds made the colour in generic RGB, so both spellings count.
    static func isCrenelColor(_ color: CGColor?) -> Bool {
        let c = listColor
        let known = [CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1),
                     CGColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)]
        guard let mine = srgbComponents(color) else { return false }
        return known.compactMap(srgbComponents).contains { expected in
            zip(mine, expected).allSatisfy { abs($0 - $1) < 0.03 }
        }
    }

    private static func srgbComponents(_ color: CGColor?) -> [CGFloat]? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let parts = color?.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              parts.count >= 3 else { return nil }
        return Array(parts.prefix(3))
    }

    /// An event store made before access was granted keeps seeing no sources or lists,
    /// and `reset()` does not always revive it. The first time access is found, a new store
    /// replaces it so a grant works without relaunching.
    private var hasSeenAccess: Bool

    private func refreshAfterGrant() {
        guard !hasSeenAccess else { return }
        hasSeenAccess = true
        eventStore = EKEventStore()
    }

    func prepareList(preferredIdentifier: String?, title: String) async throws -> String {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        refreshAfterGrant()
        eventStore.refreshSourcesIfNecessary()
        let lists = eventStore.calendars(for: .reminder)
        var candidates: [ListCandidate] = []
        for list in lists where list.allowsContentModifications && (list.calendarIdentifier == preferredIdentifier || list.title == title) {
            if list.calendarIdentifier == preferredIdentifier { return list.calendarIdentifier }
            let predicate = eventStore.predicateForReminders(in: [list])
            let empty = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { items in
                    continuation.resume(returning: items?.isEmpty == true)
                }
            }
            candidates.append(ListCandidate(identifier: list.calendarIdentifier, title: list.title,
                                            writable: list.allowsContentModifications, isEmpty: empty,
                                            hasCrenelColor: Self.isCrenelColor(list.cgColor)))
        }
        if let selected = Self.selectList(candidates, preferred: preferredIdentifier, title: title) { return selected }

        guard let source = preferredSource(existingLists: lists) else {
            throw ReminderStoreError.noReminderSource
        }
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = title
        list.source = source
        list.cgColor = CGColor(srgbRed: Self.listColor.red, green: Self.listColor.green, blue: Self.listColor.blue, alpha: 1)
        try eventStore.saveCalendar(list, commit: true)
        return list.calendarIdentifier
    }

    func fetch(listIdentifier: String, completedSince: Date) async throws -> [ReminderRecord] {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        refreshAfterGrant()
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
            try Self.verifyOwnership(actual: existing.calendar.calendarIdentifier, expected: listIdentifier)
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = list
        }
        apply(record, to: reminder)
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(identifier: String, listIdentifier: String) throws {
        guard accessState() == .authorized else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }
        try Self.verifyOwnership(actual: reminder.calendar.calendarIdentifier, expected: listIdentifier)
        try eventStore.remove(reminder, commit: true)
    }

    static func verifyOwnership(actual: String?, expected: String) throws {
        guard actual == expected else { throw ReminderStoreError.reminderMoved }
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
