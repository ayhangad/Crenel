import Foundation

/// Task priority. Ordered so that `.high > .medium > .low > .none`.
enum TaskPriority: Int, Codable, CaseIterable, Sendable, Comparable {
    case none = 0, low = 1, medium = 2, high = 3

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short display text, e.g. "High priority".
    var displayText: String {
        switch self {
        case .none: "No priority"
        case .low: "Low priority"
        case .medium: "Medium priority"
        case .high: "High priority"
        }
    }
}

/// Repetition rule of a task.
struct TaskRecurrence: Codable, Equatable, Hashable, Sendable {
    enum Frequency: String, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }

    var frequency: Frequency
    /// Every `interval` units; always >= 1.
    var interval: Int
    /// Calendar weekday numbers (1 = Sunday ... 7 = Saturday) for weekly rules; sorted, unique.
    var weekdays: [Int]?

    init(frequency: Frequency, interval: Int = 1, weekdays: [Int]? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        let cleaned = Array(Set((weekdays ?? []).filter { (1...7).contains($0) })).sorted()
        self.weekdays = cleaned.isEmpty ? nil : cleaned
    }

    static let daily = TaskRecurrence(frequency: .daily)
    static let weekly = TaskRecurrence(frequency: .weekly)
    static let monthly = TaskRecurrence(frequency: .monthly)
    static let yearly = TaskRecurrence(frequency: .yearly)
    /// Monday through Friday.
    static let weekdaysOnly = TaskRecurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])

    static func weekly(on weekdays: [Int], interval: Int = 1) -> TaskRecurrence {
        TaskRecurrence(frequency: .weekly, interval: interval, weekdays: weekdays)
    }

    /// Short display text: "Every day", "Every Monday", "Every weekday", "Every 2 weeks", "Every month", "Every year".
    var displayText: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            guard let weekdays, !weekdays.isEmpty else {
                return interval == 1 ? "Every week" : "Every \(interval) weeks"
            }
            if interval == 1, weekdays == [2, 3, 4, 5, 6] { return "Every weekday" }
            if interval == 1, weekdays == [1, 7] { return "Every weekend" }
            let names = Self.mondayFirst(weekdays).map { Self.weekdayNames[$0] ?? "" }
                .joined(separator: ", ")
            return interval == 1 ? "Every \(names)" : "Every \(interval) weeks on \(names)"
        case .monthly:
            return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly:
            return interval == 1 ? "Every year" : "Every \(interval) years"
        }
    }

    /// First occurrence on or after `date` (start of day). Rules without weekdays start on `date` itself.
    func firstOccurrence(onOrAfter date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard frequency == .weekly, let weekdays, !weekdays.isEmpty else { return start }
        let today = calendar.component(.weekday, from: start)
        let offset = weekdays.map { ($0 - today + 7) % 7 }.min() ?? 0
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    static let weekdayNames: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    private static func mondayFirst(_ weekdays: [Int]) -> [Int] {
        weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
    }
}
