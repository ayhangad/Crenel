import Foundation

extension TaskRecurrence {
    /// The first occurrence strictly after `date`, keeping the time of day.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        let step = max(1, interval)
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: step, to: date) ?? date
        case .weekly:
            let days = (weekdays ?? []).filter { (1...7).contains($0) }
            guard !days.isEmpty else {
                return calendar.date(byAdding: .weekOfYear, value: step, to: date) ?? date
            }
            // Walk forward day by day within the current week, then jump `step` weeks.
            for offset in 1...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                let weekday = calendar.component(.weekday, from: candidate)
                let crossesWeek = calendar.component(.weekOfYear, from: candidate)
                    != calendar.component(.weekOfYear, from: date)
                if days.contains(weekday) {
                    if !crossesWeek || step == 1 { return candidate }
                    return calendar.date(byAdding: .weekOfYear, value: step - 1, to: candidate) ?? candidate
                }
            }
            return calendar.date(byAdding: .weekOfYear, value: step, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: step, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: step, to: date) ?? date
        }
    }
}
