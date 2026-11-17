import Foundation

// Rule-based, deterministic quick-capture parser for Turkish and English task input.
//
// Pipeline: tokenize -> scan left to right -> keep one suggestion per kind -> resolve dates.
// Matching runs on normalized tokens (Turkish-locale lowercase, diacritics folded, apostrophes
// removed: "Cuma'ya" -> "cumaya", "15'te" -> "15te"), so it is case- and diacritic-insensitive.
//
// Precedence rules
// - Tokens inside URLs, e-mails, @mentions, #hashtags, versions ("v1.2", "version 2.10"),
//   money ("15.00 TL", "$5", "%20") and phone-number-like digit runs are never matched.
// - At each token every matcher (recurrence, due, priority) is tried; the longest match wins and
//   ties go to recurrence > due > priority ("her pazartesi" is a recurrence, not a weekday).
//   Scanning resumes after the winning span, so matches never overlap. Only whole tokens match,
//   so partial input ("yar", "next Mo") produces nothing and "cumartesi" is never "cuma".
// - A due phrase is a day phrase with an optional adjacent time phrase before or after it
//   ("yarın 15te", "at 3pm tomorrow"). Connectors belong to the span: leading until/by/on/for/
//   before/due/en geç/at/saat, trailing günü/kadar/at the latest.
// - One suggestion per kind; the first due phrase containing a day beats a time-only phrase.
//   Bare part-of-day words ("akşam", "morning") only count next to a day ("yarın akşam").
// - Date semantics (weeks run Monday...Sunday):
//   bare weekday = next occurrence, today excluded unless a still-future time is given today;
//   "this/bu X" = X of the current week if not past, otherwise next occurrence;
//   "next/haftaya X" = X of next week (never today); next week = Monday of next week;
//   weekend = Saturday (today on Sat/Sun); end of week / this week / hafta sonuna kadar = Friday
//   (next week's Friday on Sat/Sun); end of month = last day; next month = the 1st;
//   end of year = Dec 31; a date without a year rolls to next year when already past;
//   a bare year is only a date with "by/until 2027" or "2027'ye kadar" (Dec 31).
// - Times: a bare hour 1-7 without am/pm or part of day means afternoon ("saat 3" = 15:00);
//   tonight / bu akşam = 20:00, midnight = 23:59. A time alone means today if still ahead,
//   otherwise tomorrow; next to a recurrence it anchors to the recurrence's first occurrence.
// - Recurrence first occurrence includes today ("her pazartesi" on a Monday starts today).

struct TaskInputSuggestion: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case due(date: Date, hasTime: Bool)
        case recurrence(TaskRecurrence)
        case priority(TaskPriority)
    }

    /// Stable for the same kind and range, so the UI does not flicker while typing.
    let id: String
    let kind: Kind
    /// Span of the matched phrase (including connector words) in the parsed input.
    let range: Range<String.Index>
    let matchedText: String
    /// Short chip label: "Today", "Tomorrow 15:00", "Mon 23 Nov", "Every Monday", "High priority".
    let label: String
    /// For `.recurrence`: first occurrence (start of day) on or after `now`; used by `apply` as the
    /// due date when no due suggestion is accepted.
    var firstOccurrence: Date? = nil
}

struct TaskInputParseResult: Equatable, Sendable {
    var title: String
    var dueDate: Date?
    var dueHasTime: Bool
    var recurrence: TaskRecurrence?
    var priority: TaskPriority
}

struct TaskInputParser: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Live suggestions for `text`; at most one per kind, ordered due, recurrence, priority.
    func suggestions(for text: String, now: Date) -> [TaskInputSuggestion] {
        guard !text.isEmpty else { return [] }
        let tokens = Tokenizer.tokenize(text)
        guard !tokens.isEmpty else { return [] }
        let engine = Engine(tokens: tokens, ctx: DateContext(calendar: calendar, now: now))
        return engine.suggestions(in: text)
    }

    /// Builds the structured result from the accepted suggestions; matched phrases are removed from the title.
    func apply(_ accepted: [TaskInputSuggestion], to text: String) -> TaskInputParseResult {
        var result = TaskInputParseResult(
            title: Self.tidy(text),
            dueDate: nil,
            dueHasTime: false,
            recurrence: nil,
            priority: .none
        )
        var removals: [Range<String.Index>] = []
        var recurrenceStart: Date?

        for suggestion in accepted {
            switch suggestion.kind {
            case let .due(date, hasTime):
                result.dueDate = date
                result.dueHasTime = hasTime
            case let .recurrence(recurrence):
                result.recurrence = recurrence
                recurrenceStart = suggestion.firstOccurrence
            case let .priority(priority):
                result.priority = max(result.priority, priority)
            }
            let range = suggestion.range
            if range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex,
               text[range] == suggestion.matchedText {
                removals.append(range)
            }
        }

        if result.dueDate == nil, let recurrenceStart {
            result.dueDate = recurrenceStart
            result.dueHasTime = false
        }

        let remaining = Self.tidy(Self.removing(removals, from: text))
        if remaining.contains(where: { $0.isLetter || $0.isNumber }) {
            result.title = remaining
        }
        return result
    }

    /// Compact label: "Today", "Tomorrow 09:00", "Fri 20 Nov" (2-7 days ahead), "23 Nov", "23 Nov 2027".
    func dueLabel(for date: Date, hasTime: Bool, now: Date) -> String {
        Labels.due(date, hasTime: hasTime, now: now, calendar: calendar)
    }

    // MARK: Title tidying

    private static func removing(_ ranges: [Range<String.Index>], from text: String) -> String {
        guard !ranges.isEmpty else { return text }
        var output = ""
        var cursor = text.startIndex
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if range.lowerBound > cursor {
                output += text[cursor..<range.lowerBound]
                output += " "
            }
            cursor = max(cursor, range.upperBound)
        }
        output += text[cursor...]
        return output
    }

    private static func tidy(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: " +([,.;:!?)])", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\( *\\)", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "([,;:])(?: *[,;:])+", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—"))
        return value.trimmingCharacters(in: edges)
    }
}

// MARK: - Tokens

private struct Token {
    /// Range of the token core (surrounding punctuation stripped) in the original text.
    let range: Range<String.Index>
    /// Normalized form: Turkish lowercase, diacritics folded, apostrophes removed.
    let word: String
    let hadApostrophe: Bool
    /// Standalone "!", "!!", "!!!".
    let isBangs: Bool
    var isBlocked: Bool

    var startsWithDigit: Bool { word.utf8.first.map(isASCIIDigit) ?? false }
    var isAllDigits: Bool { !word.isEmpty && word.utf8.allSatisfy(isASCIIDigit) }
}

private func isASCIIDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }

private enum Tokenizer {
    static let turkish = Locale(identifier: "tr")
    static let leadingTrim: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "«", "<", "*", "_", "¿", "¡"]
    static let trailingTrim: Set<Character> = [
        ",", ";", ":", ".", "!", "?", ")", "]", "}", "\"", "'", "”", "’", "»", ">", "…", "*", "_"
    ]
    static let protectedCharacters: Set<Character> = ["$", "€", "£", "₺", "%", "+", "=", "\\", "|"]
    static let currencyWords: Set<String> = [
        "tl", "try", "lira", "usd", "eur", "euro", "dolar", "dollar", "dollars", "gbp", "sterlin",
        "$", "€", "₺", "£", "%", "bin", "milyon", "k"
    ]
    static let versionWords: Set<String> = ["version", "versiyon", "surum", "release", "build", "v", "ios", "macos", "sdk"]

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            if let token = makeToken(text, chunk: index..<end) { tokens.append(token) }
            index = end
        }
        blockNumericContexts(&tokens)
        return tokens
    }

    private static func makeToken(_ text: String, chunk range: Range<String.Index>) -> Token? {
        let chunk = text[range]
        if chunk.allSatisfy({ $0 == "!" }) {
            return Token(range: range, word: String(chunk), hadApostrophe: false, isBangs: true, isBlocked: false)
        }
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, leadingTrim.contains(text[lower]) { lower = text.index(after: lower) }
        while upper > lower {
            let previous = text.index(before: upper)
            guard trailingTrim.contains(text[previous]) else { break }
            upper = previous
        }
        guard lower < upper else { return nil }
        let (word, apostrophe) = normalize(text[lower..<upper])
        return Token(
            range: lower..<upper,
            word: word,
            hadApostrophe: apostrophe,
            isBangs: false,
            isBlocked: isProtected(chunk: chunk, word: word)
        )
    }

    private static func isProtected(chunk: Substring, word: String) -> Bool {
        if chunk.contains("://") || chunk.contains("@") || chunk.hasPrefix("#") || word.hasPrefix("www.") {
            return true
        }
        if chunk.contains(where: { protectedCharacters.contains($0) }) { return true }
        let bytes = Array(word.utf8.prefix(2))
        return bytes.count == 2 && bytes[0] == UInt8(ascii: "v") && isASCIIDigit(bytes[1])
    }

    /// Blocks phone-number-like runs, money amounts and version numbers.
    private static func blockNumericContexts(_ tokens: inout [Token]) {
        var index = 0
        while index < tokens.count {
            var end = index
            while end < tokens.count, tokens[end].isAllDigits { end += 1 }
            if end - index >= 3 {
                for k in index..<end { tokens[k].isBlocked = true }
            }
            index = max(end, index + 1)
        }
        for k in tokens.indices where tokens[k].startsWithDigit {
            if tokens[k].isAllDigits, tokens[k].word.utf8.count >= 5 { tokens[k].isBlocked = true }
            if k + 1 < tokens.count, currencyWords.contains(tokens[k + 1].word) { tokens[k].isBlocked = true }
            if k > 0, versionWords.contains(tokens[k - 1].word) || currencyWords.contains(tokens[k - 1].word) {
                tokens[k].isBlocked = true
            }
        }
    }

    static func normalize(_ text: Substring) -> (String, Bool) {
        let lower = text.lowercased(with: turkish)
        var scalars = String.UnicodeScalarView()
        var apostrophe = false
        for scalar in lower.unicodeScalars {
            switch scalar {
            case "ı", "î", "ï": scalars.append("i")
            case "ş": scalars.append("s")
            case "ğ": scalars.append("g")
            case "ç": scalars.append("c")
            case "ö": scalars.append("o")
            case "ü", "û": scalars.append("u")
            case "â", "ä": scalars.append("a")
            case "'", "’", "‘", "`", "´", "ʼ": apostrophe = true
            case "\u{0307}": continue
            default: scalars.append(scalar)
            }
        }
        return (String(scalars), apostrophe)
    }
}

// MARK: - Lexicon

private enum DayPeriod {
    case morning, noon, afternoon, evening, night

    var defaultTime: HourMinute {
        switch self {
        case .morning: HourMinute(hour: 9, minute: 0)
        case .noon: HourMinute(hour: 12, minute: 0)
        case .afternoon: HourMinute(hour: 15, minute: 0)
        case .evening: HourMinute(hour: 20, minute: 0)
        case .night: HourMinute(hour: 22, minute: 0)
        }
    }
}

private enum RelativeDay {
    case today, tomorrow, dayAfterTomorrow, todayAt(DayPeriod)
    case nextWeek, weekend, nextWeekend, endOfWeek
    case endOfMonth, nextMonth, endOfYear, nextYear
}

private enum Unit {
    case minute, hour, day, week, month, year

    var frequency: TaskRecurrence.Frequency? {
        switch self {
        case .day: .daily
        case .week: .weekly
        case .month: .monthly
        case .year: .yearly
        case .minute, .hour: nil
        }
    }
}

private enum Lexicon {
    /// Turkish case/possessive suffixes after apostrophe removal and diacritic folding.
    static let trSuffixes: Set<String> = [
        "", "a", "e", "ya", "ye", "yi", "yu", "i", "u", "da", "de", "ta", "te", "dan", "den", "tan", "ten",
        "nin", "nun", "in", "un", "na", "ne", "nda", "nde", "ndan", "nden", "ki", "daki", "deki", "taki", "teki"
    ]
    static let trPluralSuffixes: Set<String> = ["leri", "lari", "lerde", "larda", "ler", "lar"]
    static let timeLocativeSuffixes: Set<String> = ["te", "ta", "de", "da", "ten", "tan", "den", "dan"]
    static let timeDativeSuffixes: Set<String> = ["e", "a", "ye", "ya"]

    /// Ordered so that longer stems sharing a prefix come first ("pazartesi" before "pazar").
    static let turkishWeekdayStems: [(String, Int)] = [
        ("pazartesi", 2), ("cumartesi", 7), ("carsamba", 4), ("persembe", 5), ("pazar", 1), ("sali", 3), ("cuma", 6)
    ]
    static let englishWeekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]
    /// Only accepted after a modifier or connector ("on Fri", "next Mon").
    static let englishWeekdayAbbreviations: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7
    ]

    static let monthNames: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9,
        "oct": 10, "nov": 11, "dec": 12,
        "oca": 1, "sub": 2, "nis": 4, "haz": 6, "tem": 7, "agu": 8, "eyl": 9, "eki": 10, "kas": 11, "ara": 12
    ]
    /// Turkish month stems that accept case suffixes ("kasıma", "ocağa", "aralıkta").
    static let turkishMonthStems: [(String, Int)] = [
        ("ocak", 1), ("ocag", 1), ("subat", 2), ("mart", 3), ("nisan", 4), ("mayis", 5), ("haziran", 6),
        ("temmuz", 7), ("agustos", 8), ("eylul", 9), ("ekim", 10), ("kasim", 11), ("aralik", 12), ("aralig", 12)
    ]

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9
    ]
    static let turkishDigits: [String: Int] = [
        "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9
    ]

    static let units: [String: Unit] = [
        "minute": .minute, "minutes": .minute, "min": .minute, "mins": .minute, "dakika": .minute, "dk": .minute,
        "hour": .hour, "hours": .hour, "hr": .hour, "hrs": .hour, "saat": .hour,
        "day": .day, "days": .day, "gun": .day,
        "week": .week, "weeks": .week, "hafta": .week,
        "month": .month, "months": .month, "ay": .month,
        "year": .year, "years": .year, "yil": .year, "sene": .year
    ]
    /// "2 haftada bir" style units.
    static let locativeUnits: [String: Unit] = [
        "gunde": .day, "haftada": .week, "ayda": .month, "yilda": .year, "senede": .year
    ]

    static let dayConnectors: Set<String> = ["until", "till", "til", "untill", "by", "on", "for", "before", "due"]
    static let timeConnectors: Set<String> = ["at", "by", "until", "till", "before", "around", "saat"]

    static let relativePhrases: [([String], RelativeDay)] = [
        (["today"], .today), (["bugun"], .today), (["bugune"], .today),
        (["tomorrow"], .tomorrow), (["tmrw"], .tomorrow), (["tmr"], .tomorrow),
        (["yarin"], .tomorrow), (["yarina"], .tomorrow),
        (["day", "after", "tomorrow"], .dayAfterTomorrow), (["overmorrow"], .dayAfterTomorrow),
        (["obur", "gun"], .dayAfterTomorrow), (["obur", "gune"], .dayAfterTomorrow),
        (["oburgun"], .dayAfterTomorrow), (["oburgune"], .dayAfterTomorrow),
        (["yarindan", "sonra"], .dayAfterTomorrow),
        (["tonight"], .todayAt(.evening)), (["this", "evening"], .todayAt(.evening)),
        (["this", "morning"], .todayAt(.morning)), (["this", "afternoon"], .todayAt(.afternoon)),
        (["bu", "aksam"], .todayAt(.evening)), (["bu", "sabah"], .todayAt(.morning)),
        (["bu", "gece"], .todayAt(.night)), (["bu", "ogleden", "sonra"], .todayAt(.afternoon)),
        (["bu", "ogle"], .todayAt(.noon)), (["bu", "oglen"], .todayAt(.noon)),
        (["next", "week"], .nextWeek), (["haftaya"], .nextWeek),
        (["gelecek", "hafta"], .nextWeek), (["gelecek", "haftaya"], .nextWeek),
        (["onumuzdeki", "hafta"], .nextWeek), (["onumuzdeki", "haftaya"], .nextWeek),
        (["weekend"], .weekend), (["this", "weekend"], .weekend),
        (["hafta", "sonu"], .weekend), (["hafta", "sonunda"], .weekend), (["hafta", "sonuna"], .weekend),
        (["haftasonu"], .weekend), (["haftasonunda"], .weekend), (["haftasonuna"], .weekend),
        (["bu", "hafta", "sonu"], .weekend), (["bu", "hafta", "sonunda"], .weekend),
        (["next", "weekend"], .nextWeekend), (["gelecek", "hafta", "sonu"], .nextWeekend),
        (["haftaya", "hafta", "sonu"], .nextWeekend),
        (["end", "of", "week"], .endOfWeek), (["end", "of", "the", "week"], .endOfWeek), (["eow"], .endOfWeek),
        (["this", "week"], .endOfWeek), (["bu", "hafta"], .endOfWeek),
        (["hafta", "sonuna", "kadar"], .endOfWeek), (["haftasonuna", "kadar"], .endOfWeek),
        (["bu", "hafta", "sonuna", "kadar"], .endOfWeek), (["bu", "hafta", "icinde"], .endOfWeek),
        (["end", "of", "month"], .endOfMonth), (["end", "of", "the", "month"], .endOfMonth), (["eom"], .endOfMonth),
        (["this", "month"], .endOfMonth), (["bu", "ay"], .endOfMonth), (["bu", "ay", "icinde"], .endOfMonth),
        (["ay", "sonu"], .endOfMonth), (["ay", "sonuna"], .endOfMonth), (["ay", "sonunda"], .endOfMonth),
        (["aysonu"], .endOfMonth), (["aysonuna"], .endOfMonth),
        (["bu", "ay", "sonu"], .endOfMonth), (["bu", "ay", "sonuna"], .endOfMonth), (["bu", "ay", "sonunda"], .endOfMonth),
        (["next", "month"], .nextMonth), (["gelecek", "ay"], .nextMonth), (["gelecek", "aya"], .nextMonth),
        (["onumuzdeki", "ay"], .nextMonth), (["onumuzdeki", "aya"], .nextMonth),
        (["end", "of", "year"], .endOfYear), (["end", "of", "the", "year"], .endOfYear), (["eoy"], .endOfYear),
        (["this", "year"], .endOfYear), (["bu", "yil"], .endOfYear),
        (["yil", "sonu"], .endOfYear), (["yil", "sonuna"], .endOfYear), (["yil", "sonunda"], .endOfYear),
        (["yilsonu"], .endOfYear), (["yilsonuna"], .endOfYear),
        (["sene", "sonu"], .endOfYear), (["sene", "sonuna"], .endOfYear), (["sene", "sonunda"], .endOfYear),
        (["next", "year"], .nextYear), (["seneye"], .nextYear), (["gelecek", "yil"], .nextYear),
        (["gelecek", "sene"], .nextYear), (["onumuzdeki", "yil"], .nextYear), (["onumuzdeki", "sene"], .nextYear)
    ]
    static let relativeIndex: [String: [([String], RelativeDay)]] =
        Dictionary(grouping: relativePhrases, by: { $0.0[0] })

    static let recurrenceWords: [String: TaskRecurrence] = [
        "daily": .daily, "everyday": .daily, "hergun": .daily,
        "weekly": .weekly, "biweekly": TaskRecurrence(frequency: .weekly, interval: 2),
        "fortnightly": TaskRecurrence(frequency: .weekly, interval: 2),
        "monthly": .monthly, "yearly": .yearly, "annually": .yearly,
        "weekdays": .weekdaysOnly, "haftaicleri": .weekdaysOnly
    ]

    static let priorityWords: [String: TaskPriority] = [
        "urgent": .high, "asap": .high, "acil": .high, "acilen": .high,
        "important": .medium, "onemli": .medium,
        "p1": .high, "p2": .medium, "p3": .low,
        "high-priority": .high, "medium-priority": .medium, "low-priority": .low
    ]
    static let priorityLevels: [String: TaskPriority] = [
        "high": .high, "yuksek": .high, "medium": .medium, "orta": .medium, "low": .low, "dusuk": .low
    ]
    static let priorityNouns: Set<String> = ["priority", "prio", "oncelik", "oncelikli", "oncelikle"]
}

// MARK: - Dates

private struct HourMinute: Equatable {
    var hour: Int
    var minute: Int
}

private struct DateContext {
    let calendar: Calendar
    let now: Date
    let today: Date
    let weekday: Int
    let year: Int

    init(calendar: Calendar, now: Date) {
        self.calendar = calendar
        self.now = now
        today = calendar.startOfDay(for: now)
        weekday = calendar.component(.weekday, from: now)
        year = calendar.component(.year, from: now)
    }

    /// Monday = 0 ... Sunday = 6.
    func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    var weekStart: Date { day(-mondayIndex(weekday)) }

    func day(_ offset: Int, from base: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base ?? today) ?? today
    }

    func adding(_ component: Calendar.Component, _ value: Int, to base: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: base) ?? base
    }

    func set(_ time: HourMinute, on day: Date) -> Date {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == month && parts.day == day ? date : nil
    }

    func lastDayOfMonth(containing date: Date) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 28
        return self.date(parts.year ?? year, parts.month ?? 1, days) ?? date
    }
}

private enum Labels {
    static func due(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let dayDiff = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        let parts = calendar.dateComponents([.year, .hour, .minute], from: date)
        var text: String
        switch dayDiff {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case 2...7: text = format(date, "EEE d MMM", calendar: calendar)
        default:
            let sameYear = parts.year == calendar.component(.year, from: now)
            text = format(date, sameYear ? "d MMM" : "d MMM yyyy", calendar: calendar)
        }
        if hasTime { text += String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0) }
        return text
    }

    /// Day and month names follow the interface language ("Mon 23 Nov").
    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

// MARK: - Matching

private struct Span<Value> {
    let value: Value
    let end: Int
}

private struct DayPart {
    /// Start of the day.
    var date: Date
    /// Fixed instant ("in 2 hours"); no separate time may be attached.
    var exact: Date?
    /// "tonight", "bu sabah": default time and hint for bare hours.
    var period: DayPeriod?
    /// Bare weekday equal to today: today wins if a still-future time is attached.
    var allowsTodayWithLaterTime = false

    init(_ date: Date, exact: Date? = nil, period: DayPeriod? = nil, allowsTodayWithLaterTime: Bool = false) {
        self.date = date
        self.exact = exact
        self.period = period
        self.allowsTodayWithLaterTime = allowsTodayWithLaterTime
    }
}

private struct TimePart {
    var hour: Int
    var minute: Int
    var hasMeridiem = false
    var isZeroPadded = false
    var period: DayPeriod?
    /// Fixed words ("noon", "midnight") are never adjusted.
    var isFixed = false
    /// Part of day only ("akşam"); valid only next to a day.
    var isWeak = false
}

private struct DueCandidate {
    var day: DayPart?
    var time: TimePart?
}

private enum Found {
    case due(DueCandidate)
    case recurrence(TaskRecurrence)
    case priority(TaskPriority)
}

private struct Match {
    let start: Int
    let end: Int
    let found: Found
}

private struct WeekdayHit {
    let weekday: Int
    let isPlural: Bool
}

private enum WeekdayMode { case bare, this, coming, next }

private struct Engine {
    let tokens: [Token]
    let ctx: DateContext

    // MARK: Token access

    func token(_ i: Int) -> Token? {
        guard i >= 0, i < tokens.count, !tokens[i].isBlocked else { return nil }
        return tokens[i]
    }

    func word(_ i: Int) -> String? { token(i)?.word }

    func matches(_ i: Int, _ options: Set<String>) -> Bool {
        guard let word = word(i) else { return false }
        return options.contains(word)
    }

    // MARK: Output

    func suggestions(in text: String) -> [TaskInputSuggestion] {
        var due: (Match, DueCandidate)?
        var recurrence: (Match, TaskRecurrence)?
        var priority: (Match, TaskPriority)?
        for match in scan() {
            switch match.found {
            case let .due(candidate):
                if due == nil || (due?.1.day == nil && candidate.day != nil) { due = (match, candidate) }
            case let .recurrence(value):
                if recurrence == nil { recurrence = (match, value) }
            case let .priority(value):
                if priority == nil { priority = (match, value) }
            }
        }

        var output: [TaskInputSuggestion] = []
        if let due {
            let (match, candidate) = due
            let (date, hasTime) = resolveDue(candidate, recurrence: recurrence?.1)
            let label = Labels.due(date, hasTime: hasTime, now: ctx.now, calendar: ctx.calendar)
            output.append(suggestion("due", .due(date: date, hasTime: hasTime), match, text, label))
        }
        if let recurrence {
            let (match, value) = recurrence
            var item = suggestion("recurrence", .recurrence(value), match, text, value.displayText)
            item.firstOccurrence = value.firstOccurrence(onOrAfter: ctx.today, calendar: ctx.calendar)
            output.append(item)
        }
        if let priority {
            let (match, value) = priority
            output.append(suggestion("priority", .priority(value), match, text, value.displayText))
        }
        return output
    }

    private func suggestion(
        _ tag: String,
        _ kind: TaskInputSuggestion.Kind,
        _ match: Match,
        _ text: String,
        _ label: String
    ) -> TaskInputSuggestion {
        let range = tokens[match.start].range.lowerBound..<tokens[match.end - 1].range.upperBound
        let lower = text.utf16.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.utf16.distance(from: text.startIndex, to: range.upperBound)
        return TaskInputSuggestion(
            id: "\(tag)-\(lower)-\(upper)",
            kind: kind,
            range: range,
            matchedText: String(text[range]),
            label: label
        )
    }

    // MARK: Scan

    func scan() -> [Match] {
        var result: [Match] = []
        var i = 0
        while i < tokens.count {
            guard !tokens[i].isBlocked else {
                i += 1
                continue
            }
            var best: Match?
            for candidate in [recurrenceMatch(i), dueMatch(i), priorityMatch(i)] {
                if let candidate, candidate.end > (best?.end ?? i) { best = candidate }
            }
            if let best {
                result.append(best)
                i = best.end
            } else {
                i += 1
            }
        }
        return result
    }

    // MARK: Due

    func dueMatch(_ i: Int) -> Match? {
        var best: (DueCandidate, Int)?

        // Day first, optionally after connectors, optionally followed by a time.
        var j = i
        var connectors = 0
        while j < tokens.count {
            if let day = parseDay(j, afterConnector: connectors > 0) {
                var candidate = DueCandidate(day: day.value)
                var end = day.end
                if day.value.exact == nil, let time = parseTime(end, periodContext: day.value.period != nil) {
                    candidate.time = time.value
                    end = time.end
                }
                best = (candidate, end)
                break
            }
            let length = connectorLength(j)
            guard connectors < 2, length > 0 else { break }
            j += length
            connectors += 1
        }

        // Time first, optionally followed by a day.
        if let time = parseTime(i, periodContext: false) {
            var candidate = DueCandidate(time: time.value)
            var end = time.end
            if let day = parseDay(end, afterConnector: false), day.value.exact == nil {
                candidate.day = day.value
                end = day.end
            }
            let valid = candidate.day != nil || !time.value.isWeak
            if valid, end > (best?.1 ?? i) { best = (candidate, end) }
        }

        guard let best else { return nil }
        let (candidate, end) = best
        return Match(start: i, end: trailingConnectors(end), found: .due(candidate))
    }

    private func connectorLength(_ i: Int) -> Int {
        if matches(i, Lexicon.dayConnectors) { return 1 }
        if word(i) == "en", word(i + 1) == "gec" { return 2 }
        return 0
    }

    private func trailingConnectors(_ end: Int) -> Int {
        var e = end
        if matches(e, ["gunu", "gunune", "gununde", "gunun"]) { e += 1 }
        if word(e) == "kadar" {
            e += 1
        } else if word(e) == "at", word(e + 1) == "the", word(e + 2) == "latest" {
            e += 3
        }
        return e
    }

    func resolveDue(_ candidate: DueCandidate, recurrence: TaskRecurrence?) -> (Date, Bool) {
        if let day = candidate.day {
            if let exact = day.exact { return (exact, true) }
            if let time = candidate.time {
                let clock = resolveClock(time, hint: day.period)
                if day.allowsTodayWithLaterTime {
                    let today = ctx.set(clock, on: ctx.today)
                    if today > ctx.now { return (today, true) }
                }
                return (ctx.set(clock, on: day.date), true)
            }
            if let period = day.period { return (ctx.set(period.defaultTime, on: day.date), true) }
            return (day.date, false)
        }
        guard let time = candidate.time else { return (ctx.today, false) }
        let clock = resolveClock(time, hint: nil)
        if let recurrence {
            var first = recurrence.firstOccurrence(onOrAfter: ctx.today, calendar: ctx.calendar)
            if ctx.set(clock, on: first) <= ctx.now {
                first = recurrence.firstOccurrence(onOrAfter: ctx.day(1), calendar: ctx.calendar)
            }
            return (ctx.set(clock, on: first), true)
        }
        let today = ctx.set(clock, on: ctx.today)
        return (today > ctx.now ? today : ctx.set(clock, on: ctx.day(1)), true)
    }

    private func resolveClock(_ time: TimePart, hint: DayPeriod?) -> HourMinute {
        let period = time.period ?? hint
        if time.isWeak { return (period ?? .morning).defaultTime }
        var hour = time.hour
        if !time.hasMeridiem, !time.isFixed {
            if let period {
                switch period {
                case .morning:
                    break
                case .noon, .afternoon, .evening:
                    if (1...11).contains(hour) { hour += 12 }
                case .night:
                    if (5...11).contains(hour) { hour += 12 }
                    if hour == 12 { return HourMinute(hour: 23, minute: 59) }
                }
            } else if !time.isZeroPadded, (1...7).contains(hour) {
                hour += 12
            }
        }
        return HourMinute(hour: hour, minute: time.minute)
    }

    // MARK: Day phrases

    func parseDay(_ j: Int, afterConnector: Bool) -> Span<DayPart>? {
        guard word(j) != nil else { return nil }
        var best: Span<DayPart>?
        let candidates = [
            relativePhrase(j), relativeOffset(j), weekdayPhrase(j, afterConnector: afterConnector),
            absoluteDate(j), numericDate(j), yearOnly(j, afterConnector: afterConnector), ordinalDay(j)
        ]
        for case let candidate? in candidates where candidate.end > (best?.end ?? j) {
            best = candidate
        }
        return best
    }

    private func relativePhrase(_ j: Int) -> Span<DayPart>? {
        let start = word(j) == "the" ? j + 1 : j
        guard let first = word(start), let phrases = Lexicon.relativeIndex[first] else { return nil }
        var best: (RelativeDay, Int)?
        for (words, kind) in phrases where start + words.count > (best?.1 ?? start) {
            if words.indices.allSatisfy({ word(start + $0) == words[$0] }) {
                best = (kind, start + words.count)
            }
        }
        guard let best else { return nil }
        let (kind, end) = best
        return Span(value: relativeDay(kind), end: end)
    }

    private func relativeDay(_ kind: RelativeDay) -> DayPart {
        let mondayIndex = ctx.mondayIndex(ctx.weekday)
        switch kind {
        case .today: return DayPart(ctx.today)
        case .tomorrow: return DayPart(ctx.day(1))
        case .dayAfterTomorrow: return DayPart(ctx.day(2))
        case let .todayAt(period): return DayPart(ctx.today, period: period)
        case .nextWeek: return DayPart(ctx.day(7, from: ctx.weekStart))
        case .weekend: return DayPart(mondayIndex >= 5 ? ctx.today : ctx.day(5, from: ctx.weekStart))
        case .nextWeekend: return DayPart(ctx.day(12, from: ctx.weekStart))
        case .endOfWeek: return DayPart(ctx.day(mondayIndex <= 4 ? 4 : 11, from: ctx.weekStart))
        case .endOfMonth: return DayPart(ctx.lastDayOfMonth(containing: ctx.today))
        case .nextMonth:
            let month = ctx.calendar.component(.month, from: ctx.today)
            let date = month == 12 ? ctx.date(ctx.year + 1, 1, 1) : ctx.date(ctx.year, month + 1, 1)
            return DayPart(date ?? ctx.today)
        case .endOfYear: return DayPart(ctx.date(ctx.year, 12, 31) ?? ctx.today)
        case .nextYear: return DayPart(ctx.date(ctx.year + 1, 1, 1) ?? ctx.today)
        }
    }

    /// "in 3 days", "in a week", "2 weeks from now", "3 gün sonra", "iki hafta içinde", "2 saat sonra".
    private func relativeOffset(_ j: Int) -> Span<DayPart>? {
        var k = j
        let english = matches(k, ["in", "within"])
        if english { k += 1 }
        guard let count = parseCount(k), let unitWord = word(count.end), let unit = Lexicon.units[unitWord] else {
            return nil
        }
        var end = count.end + 1
        if word(end) == "from", word(end + 1) == "now" {
            end += 2
        } else if !english {
            guard matches(end, ["sonra", "icinde", "icerisinde", "sonraya", "later"]) else { return nil }
            end += 1
        }
        let n = count.value
        let day: DayPart
        switch unit {
        case .minute, .hour:
            let seconds = Double(n) * (unit == .hour ? 3600 : 60)
            let raw = ctx.now.addingTimeInterval(seconds).timeIntervalSinceReferenceDate
            let exact = Date(timeIntervalSinceReferenceDate: (raw / 60).rounded(.down) * 60)
            day = DayPart(ctx.calendar.startOfDay(for: exact), exact: exact)
        case .day: day = DayPart(ctx.day(n))
        case .week: day = DayPart(ctx.day(7 * n))
        case .month: day = DayPart(ctx.adding(.month, n, to: ctx.today))
        case .year: day = DayPart(ctx.adding(.year, n, to: ctx.today))
        }
        return Span(value: day, end: end)
    }

    private func parseCount(_ k: Int) -> Span<Int>? {
        guard let token = token(k) else { return nil }
        let word = token.word
        if token.isAllDigits {
            guard word.utf8.count <= 3, let value = Int(word), value > 0 else { return nil }
            return Span(value: value, end: k + 1)
        }
        if word == "on" {
            if let next = self.word(k + 1), let digit = Lexicon.turkishDigits[next] {
                return Span(value: 10 + digit, end: k + 2)
            }
            return Span(value: 10, end: k + 1)
        }
        guard let value = Lexicon.numberWords[word] else { return nil }
        return Span(value: value, end: k + 1)
    }

    /// "Monday", "next Monday", "this Friday", "bu cuma", "haftaya salı", "pazartesiye", "monday next week".
    private func weekdayPhrase(_ j: Int, afterConnector: Bool) -> Span<DayPart>? {
        var k = j
        var mode = WeekdayMode.bare
        switch word(j) {
        case "next":
            mode = .next
            k += word(j + 1) == "week" ? 2 : 1
        case "this":
            mode = .this
            k += word(j + 1) == "coming" ? 2 : 1
        case "coming":
            mode = .coming
            k += 1
        case "haftaya":
            mode = .next
            k += 1
        case "gelecek", "onumuzdeki":
            if matches(j + 1, ["hafta", "haftaya", "haftanin"]) {
                mode = .next
                k += 2
            } else {
                mode = .coming
                k += 1
            }
        case "bu":
            mode = .this
            k += 1
        default:
            break
        }
        guard let hit = weekdayWord(k, lenient: k > j || afterConnector), !hit.value.isPlural else { return nil }
        var end = hit.end
        if mode == .bare, word(end) == "next", word(end + 1) == "week" {
            mode = .next
            end += 2
        }
        return Span(value: weekdayDate(hit.value.weekday, mode: mode), end: end)
    }

    private func weekdayDate(_ weekday: Int, mode: WeekdayMode) -> DayPart {
        let diff = (weekday - ctx.weekday + 7) % 7
        switch mode {
        case .bare:
            return diff == 0 ? DayPart(ctx.day(7), allowsTodayWithLaterTime: true) : DayPart(ctx.day(diff))
        case .coming:
            return DayPart(ctx.day(diff == 0 ? 7 : diff))
        case .this:
            return DayPart(ctx.day(diff))
        case .next:
            return DayPart(ctx.day(7 + ctx.mondayIndex(weekday) - ctx.mondayIndex(ctx.weekday)))
        }
    }

    func weekdayWord(_ k: Int, lenient: Bool) -> Span<WeekdayHit>? {
        guard let token = token(k) else { return nil }
        let word = token.word
        if let weekday = Lexicon.englishWeekdays[word] {
            return Span(value: WeekdayHit(weekday: weekday, isPlural: false), end: k + 1)
        }
        if word.hasSuffix("s"), let weekday = Lexicon.englishWeekdays[String(word.dropLast())] {
            return Span(value: WeekdayHit(weekday: weekday, isPlural: !token.hadApostrophe), end: k + 1)
        }
        if lenient, let weekday = Lexicon.englishWeekdayAbbreviations[word] {
            return Span(value: WeekdayHit(weekday: weekday, isPlural: false), end: k + 1)
        }
        for (stem, weekday) in Lexicon.turkishWeekdayStems where word.hasPrefix(stem) {
            let rest = String(word.dropFirst(stem.count))
            if Lexicon.trPluralSuffixes.contains(rest) {
                return Span(value: WeekdayHit(weekday: weekday, isPlural: true), end: k + 1)
            }
            if Lexicon.trSuffixes.contains(rest) {
                // "pazar" also means "market": inflected forms need context ("pazara kadar", "bu pazara").
                if stem == "pazar", !rest.isEmpty, !lenient, self.word(k + 1) != "kadar" { return nil }
                return Span(value: WeekdayHit(weekday: weekday, isPlural: false), end: k + 1)
            }
        }
        return nil
    }

    /// "23 Kasım", "23 kas 2027", "23rd of November", "Nov 23", "November 23rd, 2027".
    private func absoluteDate(_ j: Int) -> Span<DayPart>? {
        if let day = dayNumber(j) {
            var k = j + 1
            if word(k) == "of" { k += 1 }
            if let month = monthWord(k) {
                let year = yearWord(month.end)
                if let date = resolveDate(year?.value, month.value, day) {
                    return Span(value: DayPart(date), end: year?.end ?? month.end)
                }
            }
        }
        if let month = monthWord(j), let day = dayNumber(month.end) {
            let year = yearWord(month.end + 1)
            if let date = resolveDate(year?.value, month.value, day) {
                return Span(value: DayPart(date), end: year?.end ?? month.end + 1)
            }
        }
        return nil
    }

    /// "23.11", "23/11", "23.11.2027", "11/23" (US order when unambiguous), "2027-11-23", "23.11'e".
    private func numericDate(_ k: Int) -> Span<DayPart>? {
        guard let token = token(k), token.startsWithDigit else { return nil }
        let bytes = Array(token.word.utf8)
        var groups: [Int] = []
        var lengths: [Int] = []
        var separators: [UInt8] = []
        var index = 0
        while index < bytes.count {
            var value = 0
            var length = 0
            while index < bytes.count, isASCIIDigit(bytes[index]) {
                value = value * 10 + Int(bytes[index] - 48)
                length += 1
                index += 1
            }
            guard length > 0, length <= 4 else { return nil }
            groups.append(value)
            lengths.append(length)
            guard index + 1 < bytes.count,
                  [UInt8(ascii: "."), UInt8(ascii: "/"), UInt8(ascii: "-")].contains(bytes[index]),
                  isASCIIDigit(bytes[index + 1]) else { break }
            separators.append(bytes[index])
            index += 1
        }
        let suffix = String(decoding: bytes[index...], as: UTF8.self)
        guard groups.count >= 2, groups.count <= 3, Lexicon.trSuffixes.contains(suffix),
              let separator = separators.first, separators.allSatisfy({ $0 == separator }) else { return nil }

        var year: Int?
        var month: Int
        var day: Int
        if separator == UInt8(ascii: "-") {
            guard groups.count == 3, lengths[0] == 4 else { return nil }
            (year, month, day) = (groups[0], groups[1], groups[2])
        } else {
            guard lengths[0] <= 2, lengths[1] <= 2 else { return nil }
            (day, month) = (groups[0], groups[1])
            if groups.count == 3 {
                guard lengths[2] == 2 || lengths[2] == 4 else { return nil }
                year = lengths[2] == 2 ? 2000 + groups[2] : groups[2]
            }
            if separator == UInt8(ascii: ".") {
                // "9.30" / "saat 10.10" are times; dotted dates need a two-digit month.
                guard lengths[1] == 2, !matches(k - 1, ["at", "saat"]) else { return nil }
            } else if month > 12, day <= 12 {
                swap(&day, &month)
            }
        }
        guard let date = resolveDate(year, month, day) else { return nil }
        return Span(value: DayPart(date), end: k + 1)
    }

    /// "by 2027", "until 2027", "2027'ye kadar", "2027 sonuna kadar" -> Dec 31. A bare year is not a date.
    private func yearOnly(_ j: Int, afterConnector: Bool) -> Span<DayPart>? {
        guard let token = token(j), token.startsWithDigit else { return nil }
        let bytes = Array(token.word.utf8)
        guard bytes.count >= 4, bytes.prefix(4).allSatisfy(isASCIIDigit),
              bytes.count == 4 || !isASCIIDigit(bytes[4]),
              let year = Int(String(decoding: bytes.prefix(4), as: UTF8.self)),
              (ctx.year...2199).contains(year),
              let date = ctx.date(year, 12, 31) else { return nil }
        let suffix = String(decoding: bytes.dropFirst(4), as: UTF8.self)
        if suffix.isEmpty {
            if matches(j + 1, ["sonu", "sonuna", "sonunda"]) { return Span(value: DayPart(date), end: j + 2) }
            if afterConnector { return Span(value: DayPart(date), end: j + 1) }
        } else if Lexicon.timeDativeSuffixes.contains(suffix), word(j + 1) == "kadar" {
            return Span(value: DayPart(date), end: j + 1)
        }
        return nil
    }

    /// "the 23rd" -> next 23rd of a month (today included).
    private func ordinalDay(_ j: Int) -> Span<DayPart>? {
        guard word(j) == "the", let token = token(j + 1),
              ["st", "nd", "rd", "th"].contains(where: { token.word.hasSuffix($0) }),
              let day = dayNumber(j + 1) else { return nil }
        let month = ctx.calendar.component(.month, from: ctx.today)
        for offset in 0..<4 {
            let total = month - 1 + offset
            if let date = ctx.date(ctx.year + total / 12, total % 12 + 1, day), date >= ctx.today {
                return Span(value: DayPart(date), end: j + 2)
            }
        }
        return nil
    }

    private func dayNumber(_ k: Int) -> Int? {
        guard let token = token(k), token.startsWithDigit else { return nil }
        var word = token.word
        for suffix in ["st", "nd", "rd", "th"] where word.hasSuffix(suffix) {
            word.removeLast(2)
            break
        }
        guard word.utf8.count <= 2, word.utf8.allSatisfy(isASCIIDigit), let value = Int(word),
              (1...31).contains(value) else { return nil }
        return value
    }

    private func monthWord(_ k: Int) -> Span<Int>? {
        guard let word = word(k) else { return nil }
        if let month = Lexicon.monthNames[word] { return Span(value: month, end: k + 1) }
        for (stem, month) in Lexicon.turkishMonthStems where word.hasPrefix(stem) {
            if Lexicon.trSuffixes.contains(String(word.dropFirst(stem.count))) {
                return Span(value: month, end: k + 1)
            }
        }
        return nil
    }

    private func yearWord(_ k: Int) -> Span<Int>? {
        guard let token = token(k), token.startsWithDigit else { return nil }
        let bytes = Array(token.word.utf8)
        guard bytes.count >= 4, bytes.prefix(4).allSatisfy(isASCIIDigit),
              bytes.count == 4 || !isASCIIDigit(bytes[4]),
              Lexicon.trSuffixes.contains(String(decoding: bytes.dropFirst(4), as: UTF8.self)),
              let year = Int(String(decoding: bytes.prefix(4), as: UTF8.self)),
              (2000...2199).contains(year) else { return nil }
        return Span(value: year, end: k + 1)
    }

    private func resolveDate(_ year: Int?, _ month: Int, _ day: Int) -> Date? {
        if let year {
            // Explicit past dates (often a half-typed year like "23.11.20") are not suggested.
            guard let date = ctx.date(year, month, day), date >= ctx.today else { return nil }
            return date
        }
        if let date = ctx.date(ctx.year, month, day), date >= ctx.today { return date }
        return ctx.date(ctx.year + 1, month, day)
    }

    // MARK: Times

    /// "15:00", "15.00", "3pm", "3 pm", "at 9", "saat 3te", "15'te", "sabah 9", "akşam 7", "öğlen", "noon".
    func parseTime(_ k: Int, periodContext: Bool) -> Span<TimePart>? {
        var j = k
        var bareAllowed = periodContext
        if matches(j, Lexicon.timeConnectors) {
            bareAllowed = true
            j += 1
        }
        if let fixed = fixedTime(j) {
            return Span(value: TimePart(hour: fixed.value.hour, minute: fixed.value.minute, isFixed: true), end: fixed.end)
        }
        var period: DayPeriod?
        if let found = periodWord(j) {
            period = found.value
            j = found.end
        }
        if let clock = parseClock(j, bareAllowed: bareAllowed || period != nil) {
            var time = clock.value
            time.period = period
            return Span(value: time, end: clock.end)
        }
        guard let period else { return nil }
        let time = period.defaultTime
        return Span(
            value: TimePart(hour: time.hour, minute: time.minute, period: period, isFixed: period == .noon, isWeak: period != .noon),
            end: j
        )
    }

    private func fixedTime(_ k: Int) -> Span<HourMinute>? {
        switch word(k) {
        case "noon", "midday":
            return Span(value: HourMinute(hour: 12, minute: 0), end: k + 1)
        case "midnight":
            return Span(value: HourMinute(hour: 23, minute: 59), end: k + 1)
        case "gece" where matches(k + 1, ["yarisi", "yarisina", "yarisinda"]):
            return Span(value: HourMinute(hour: 23, minute: 59), end: k + 2)
        default:
            return nil
        }
    }

    private func periodWord(_ k: Int) -> Span<DayPeriod>? {
        switch word(k) {
        case "sabah", "sabahleyin", "morning": return Span(value: .morning, end: k + 1)
        case "ogle", "oglen", "ogleyin": return Span(value: .noon, end: k + 1)
        case "ogleden" where word(k + 1) == "sonra": return Span(value: .afternoon, end: k + 2)
        case "afternoon", "ikindi": return Span(value: .afternoon, end: k + 1)
        case "aksam", "aksamleyin", "aksamustu", "evening": return Span(value: .evening, end: k + 1)
        case "gece", "geceleyin", "night": return Span(value: .night, end: k + 1)
        default: return nil
        }
    }

    private func parseClock(_ k: Int, bareAllowed: Bool) -> Span<TimePart>? {
        guard let token = token(k), token.startsWithDigit else { return nil }
        let bytes = Array(token.word.utf8)
        var index = 0
        var hour = 0
        while index < bytes.count, isASCIIDigit(bytes[index]) {
            hour = hour * 10 + Int(bytes[index] - 48)
            index += 1
        }
        let hourDigits = index
        guard (1...2).contains(hourDigits) else { return nil }

        var minute = 0
        var hasMinutes = false
        var hasColon = false
        if index + 2 < bytes.count,
           bytes[index] == UInt8(ascii: ":") || bytes[index] == UInt8(ascii: "."),
           isASCIIDigit(bytes[index + 1]), isASCIIDigit(bytes[index + 2]),
           index + 3 == bytes.count || !isASCIIDigit(bytes[index + 3]) {
            hasColon = bytes[index] == UInt8(ascii: ":")
            minute = Int(bytes[index + 1] - 48) * 10 + Int(bytes[index + 2] - 48)
            hasMinutes = true
            index += 3
        }

        var rest = String(decoding: bytes[index...], as: UTF8.self)
        var meridiem: String?
        if rest == "am" || rest == "pm" {
            meridiem = rest
            rest = ""
        }
        var end = k + 1
        if meridiem == nil, rest.isEmpty, let next = word(end), ["am", "pm", "a.m", "p.m"].contains(next) {
            meridiem = next.hasPrefix("a") ? "am" : "pm"
            end += 1
        }
        let locative = Lexicon.timeLocativeSuffixes.contains(rest)
        let dative = Lexicon.timeDativeSuffixes.contains(rest)
        guard rest.isEmpty || locative || dative else { return nil }
        if dative, !(bareAllowed || hasMinutes || word(end) == "kadar") { return nil }
        let explicitForm = hasColon || hasMinutes || meridiem != nil || locative || dative
        guard explicitForm || bareAllowed else { return nil }

        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else {
            guard hour <= 23 else { return nil }
        }
        guard minute <= 59 else { return nil }
        let time = TimePart(
            hour: hour,
            minute: minute,
            hasMeridiem: meridiem != nil,
            isZeroPadded: hourDigits == 2 && bytes[0] == UInt8(ascii: "0")
        )
        return Span(value: time, end: end)
    }

    // MARK: Recurrence

    func recurrenceMatch(_ i: Int) -> Match? {
        guard let word = word(i) else { return nil }
        var best: Span<TaskRecurrence>?
        func consider(_ candidate: Span<TaskRecurrence>?) {
            if let candidate, candidate.end > (best?.end ?? i) { best = candidate }
        }
        if let value = Lexicon.recurrenceWords[word] { consider(Span(value: value, end: i + 1)) }
        if ["every", "each", "her"].contains(word) { consider(everyPhrase(i + 1)) }
        consider(turkishWeekdaysPhrase(i))
        consider(periodicPhrase(i))
        consider(pluralWeekdays(i))
        if word == "on" {
            if matches(i + 1, ["weekdays"]) { consider(Span(value: .weekdaysOnly, end: i + 2)) }
            consider(pluralWeekdays(i + 1))
        }
        guard let best else { return nil }
        return Match(start: i, end: best.end, found: .recurrence(best.value))
    }

    /// After "every"/"her": "day", "other week", "2 weeks", "iki haftada bir", "weekday", "hafta içi", "Monday and Thursday".
    private func everyPhrase(_ k: Int) -> Span<TaskRecurrence>? {
        if matches(k, ["weekday", "weekdays", "haftaici"]) { return Span(value: .weekdaysOnly, end: k + 1) }
        if word(k) == "hafta", matches(k + 1, ["ici", "icinde"]) { return Span(value: .weekdaysOnly, end: k + 2) }
        if matches(k, ["morning", "evening", "night", "sabah", "aksam", "gece"]) {
            return Span(value: .daily, end: k + 1)
        }

        var j = k
        var interval = 1
        if word(j) == "other" {
            interval = 2
            j += 1
        } else if let count = parseCount(j), unitAt(count.end) != nil {
            interval = count.value
            j = count.end
        }
        if let unit = unitAt(j), let frequency = unit.unit.frequency {
            var end = j + 1
            if unit.isLocative, word(end) == "bir" { end += 1 }
            var weekdays: [Int]?
            if frequency == .weekly {
                let listStart = word(end) == "on" ? end + 1 : end
                if let list = weekdayList(listStart) {
                    weekdays = list.value
                    end = list.end
                }
            }
            return Span(value: TaskRecurrence(frequency: frequency, interval: interval, weekdays: weekdays), end: end)
        }
        guard j == k, let list = weekdayList(k) else { return nil }
        return Span(value: .weekly(on: list.value), end: list.end)
    }

    private func unitAt(_ k: Int) -> (unit: Unit, isLocative: Bool)? {
        guard let word = word(k) else { return nil }
        if let unit = Lexicon.units[word] { return (unit, false) }
        if let unit = Lexicon.locativeUnits[word] { return (unit, true) }
        return nil
    }

    /// "hafta içi her gün", "haftaiçi her gün", "hafta içleri".
    private func turkishWeekdaysPhrase(_ i: Int) -> Span<TaskRecurrence>? {
        var k = i
        if word(k) == "hafta", word(k + 1) == "icleri" { return Span(value: .weekdaysOnly, end: k + 2) }
        if word(k) == "hafta", word(k + 1) == "ici" {
            k += 2
        } else if word(k) == "haftaici" {
            k += 1
        } else {
            return nil
        }
        guard word(k) == "her", word(k + 1) == "gun" else { return nil }
        return Span(value: .weekdaysOnly, end: k + 2)
    }

    /// "2 haftada bir", "iki haftada bir", "haftada bir", "ayda bir".
    private func periodicPhrase(_ i: Int) -> Span<TaskRecurrence>? {
        var k = i
        var interval = 1
        if let count = parseCount(i), let word = word(count.end), Lexicon.locativeUnits[word] != nil {
            interval = count.value
            k = count.end
        }
        guard let word = word(k), let unit = Lexicon.locativeUnits[word], let frequency = unit.frequency,
              self.word(k + 1) == "bir" else { return nil }
        return Span(value: TaskRecurrence(frequency: frequency, interval: interval), end: k + 2)
    }

    /// "pazartesileri", "cumaları", "Mondays" (not "Monday's").
    private func pluralWeekdays(_ i: Int) -> Span<TaskRecurrence>? {
        guard let hit = weekdayWord(i, lenient: false), hit.value.isPlural else { return nil }
        return Span(value: .weekly(on: [hit.value.weekday]), end: hit.end)
    }

    private func weekdayList(_ k: Int) -> Span<[Int]>? {
        guard let first = weekdayWord(k, lenient: true) else { return nil }
        var days = [first.value.weekday]
        var end = first.end
        while true {
            let next = matches(end, ["and", "ve", "&", "ile"]) ? end + 1 : end
            guard let hit = weekdayWord(next, lenient: true) else { break }
            days.append(hit.value.weekday)
            end = hit.end
        }
        if matches(end, ["gunu", "gunleri"]) { end += 1 }
        return Span(value: days, end: end)
    }

    // MARK: Priority

    func priorityMatch(_ i: Int) -> Match? {
        guard let token = token(i) else { return nil }
        if token.isBangs {
            let count = token.word.count
            let priority: TaskPriority = count >= 3 ? .high : (count == 2 ? .medium : .low)
            return Match(start: i, end: i + 1, found: .priority(priority))
        }
        if let priority = Lexicon.priorityWords[token.word] {
            return Match(start: i, end: i + 1, found: .priority(priority))
        }
        if let priority = Lexicon.priorityLevels[token.word], matches(i + 1, Lexicon.priorityNouns) {
            return Match(start: i, end: i + 2, found: .priority(priority))
        }
        return nil
    }
}
