import XCTest
@testable import MeetingNotch

/// Fixed clock: Monday 16 November 2026, 10:00 Europe/Istanbul.
final class TaskInputParserTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "tr_TR")
        return calendar
    }()

    private var parser: TaskInputParser { TaskInputParser(calendar: calendar) }
    private var monday: Date { date(2026, 11, 16, 10, 0) }
    private var wednesday: Date { date(2026, 11, 18, 10, 0) }
    private var sunday: Date { date(2026, 11, 22, 10, 0) }

    // MARK: Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func dueSuggestion(_ text: String, now: Date? = nil) -> TaskInputSuggestion? {
        parser.suggestions(for: text, now: now ?? monday).first {
            if case .due = $0.kind { return true }
            return false
        }
    }

    private func assertDue(
        _ text: String,
        _ expected: Date,
        hasTime: Bool = false,
        matched: String? = nil,
        label: String? = nil,
        now: Date? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let suggestion = dueSuggestion(text, now: now) else {
            return XCTFail("No due suggestion for \"\(text)\"", file: file, line: line)
        }
        guard case let .due(date, time) = suggestion.kind else { return }
        XCTAssertEqual(date, expected, "date for \"\(text)\"", file: file, line: line)
        XCTAssertEqual(time, hasTime, "hasTime for \"\(text)\"", file: file, line: line)
        if let matched {
            XCTAssertEqual(suggestion.matchedText, matched, "matched text for \"\(text)\"", file: file, line: line)
        }
        if let label {
            XCTAssertEqual(suggestion.label, label, "label for \"\(text)\"", file: file, line: line)
        }
    }

    private func assertNoDue(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(dueSuggestion(text), "unexpected due suggestion for \"\(text)\"", file: file, line: line)
    }

    private func recurrence(_ text: String, now: Date? = nil) -> TaskInputSuggestion? {
        parser.suggestions(for: text, now: now ?? monday).first {
            if case .recurrence = $0.kind { return true }
            return false
        }
    }

    private func recurrenceValue(_ text: String) -> TaskRecurrence? {
        guard case let .recurrence(value)? = recurrence(text)?.kind else { return nil }
        return value
    }

    private func priority(_ text: String) -> TaskPriority? {
        for suggestion in parser.suggestions(for: text, now: monday) {
            if case let .priority(value) = suggestion.kind { return value }
        }
        return nil
    }

    // MARK: Relative days

    func testRelativeDaysEnglish() {
        assertDue("Call mom today", date(2026, 11, 16), matched: "today", label: "Bugün")
        assertDue("Call mom tomorrow", date(2026, 11, 17), matched: "tomorrow", label: "Yarın")
        assertDue("Call mom the day after tomorrow", date(2026, 11, 18), matched: "the day after tomorrow")
        assertDue("Pack tonight", date(2026, 11, 16, 20, 0), hasTime: true, label: "Bugün 20:00")
        assertDue("Report in 3 days", date(2026, 11, 19), matched: "in 3 days", label: "Per 19 Kas")
        assertDue("Report in two weeks", date(2026, 11, 30), label: "30 Kas")
        assertDue("Report in a week", date(2026, 11, 23))
        assertDue("Plan next week", date(2026, 11, 23), matched: "next week")
        assertDue("Hike this weekend", date(2026, 11, 21), matched: "this weekend", label: "Cmt 21 Kas")
        assertDue("Ship by end of week", date(2026, 11, 20), matched: "by end of week")
        assertDue("Invoice by the end of the month", date(2026, 11, 30), matched: "by the end of the month")
        assertDue("Budget next month", date(2026, 12, 1), label: "1 Ara")
        assertDue("Taxes end of year", date(2026, 12, 31))
        assertDue("Ping in 2 hours", date(2026, 11, 16, 12, 0), hasTime: true, label: "Bugün 12:00")
    }

    func testRelativeDaysTurkish() {
        assertDue("Annemi bugün ara", date(2026, 11, 16), matched: "bugün")
        assertDue("Annemi yarın ara", date(2026, 11, 17), matched: "yarın")
        assertDue("Rapor yarına kadar", date(2026, 11, 17), matched: "yarına kadar")
        assertDue("Rapor öbür gün", date(2026, 11, 18), matched: "öbür gün")
        assertDue("Rapor yarından sonra", date(2026, 11, 18), matched: "yarından sonra")
        assertDue("Valizi bu akşam hazırla", date(2026, 11, 16, 20, 0), hasTime: true, matched: "bu akşam")
        assertDue("Rapor 3 gün sonra", date(2026, 11, 19), matched: "3 gün sonra")
        assertDue("Rapor iki gün sonra", date(2026, 11, 18), matched: "iki gün sonra")
        assertDue("Rapor on iki gün sonra", date(2026, 11, 28))
        assertDue("Planla haftaya", date(2026, 11, 23), matched: "haftaya")
        assertDue("Planla gelecek hafta", date(2026, 11, 23), matched: "gelecek hafta")
        assertDue("Yürüyüş hafta sonu", date(2026, 11, 21), matched: "hafta sonu")
        assertDue("Bitir hafta sonuna kadar", date(2026, 11, 20), matched: "hafta sonuna kadar")
        assertDue("Fatura ay sonu", date(2026, 11, 30), matched: "ay sonu")
        assertDue("Fatura ay sonuna kadar", date(2026, 11, 30), matched: "ay sonuna kadar")
        assertDue("Bütçe gelecek ay", date(2026, 12, 1))
        assertDue("Vergi yıl sonu", date(2026, 12, 31), matched: "yıl sonu")
    }

    // MARK: Weekdays

    func testWeekdaysOnMonday() {
        assertDue("Standup Monday", date(2026, 11, 23), label: "Pzt 23 Kas")
        assertDue("Finish this until next Monday", date(2026, 11, 23), matched: "until next Monday", label: "Pzt 23 Kas")
        assertDue("Demo on Friday", date(2026, 11, 20), matched: "on Friday", label: "Cum 20 Kas")
        assertDue("Demo this Friday", date(2026, 11, 20))
        assertDue("Demo next Friday", date(2026, 11, 27))
        assertDue("Demo on Fri", date(2026, 11, 20))
        assertDue("Demo Monday at 3pm", date(2026, 11, 16, 15, 0), hasTime: true, label: "Bugün 15:00")
        assertDue("Demo Monday at 9am", date(2026, 11, 23, 9, 0), hasTime: true)
        assertDue("Rapor pazartesi", date(2026, 11, 23))
        assertDue("Rapor pazartesiye", date(2026, 11, 23), matched: "pazartesiye")
        assertDue("Rapor pazartesi günü", date(2026, 11, 23), matched: "pazartesi günü")
        assertDue("Rapor salı", date(2026, 11, 17), label: "Yarın")
        assertDue("Rapor çarşamba", date(2026, 11, 18))
        assertDue("Rapor perşembe", date(2026, 11, 19))
        assertDue("Rapor cumaya kadar", date(2026, 11, 20), matched: "cumaya kadar")
        assertDue("Rapor cuma'ya", date(2026, 11, 20), matched: "cuma'ya")
        assertDue("Rapor cumartesi", date(2026, 11, 21))
        assertDue("Rapor pazar", date(2026, 11, 22))
        assertDue("Rapor bu cuma", date(2026, 11, 20), matched: "bu cuma")
        assertDue("Rapor haftaya salı", date(2026, 11, 24), matched: "haftaya salı")
        assertDue("Rapor gelecek hafta çarşamba", date(2026, 11, 25))
        assertDue("Monday's report", date(2026, 11, 23))
    }

    func testWeekdaysOnOtherDays() {
        assertDue("Standup next Monday", date(2026, 11, 23), now: wednesday)
        assertDue("Demo next Friday", date(2026, 11, 27), now: wednesday)
        assertDue("Demo Friday", date(2026, 11, 20), now: wednesday)
        assertDue("Demo this Monday", date(2026, 11, 23), now: wednesday)
        assertDue("Standup next Monday", date(2026, 11, 23), now: sunday)
        assertDue("Toplantı haftaya pazartesi", date(2026, 11, 23), now: sunday)
        assertDue("Hike this weekend", date(2026, 11, 22), now: sunday)
        assertDue("Ship end of week", date(2026, 11, 27), now: sunday)
    }

    func testCumartesiIsNotCuma() {
        assertDue("cumartesi pazar yap", date(2026, 11, 21), matched: "cumartesi")
        assertDue("CUMARTESİ", date(2026, 11, 21))
    }

    // MARK: Absolute dates

    func testAbsoluteDates() {
        assertDue("Doğum günü 23 Kasım", date(2026, 11, 23), matched: "23 Kasım")
        assertDue("Doğum günü 23 kas", date(2026, 11, 23))
        assertDue("Doğum günü 23.11", date(2026, 11, 23), matched: "23.11")
        assertDue("Doğum günü 23/11", date(2026, 11, 23))
        assertDue("Birthday Nov 23", date(2026, 11, 23), matched: "Nov 23")
        assertDue("Birthday November 23rd", date(2026, 11, 23), matched: "November 23rd")
        assertDue("Birthday 23 November 2027", date(2027, 11, 23), label: "23 Kas 2027")
        assertDue("Birthday 11/23", date(2026, 11, 23))
        assertDue("Birthday 2027-03-05", date(2027, 3, 5))
        assertDue("Rapor 23 Kasım'a kadar", date(2026, 11, 23), matched: "23 Kasım'a kadar")
        assertDue("Rapor 23.11'e kadar", date(2026, 11, 23), matched: "23.11'e kadar")
        assertDue("Rapor 5 Ocak", date(2027, 1, 5), label: "5 Oca 2027")
        assertDue("Rapor 10 Kasım", date(2027, 11, 10))
        assertDue("Rapor 1 Aralık", date(2026, 12, 1))
        assertDue("Pay on the 25th", date(2026, 11, 25), matched: "on the 25th")
        assertNoDue("Rapor 31 Şubat")
    }

    func testYears() {
        assertDue("Finish thesis by 2027", date(2027, 12, 31), matched: "by 2027", label: "31 Ara 2027")
        assertDue("Tezi 2027'ye kadar bitir", date(2027, 12, 31), matched: "2027'ye kadar")
        assertNoDue("2027 planı")
        assertNoDue("Plan for 2020")
    }

    // MARK: Times

    func testTimesAlone() {
        assertDue("Call 15:00", date(2026, 11, 16, 15, 0), hasTime: true, matched: "15:00", label: "Bugün 15:00")
        assertDue("Call 15.00", date(2026, 11, 16, 15, 0), hasTime: true)
        assertDue("Call 3pm", date(2026, 11, 16, 15, 0), hasTime: true)
        assertDue("Call 3 pm", date(2026, 11, 16, 15, 0), hasTime: true, matched: "3 pm")
        assertDue("Call at 9", date(2026, 11, 17, 9, 0), hasTime: true, matched: "at 9", label: "Yarın 09:00")
        assertDue("Call at noon", date(2026, 11, 16, 12, 0), hasTime: true)
        assertDue("Deploy before midnight", date(2026, 11, 16, 23, 59), hasTime: true)
        assertDue("Ara saat 3te", date(2026, 11, 16, 15, 0), hasTime: true, matched: "saat 3te")
        assertDue("Ara 15'te", date(2026, 11, 16, 15, 0), hasTime: true, matched: "15'te")
        assertDue("Ara 15te", date(2026, 11, 16, 15, 0), hasTime: true)
        assertDue("Ara sabah 9", date(2026, 11, 17, 9, 0), hasTime: true, matched: "sabah 9")
        assertDue("Ara öğlen", date(2026, 11, 16, 12, 0), hasTime: true)
        assertDue("Ara akşam 7", date(2026, 11, 16, 19, 0), hasTime: true)
        assertDue("Ara gece 11", date(2026, 11, 16, 23, 0), hasTime: true)
        assertDue("Ara 9:30", date(2026, 11, 17, 9, 30), hasTime: true)
    }

    func testDayAndTimeCombined() {
        assertDue("Faturayı yarın 15te öde", date(2026, 11, 17, 15, 0), hasTime: true, matched: "yarın 15te", label: "Yarın 15:00")
        assertDue("Call tomorrow at 3pm", date(2026, 11, 17, 15, 0), hasTime: true, matched: "tomorrow at 3pm")
        assertDue("Call at 3pm tomorrow", date(2026, 11, 17, 15, 0), hasTime: true, matched: "at 3pm tomorrow")
        assertDue("Ara yarın saat 9", date(2026, 11, 17, 9, 0), hasTime: true, label: "Yarın 09:00")
        assertDue("Ara yarın akşam", date(2026, 11, 17, 20, 0), hasTime: true, matched: "yarın akşam")
        assertDue("Ara bu akşam 7de", date(2026, 11, 16, 19, 0), hasTime: true, matched: "bu akşam 7de")
        assertDue("Ara bu sabah 7de", date(2026, 11, 16, 7, 0), hasTime: true)
        assertDue("Ara tomorrow morning", date(2026, 11, 17, 9, 0), hasTime: true)
        assertDue("Ara cuma 14:00'e kadar", date(2026, 11, 20, 14, 0), hasTime: true, matched: "cuma 14:00'e kadar")
        assertDue("Ara 23.11 10:30", date(2026, 11, 23, 10, 30), hasTime: true, label: "Pzt 23 Kas 10:30")
        assertDue("Ara tonight at 9", date(2026, 11, 16, 21, 0), hasTime: true)
    }

    // MARK: Recurrence

    func testRecurrence() {
        XCTAssertEqual(recurrenceValue("Vitamin every day"), .daily)
        XCTAssertEqual(recurrenceValue("Vitamin her gün"), .daily)
        XCTAssertEqual(recurrenceValue("Vitamin daily"), .daily)
        XCTAssertEqual(recurrenceValue("Standup every weekday"), .weekdaysOnly)
        XCTAssertEqual(recurrenceValue("Standup hafta içi her gün"), .weekdaysOnly)
        XCTAssertEqual(recurrenceValue("Standup every Monday"), .weekly(on: [2]))
        XCTAssertEqual(recurrenceValue("Standup her pazartesi"), .weekly(on: [2]))
        XCTAssertEqual(recurrenceValue("Standup her pazartesi ve perşembe"), .weekly(on: [2, 5]))
        XCTAssertEqual(recurrenceValue("Gym pazartesileri"), .weekly(on: [2]))
        XCTAssertEqual(recurrenceValue("Gym on Mondays"), .weekly(on: [2]))
        XCTAssertEqual(recurrenceValue("1:1 every 2 weeks"), TaskRecurrence(frequency: .weekly, interval: 2))
        XCTAssertEqual(recurrenceValue("1:1 every other week"), TaskRecurrence(frequency: .weekly, interval: 2))
        XCTAssertEqual(recurrenceValue("Görüşme 2 haftada bir"), TaskRecurrence(frequency: .weekly, interval: 2))
        XCTAssertEqual(recurrenceValue("Görüşme iki haftada bir"), TaskRecurrence(frequency: .weekly, interval: 2))
        XCTAssertEqual(recurrenceValue("Rapor every month"), .monthly)
        XCTAssertEqual(recurrenceValue("Rapor her ay"), .monthly)
        XCTAssertEqual(recurrenceValue("Rapor monthly"), .monthly)
        XCTAssertEqual(recurrenceValue("Rapor weekly"), .weekly)
        XCTAssertEqual(recurrenceValue("Vergi every year"), .yearly)
        XCTAssertEqual(recurrenceValue("Vergi her yıl"), .yearly)
        XCTAssertNil(recurrenceValue("Rapor her"))
        XCTAssertNil(recurrenceValue("Rapor every Mo"))
    }

    func testRecurrenceLabelsAndFirstOccurrence() {
        XCTAssertEqual(recurrence("her pazartesi standup")?.label, "Her pazartesi")
        XCTAssertEqual(recurrence("her pazartesi standup")?.firstOccurrence, date(2026, 11, 16))
        XCTAssertEqual(recurrence("every friday review")?.firstOccurrence, date(2026, 11, 20))
        XCTAssertEqual(recurrence("hafta içi her gün")?.label, "Her hafta içi")
        XCTAssertEqual(recurrence("2 haftada bir")?.label, "2 haftada bir")
        XCTAssertEqual(recurrence("her gün")?.label, "Her gün")
        XCTAssertEqual(recurrence("her ay")?.label, "Her ay")
        XCTAssertEqual(recurrence("her yıl")?.label, "Her yıl")
        XCTAssertEqual(TaskPriority.high.displayText, "Yüksek öncelik")
        XCTAssertEqual(TaskPriority.low.displayText, "Düşük öncelik")
    }

    func testRecurrenceWithTimeAnchorsToOccurrence() {
        assertDue("Standup her pazartesi 9da", date(2026, 11, 23, 9, 0), hasTime: true)
        assertDue("Standup every Monday at 11", date(2026, 11, 16, 11, 0), hasTime: true)
    }

    // MARK: Priority

    func testPriority() {
        XCTAssertEqual(priority("Ship it !"), .low)
        XCTAssertEqual(priority("Ship it !!"), .medium)
        XCTAssertEqual(priority("Ship it !!!"), .high)
        XCTAssertEqual(priority("Ship it urgent"), .high)
        XCTAssertEqual(priority("Faturayı öde acil"), .high)
        XCTAssertEqual(priority("Read important doc"), .medium)
        XCTAssertEqual(priority("Önemli: sözleşme"), .medium)
        XCTAssertEqual(priority("Fix bug high priority"), .high)
        XCTAssertEqual(priority("Bug yüksek öncelik"), .high)
        XCTAssertEqual(priority("Cleanup low priority"), .low)
        XCTAssertEqual(priority("Temizlik düşük öncelik"), .low)
        XCTAssertNil(priority("Wow!!!"))
        XCTAssertNil(priority("See https://example.com/!!!"))
    }

    // MARK: Protected content

    func testDoesNotMatchInsideProtectedContent() {
        assertNoDue("Read https://example.com/monday/tomorrow")
        assertNoDue("Mail monday@example.com")
        assertNoDue("Ping @yarin")
        assertNoDue("Tag #bugün")
        assertNoDue("Upgrade to v1.2")
        assertNoDue("Upgrade to version 2.10")
        assertNoDue("Pay 15.00 TL")
        assertNoDue("Call 0532 123 45 67")
        assertNoDue("Pay $15.00")
        XCTAssertNil(priority("Ask @acil"))
    }

    func testPartialInputIsSafe() {
        assertNoDue("next Mo")
        assertNoDue("yar")
        assertNoDue("Finish this until next")
        assertNoDue("tom")
        assertNoDue("15:")
        assertNoDue("Ara saat")
        let samples = [
            "Finish this until next Monday at 3pm !!!",
            "Faturayı yarın 15te öde acil",
            "her pazartesi ve perşembe standup notları !",
            "Rapor 23.11.2027'ye kadar",
            "İ ı ' ’ 23/ /11 : . !! #@ 99999 2027-"
        ]
        for sample in samples {
            var prefix = ""
            for character in sample {
                prefix.append(character)
                for suggestion in parser.suggestions(for: prefix, now: monday) {
                    XCTAssertEqual(String(prefix[suggestion.range]), suggestion.matchedText)
                    if case let .due(value, _) = suggestion.kind {
                        XCTAssertGreaterThanOrEqual(value, date(2026, 11, 16), "past date for \"\(prefix)\"")
                    }
                }
            }
        }
    }

    // MARK: Turkish casing

    func testTurkishCasing() {
        assertDue("YARIN", date(2026, 11, 17))
        assertDue("BUGÜN", date(2026, 11, 16))
        assertDue("PAZARTESİ", date(2026, 11, 23))
        assertDue("HAFTAYA SALI", date(2026, 11, 24))
        assertDue("İki gün sonra", date(2026, 11, 18))
        assertDue("TOMORROW", date(2026, 11, 17))
        assertDue("FRIDAY", date(2026, 11, 20))
    }

    // MARK: Suggestions and apply

    func testSuggestionOrderAndStableIDs() {
        let suggestions = parser.suggestions(for: "Standup her pazartesi 9da acil", now: monday)
        XCTAssertEqual(suggestions.count, 3)
        guard suggestions.count == 3 else { return }
        if case .due = suggestions[0].kind {} else { XCTFail("first should be due") }
        if case .recurrence = suggestions[1].kind {} else { XCTFail("second should be recurrence") }
        if case .priority = suggestions[2].kind {} else { XCTFail("third should be priority") }

        let first = dueSuggestion("Rapor yarın")
        let typingMore = dueSuggestion("Rapor yarın ö")
        XCTAssertEqual(first?.id, typingMore?.id)
        XCTAssertNotEqual(first?.id, dueSuggestion("Raporu yarın")?.id)
    }

    func testApplyRemovesAcceptedPhrases() {
        let text = "Faturayı yarın 15te öde"
        let result = parser.apply(parser.suggestions(for: text, now: monday), to: text)
        XCTAssertEqual(result.title, "Faturayı öde")
        XCTAssertEqual(result.dueDate, date(2026, 11, 17, 15, 0))
        XCTAssertTrue(result.dueHasTime)
        XCTAssertNil(result.recurrence)
        XCTAssertEqual(result.priority, TaskPriority.none)

        let english = "Finish this until next Monday"
        XCTAssertEqual(parser.apply(parser.suggestions(for: english, now: monday), to: english).title, "Finish this")

        let recurring = "her pazartesi standup notları !"
        let recurringResult = parser.apply(parser.suggestions(for: recurring, now: monday), to: recurring)
        XCTAssertEqual(recurringResult.title, "standup notları")
        XCTAssertEqual(recurringResult.recurrence, .weekly(on: [2]))
        XCTAssertEqual(recurringResult.priority, .low)
        XCTAssertEqual(recurringResult.dueDate, date(2026, 11, 16))
        XCTAssertFalse(recurringResult.dueHasTime)

        let punctuated = "Rapor, yarın, gönder"
        XCTAssertEqual(parser.apply(parser.suggestions(for: punctuated, now: monday), to: punctuated).title, "Rapor, gönder")
    }

    func testApplyWithoutAcceptingKeepsPlainText() {
        let text = "  Faturayı yarın 15te öde  "
        let result = parser.apply([], to: text)
        XCTAssertEqual(result.title, "Faturayı yarın 15te öde")
        XCTAssertNil(result.dueDate)
        XCTAssertEqual(result.priority, TaskPriority.none)
    }

    func testApplyKeepsOriginalWhenEverythingMatched() {
        let text = "yarın 15:00"
        let result = parser.apply(parser.suggestions(for: text, now: monday), to: text)
        XCTAssertEqual(result.title, "yarın 15:00")
        XCTAssertEqual(result.dueDate, date(2026, 11, 17, 15, 0))
    }

    func testApplyPartialAcceptance() {
        let text = "Rapor yarın acil"
        let suggestions = parser.suggestions(for: text, now: monday)
        let onlyPriority = suggestions.filter {
            if case .priority = $0.kind { return true }
            return false
        }
        let result = parser.apply(onlyPriority, to: text)
        XCTAssertEqual(result.title, "Rapor yarın")
        XCTAssertNil(result.dueDate)
        XCTAssertEqual(result.priority, .high)
    }

    // MARK: Performance

    func testParsingIsFast() {
        let base = "Faturayı yarın 15te öde, every Monday at 9 review https://example.com/x !!! "
        let text = String(String(repeating: base, count: 3).prefix(200))
        XCTAssertEqual(text.count, 200)
        _ = parser.suggestions(for: text, now: monday)
        let iterations = 200
        let start = Date()
        for _ in 0..<iterations { _ = parser.suggestions(for: text, now: monday) }
        let average = Date().timeIntervalSince(start) / Double(iterations)
        XCTAssertLessThan(average, 0.002, "average \(average * 1000) ms")
    }
}
