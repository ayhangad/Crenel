import Foundation

/// Words dictated per day — numbers only, never the words themselves. Kept for "your
/// usual" on the Today tile, which needs more days than the in-memory history holds.
struct DictationDailyWords: Equatable, Sendable {
    /// Start of day → words dictated that day.
    private(set) var days: [Date: Int] = [:]
    static let keptDays = 30

    init(days: [Date: Int] = [:]) {
        self.days = days
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Adds (or, with a negative count, takes back) words on the day of `date`, and drops
    /// days older than `keptDays`.
    mutating func add(_ words: Int, at date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        days[day] = max(0, days[day, default: 0] + words)
        if days[day] == 0 { days[day] = nil }
        if let oldest = calendar.date(byAdding: .day, value: -Self.keptDays, to: day) {
            days = days.filter { $0.key >= oldest }
        }
    }

    func words(on date: Date, calendar: Calendar = .current) -> Int {
        days[calendar.startOfDay(for: date)] ?? 0
    }
}

/// Keeps `DictationDailyWords` in UserDefaults as `yyyy-MM-dd → words`.
struct DictationDailyWordsStore: @unchecked Sendable {
    static let key = "dictation.dailyWords"
    let defaults: UserDefaults
    var calendar: Calendar = .current

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DictationDailyWords {
        guard let raw = defaults.dictionary(forKey: Self.key) as? [String: Int] else { return DictationDailyWords() }
        var days: [Date: Int] = [:]
        for (key, words) in raw {
            if let date = formatter.date(from: key) { days[calendar.startOfDay(for: date)] = words }
        }
        return DictationDailyWords(days: days)
    }

    func save(_ value: DictationDailyWords) {
        let raw = Dictionary(uniqueKeysWithValues: value.days.map { (formatter.string(from: $0.key), $0.value) })
        defaults.set(raw, forKey: Self.key)
    }

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
