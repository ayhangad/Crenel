import Foundation

/// Task priority. Ordered so that `.high > .medium > .low > .none`.
enum TaskPriority: Int, Codable, CaseIterable, Sendable, Comparable {
    case none = 0, low = 1, medium = 2, high = 3

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short Turkish display text, e.g. "Yüksek öncelik".
    var displayText: String {
        switch self {
        case .none: "Öncelik yok"
        case .low: "Düşük öncelik"
        case .medium: "Orta öncelik"
        case .high: "Yüksek öncelik"
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

    /// Short Turkish display text: "Her gün", "Her pazartesi", "Her hafta içi", "2 haftada bir", "Her ay", "Her yıl".
    var displayText: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Her gün" : "\(interval) günde bir"
        case .weekly:
            guard let weekdays, !weekdays.isEmpty else {
                return interval == 1 ? "Her hafta" : "\(interval) haftada bir"
            }
            if interval == 1, weekdays == [2, 3, 4, 5, 6] { return "Her hafta içi" }
            if interval == 1, weekdays == [1, 7] { return "Her hafta sonu" }
            let names = Self.mondayFirst(weekdays).map { Self.turkishWeekdayNames[$0] ?? "" }
                .joined(separator: ", ")
            return interval == 1 ? "Her \(names)" : "\(interval) haftada bir \(names)"
        case .monthly:
            return interval == 1 ? "Her ay" : "\(interval) ayda bir"
        case .yearly:
            return interval == 1 ? "Her yıl" : "\(interval) yılda bir"
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

    static let turkishWeekdayNames: [Int: String] = [
        1: "pazar", 2: "pazartesi", 3: "salı", 4: "çarşamba", 5: "perşembe", 6: "cuma", 7: "cumartesi"
    ]

    private static func mondayFirst(_ weekdays: [Int]) -> [Int] {
        weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
    }
}
