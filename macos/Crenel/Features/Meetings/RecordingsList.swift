import SwiftUI

// MARK: - Recordings (history)

/// Recorded meetings, newest first (`tpl-history`): the week on tape on top (only when
/// something was recorded this week), then the recordings grouped by month. Each row is
/// a `RecordingRow`: date tile, title, when · where · what came of it, the first line of
/// the notes, and the length over the waveform. Rows keep a small gap between them so
/// the hover slab never touches the next one.
///
///     RecentMeetingsList(meetings: stored, onOpen: open, onDelete: delete, onRetry: retry)
///     RecentMeetingsList(meetings: stored, …, recovery: summary, onOpenRecovery: show, onDismissRecovery: dismiss)
struct RecentMeetingsList: View {
    let meetings: [StoredMeeting]
    let onOpen: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void
    let onRetry: (StoredMeeting) -> Void
    /// Meetings the week meter counts. Defaults to `meetings`; pass the full store when
    /// the list itself is truncated.
    var weekMeetings: [StoredMeeting]?
    /// Recovered-recordings notice above the meter (`o-history-recovery`).
    var recovery: RecordingRecoverySummary?
    var onOpenRecovery: () -> Void = {}
    var onDismissRecovery: () -> Void = {}
    /// Second line of a row, when the caller knows more than the stored meeting does
    /// (people, open action items). The built-in line only names what is missing.
    var detail: ((StoredMeeting) -> String?)?
    var now: Date = Date()
    /// Galleries: show this row as hovered.
    var forcedHover: UUID?

    @State private var hovered: AnyHashable?
    @State private var appeared = false
    @StateObject private var playback = RecordingInlinePlayback()
    @Namespace private var glide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        meetings: [StoredMeeting],
        onOpen: @escaping (StoredMeeting) -> Void,
        onDelete: @escaping (StoredMeeting) -> Void,
        onRetry: @escaping (StoredMeeting) -> Void,
        weekMeetings: [StoredMeeting]? = nil,
        recovery: RecordingRecoverySummary? = nil,
        onOpenRecovery: @escaping () -> Void = {},
        onDismissRecovery: @escaping () -> Void = {},
        detail: ((StoredMeeting) -> String?)? = nil,
        now: Date = Date(),
        forcedHover: UUID? = nil
    ) {
        self.forcedHover = forcedHover
        self.meetings = meetings
        self.onOpen = onOpen
        self.onDelete = onDelete
        self.onRetry = onRetry
        self.weekMeetings = weekMeetings
        self.recovery = recovery
        self.onOpenRecovery = onOpenRecovery
        self.onDismissRecovery = onDismissRecovery
        self.detail = detail
        self.now = now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let recovery {
                RecordingsRecoveryNotice(summary: recovery, onOpenRecovery: onOpenRecovery, onDismiss: onDismissRecovery)
                    .padding(.bottom, 12)
                    .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)
            }
            if meetings.isEmpty {
                emptyState
                    .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)
            } else {
                let week = RecordingsWeek(meetings: weekMeetings ?? meetings, now: now)
                if week.total > 0 {
                    RecordingsWeekMeter(week: week)
                        .padding(.horizontal, Hud.Row.inset)
                        .padding(.bottom, 12)
                        .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)
                }
                let groups = RecordingsMonth.groups(meetings, now: now)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        HudListHeader(group.title, count: group.meetings.count, isFirst: group.id == groups.first?.id)

                        VStack(alignment: .leading, spacing: RecordingRow.spacing) {
                            ForEach(group.meetings) { meeting in
                                row(meeting)
                                    .hudGlide(meeting.id, hovered: $hovered, in: glide, forced: forcedHover.map(AnyHashable.init))
                            }
                        }
                    }
                }
                .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
            }
        }
        .onAppear { appeared = true }
        .onDisappear { playback.stop() }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            HudIcon(.tape, size: 14).foregroundStyle(Hud.Ink.ink3)
            Text("No recordings yet").hud(.body, Hud.Ink.ink2)
            Spacer(minLength: 8)
            Text("Crenel offers when a call starts").hud(.meta).lineLimit(1)
        }
        .padding(.horizontal, Hud.Row.inset)
        .frame(height: Hud.Row.oneLine)
        .accessibilityElement(children: .combine)
    }

    private func row(_ meeting: StoredMeeting) -> some View {
        let attention = RecordingAttention(meeting)
        return RecordingRow(meeting: meeting, isHovered: (forcedHover.map(AnyHashable.init) ?? hovered) == AnyHashable(meeting.id),
                     playback: playback) {
            onOpen(meeting)
        }
        .onTapGesture { onOpen(meeting) }
        .contextMenu {
            Button("Open meeting") { onOpen(meeting) }
            if meeting.processingStatus == .failed {
                Button("Retry processing") { onRetry(meeting) }
            }
            Divider()
            Button("Delete meeting", role: .destructive) { onDelete(meeting) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            [meeting.title, RecordingsFormat.date(meeting.startedAt, now: now), HudFormat.clock(meeting.startedAt),
             attention.word, detail?(meeting), RecordingsFormat.length(meeting.duration)]
                .compactMap { $0 }.joined(separator: ", ")
        )
    }
}

/// Recordings of one calendar month, newest first. The title is the month's name, with
/// the year when it is not this one.
struct RecordingsMonth: Identifiable, Equatable {
    let id: String
    let title: String
    let meetings: [StoredMeeting]

    static func groups(_ meetings: [StoredMeeting], now: Date, calendar: Calendar = .current) -> [RecordingsMonth] {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        var result: [RecordingsMonth] = []
        for meeting in meetings.sorted(by: { $0.startedAt > $1.startedAt }) {
            let parts = calendar.dateComponents([.year, .month], from: meeting.startedAt)
            let id = "\(parts.year ?? 0)-\(parts.month ?? 0)"
            if let last = result.last, last.id == id {
                result[result.count - 1] = RecordingsMonth(id: id, title: last.title, meetings: last.meetings + [meeting])
            } else {
                formatter.setLocalizedDateFormatFromTemplate(
                    calendar.isDate(meeting.startedAt, equalTo: now, toGranularity: .year) ? "MMMM" : "MMMM yyyy"
                )
                result.append(RecordingsMonth(id: id, title: formatter.string(from: meeting.startedAt), meetings: [meeting]))
            }
        }
        return result
    }
}

// MARK: - Row state

/// What a recording needs from you, if anything. Completed recordings with notes are
/// silent: no lamp, no word.
enum RecordingAttention: Equatable {
    case none
    /// Being transcribed or summarised: the running cells.
    case processing
    /// Transcription failed: triangle.
    case failed
    /// Transcript without notes: diamond.
    case noNotes
    /// Recorded, not transcribed yet: hourglass.
    case notTranscribed

    init(_ meeting: StoredMeeting) {
        switch meeting.processingStatus {
        case .processing: self = .processing
        case .failed: self = .failed
        case .recorded: self = .notTranscribed
        case .completed: self = meeting.summaryNeedsAttention == true ? .noNotes : .none
        }
    }

    var word: String? {
        switch self {
        case .none: nil
        case .processing: String(localized: "Processing")
        case .failed: String(localized: "Failed")
        case .noNotes: String(localized: "No notes")
        case .notTranscribed: String(localized: "Not transcribed")
        }
    }

    /// The row's second line when nothing richer is known.
    var detail: String? {
        self == .noNotes ? String(localized: "Transcript only") : nil
    }

    var status: HudStatus? {
        switch self {
        case .none: nil
        case .processing: .busy
        case .failed: .err
        case .noNotes: .warn
        case .notTranscribed: .wait
        }
    }

    @ViewBuilder var shape: some View {
        switch self {
        case .none: EmptyView()
        case .processing: HudBusy()
        case .failed: HudStatusShape(.err)
        case .noNotes: HudStatusShape(.warn)
        case .notTranscribed: HudStatusShape(.wait)
        }
    }
}

enum RecordingsFormat {
    /// "Today", "Yesterday", or a short weekday and day ("Mon 16").
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    /// Width of the date column of a row.
    static let dateColumn: CGFloat = 42
    /// Width of the time column of a row.
    static let timeColumn: CGFloat = 34

    /// The day a recording was made, as its row prints it: "25 Jul", and with the year
    /// when it is not this one ("25 Jul 25").
    static func date(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yy"
        return formatter.string(from: date)
    }

    /// How long a recording is, in words a glance can read: "1h 02m", "41m", "<1m".
    static func length(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded())
        if minutes == 0 { return interval > 0 ? "<1m" : "0m" }
        return minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }

    /// Hours and minutes for the week readout, as segment text: "4h 12m".
    static func hours(_ interval: TimeInterval) -> String {
        HudFormat.remaining(minutes: max(0, Int(interval / 60)))
    }
}

// MARK: - Week meter

/// Time on tape in the current calendar week, per day, computed from stored meetings.
struct RecordingsWeek: Equatable {
    struct Day: Equatable, Identifiable {
        let id: Int
        /// One letter: "M", "T" …
        let symbol: String
        let recorded: TimeInterval
        let isToday: Bool
        let isFuture: Bool
    }

    static let cells = 6

    let days: [Day]
    let total: TimeInterval

    /// Weekdays are always shown; a weekend day appears only when it is today or has a
    /// recording.
    init(meetings: [StoredMeeting], now: Date, calendar: Calendar = .current) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            days = []
            total = 0
            return
        }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        var result: [Day] = []
        var sum: TimeInterval = 0
        for offset in 0..<7 {
            guard let start = calendar.date(byAdding: .day, value: offset, to: week.start),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let recorded = meetings
                .filter { $0.startedAt >= start && $0.startedAt < end }
                .reduce(0) { $0 + $1.duration }
            sum += recorded
            let isToday = calendar.isDate(start, inSameDayAs: now)
            if calendar.isDateInWeekend(start), recorded == 0, !isToday { continue }
            let weekday = calendar.component(.weekday, from: start)
            result.append(Day(id: offset, symbol: symbols[(weekday - 1) % symbols.count], recorded: recorded,
                              isToday: isToday, isFuture: start > now))
        }
        days = result
        total = sum
    }

    /// Lit cells for a day: the busiest day fills the stack, and a stack never reads
    /// fuller than an hour per full stack would.
    func lit(_ day: Day) -> Int {
        guard day.recorded > 0 else { return 0 }
        let scale = max(3_600, days.map(\.recorded).max() ?? 0)
        return min(Self.cells, max(1, Int((day.recorded / scale * Double(Self.cells)).rounded(.up))))
    }
}

/// The week on tape (`tpl-history` week meter): total hours in segment digits, one LED
/// stack per day, today lit.
///
///     RecordingsWeekMeter(week: RecordingsWeek(meetings: stored, now: Date()))
struct RecordingsWeekMeter: View {
    let week: RecordingsWeek

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                HudSegmentDigits(RecordingsFormat.hours(week.total), height: 20)
                Text("recorded this week").hud(.unit).fixedSize()
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week.days) { day in
                    VStack(spacing: 6) {
                        HudLEDStack(lit: week.lit(day), cells: RecordingsWeek.cells, tone: day.isToday ? .today : .past, small: true)
                        Text(verbatim: day.symbol).hud(.micro, day.isToday ? Hud.Ink.ink2 : Hud.Ink.ink4)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RecordingsFormat.length(week.total)) recorded this week")
    }
}

// MARK: - Recovery notice

/// Recordings recovered after an interrupted session (`o-history-recovery`): a diamond,
/// what was recovered, and the way to the Recovery folder.
///
///     RecordingsRecoveryNotice(summary: summary, onOpenRecovery: showFolder, onDismiss: dismiss)
struct RecordingsRecoveryNotice: View {
    let summary: RecordingRecoverySummary
    let onOpenRecovery: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HudConsole(height: 52) {
            HudStatusShape(.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).hud(.body)
                if let subtitle {
                    Text(subtitle).hud(.meta)
                }
            }
            .padding(.leading, 2)
        } buttons: {
            HudButton("Show in Finder", size: .small, action: onOpenRecovery)
                .help("Show the Recovery folder")
            HudIconButton(.close, small: true, help: "Dismiss", action: onDismiss)
        }
    }

    private var title: String {
        if summary.recoveredCount > 0 {
            return summary.recoveredCount == 1
                ? String(localized: "1 recording recovered")
                : String(localized: "\(summary.recoveredCount) recordings recovered")
        }
        return String(localized: "\(summary.preservedCount) kept in Recovery")
    }

    private var subtitle: String? {
        guard summary.recoveredCount > 0, summary.preservedCount > 0 else { return nil }
        return String(localized: "\(summary.preservedCount) kept in Recovery")
    }
}
