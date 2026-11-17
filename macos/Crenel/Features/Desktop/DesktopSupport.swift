import AppKit
import SwiftUI

// MARK: - Actions

/// Everything the desktop window asks the app to do. Views never reach into
/// `AppDelegate`; the window controller builds this once, tests build their own.
struct DesktopActions {
    var startRecording: () -> Void = {}
    var stopRecording: () -> Void = {}
    var toggleMicrophone: () -> Void = {}
    var showNotch: () -> Void = {}
    var openMeetingURL: (URL) -> Void = { _ in }
    var copyText: (String) -> Void = { _ in }
    var exportMarkdown: (String, StoredMeeting) -> Void = { _, _ in }
    /// PDF and plain-text exports of a meeting with a transcript.
    var exportMeeting: (MeetingExportFormat, StoredMeeting, StoredTranscription) -> Void = { _, _, _ in }
    var revealAudio: (URL) -> Void = { _ in }
    /// Shows a meeting's audio in Finder when its detail could not be loaded.
    var revealMeetingAudio: (StoredMeeting) -> Void = { _ in }
    var retryProcessing: (StoredMeeting) -> Void = { _ in }
    var deleteMeeting: (StoredMeeting) -> Void = { _ in }
    var loadMeeting: (StoredMeeting) async throws -> MeetingDetailContent = { _ in throw CancellationError() }
    var analysis = MeetingAnalysisActions()
    var loadPreferences: () async -> CrenelPreferences = { .default }
    var savePreferences: (CrenelPreferences) async -> SettingsActionResult = { _ in .succeeded() }
    var openReminders: () -> Void = {}
    var settings: (SettingsCategory) -> AnyView = { AnyView(SettingsView(initialCategory: $0)) }
}

extension DesktopActions {
    @MainActor
    init(delegate: AppDelegate) {
        self.init(
            startRecording: { [weak delegate] in delegate?.startManualRecording() },
            stopRecording: { [weak delegate] in delegate?.stopRecordingFlow() },
            toggleMicrophone: { [weak delegate] in delegate?.toggleMeetingMicrophoneGate() },
            showNotch: { [weak delegate] in delegate?.showCrenel() },
            openMeetingURL: { [weak delegate] in delegate?.openMeetingURL($0) },
            copyText: { [weak delegate] in delegate?.copyToPasteboard($0) },
            exportMarkdown: { [weak delegate] in delegate?.exportMarkdown($0, for: $1) },
            exportMeeting: { [weak delegate] in delegate?.exportMeeting($1, transcription: $2, as: $0) },
            revealAudio: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            revealMeetingAudio: { [weak delegate] meeting in
                Task { @MainActor in
                    guard let url = await delegate?.desktopAudioURL(for: meeting) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            retryProcessing: { [weak delegate] in delegate?.retryProcessing($0) },
            deleteMeeting: { [weak delegate] in delegate?.deleteStoredMeeting($0) },
            loadMeeting: { [weak delegate] meeting in
                guard let delegate else { throw CancellationError() }
                return try await delegate.loadDesktopMeeting(meeting)
            },
            analysis: delegate.meetingAnalysisActions,
            loadPreferences: { [weak delegate] in await delegate?.loadCrenelPreferences() ?? .default },
            savePreferences: { [weak delegate] preferences in
                await delegate?.saveCrenelPreferences(preferences) ?? .failed(message: "The app is quitting.")
            },
            openReminders: {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            },
            settings: { [weak delegate] category in
                guard let delegate else { return AnyView(EmptyView()) }
                return AnyView(delegate.desktopSettings(category: category))
            }
        )
    }
}

// MARK: - Clock

private struct DesktopFixedNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// A frozen clock for offscreen renders; `nil` follows the wall clock.
    var desktopFixedNow: Date? {
        get { self[DesktopFixedNowKey.self] }
        set { self[DesktopFixedNowKey.self] = newValue }
    }
}

/// Hands its content the current time, refreshed every half minute.
struct DesktopClock<Content: View>: View {
    @Environment(\.desktopFixedNow) private var fixedNow
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if let fixedNow {
            content(fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(context.date)
            }
        }
    }
}

// MARK: - Formats

enum DesktopFormat {
    /// "48:12", "1:02:40" — the length of a recording.
    static func length(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }

    /// "48:12", "2:10" — a recording's length in a list's time column (no leading zero).
    static func runLength(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }

    /// "4:12" — hours and minutes for the weekly readout.
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "9 h 40", "48 min" — the total on tape in the toolbar.
    static func tape(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        return minutes >= 60 ? String(format: "%d h %02d", minutes / 60, minutes % 60) : "\(minutes) min"
    }

    /// "48 min", "1 h 12 min".
    static func minutes(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        NotchAgendaFormatter.clockText(date, calendar: calendar)
    }

    /// Group title for a day: "Today", "Yesterday", "Mon 16".
    static func dayGroup(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(date, sameYear ? "EEE d" : "d MMM yyyy", calendar: calendar)
    }

    /// "Tuesday, 17 November".
    static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "EEEE, d MMMM", calendar: calendar)
    }

    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "EEE", calendar: calendar)
    }

    static func format(_ date: Date, _ pattern: String, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Decimal hours of a date within its day (14.5 = 14:30).
    static func decimalHour(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// The call service or the place of a calendar item.
    static func venue(_ meeting: Meeting) -> String? {
        if let host = meeting.meetingURL?.host()?.lowercased() {
            if host.contains("meet.google") { return "Google Meet" }
            if host.contains("zoom") { return "Zoom" }
            if host.contains("teams") { return "Teams" }
            if host.contains("webex") { return "Webex" }
            if host.contains("whereby") { return "Whereby" }
            if host.contains("facetime") { return "FaceTime" }
            return host.replacingOccurrences(of: "www.", with: "")
        }
        if let location = meeting.location, !location.isEmpty, !location.contains("://") { return location }
        return meeting.calendarTitle
    }

    static func venueGlyph(_ meeting: Meeting) -> HudGlyph {
        if meeting.meetingURL != nil { return .video }
        if meeting.location?.isEmpty == false { return .place }
        return .calendar
    }

    static func speakerName(_ segment: TranscriptSegment) -> String {
        let name = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        let suffix = segment.speakerID.split(separator: "_").last.flatMap { Int($0) }.map { String($0 + 1) }
        return "Speaker \(suffix ?? segment.speakerID)"
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

// MARK: - Derived figures

/// Numbers the dashboard prints, computed from stored data. Pure, so tests can check them.
enum DesktopStats {
    struct WeekDay: Equatable {
        let date: Date
        let label: String
        let seconds: TimeInterval
        let isToday: Bool
        let isFuture: Bool
    }

    /// Recorded time for each day of the current week, first weekday first.
    static func week(meetings: [StoredMeeting], now: Date, calendar: Calendar = .current) -> [WeekDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let seconds = meetings
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.duration }
            return WeekDay(date: day, label: DesktopFormat.weekday(day, calendar: calendar), seconds: seconds,
                           isToday: day == today, isFuture: day > today)
        }
    }

    /// Lit cells of a day's LED stack: the week's busiest day (at least two hours) fills it.
    static func stackCells(_ seconds: TimeInterval, week: [WeekDay], cells: Int = 8) -> Int {
        guard seconds > 0 else { return 0 }
        let scale = max(2 * 3_600, week.map(\.seconds).max() ?? 0)
        return min(cells, max(1, Int((seconds / scale * Double(cells)).rounded())))
    }

    static func dictationToday(_ history: [DictationHistoryEntry], now: Date, calendar: Calendar = .current) -> (words: Int, count: Int) {
        let today = history.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        return (today.reduce(0) { $0 + DesktopFormat.wordCount($1.finalText) }, today.count)
    }

    /// "Your usual": the median words per day over the last 14 days that had any dictation,
    /// today left out. Nil with fewer than three such days — too little to call usual.
    static func usualDictationWords(_ history: [DictationHistoryEntry], now: Date, calendar: Calendar = .current) -> Double? {
        var words = DictationDailyWords()
        for entry in history { words.add(DesktopFormat.wordCount(entry.finalText), at: entry.createdAt, calendar: calendar) }
        return usualDictationWords(words, now: now, calendar: calendar)
    }

    /// The same, from the per-day counts kept across launches.
    static func usualDictationWords(_ daily: DictationDailyWords, now: Date, calendar: Calendar = .current) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -14, to: today) else { return nil }
        let days = daily.days.filter { $0.key >= earliest && $0.key < today }.values.filter { $0 > 0 }.sorted()
        guard days.count >= 3 else { return nil }
        let middle = days.count / 2
        return days.count.isMultiple(of: 2)
            ? Double(days[middle - 1] + days[middle]) / 2
            : Double(days[middle])
    }

    /// The Dictation tile's dot matrix: today's fill and where "your usual" sits on the same
    /// scale. The scale is the larger of today and one and a half usual days, so the usual
    /// mark lands two thirds along until today passes it.
    static func dictationScale(todayWords: Int, usual: Double?) -> (value: Double, mark: Double?) {
        guard let usual, usual > 0 else {
            // No usual yet: one dot for every 20 words, a printed scale and not a comparison.
            return (min(1, Double(todayWords) / Double(78 * 20)), nil)
        }
        let scale = max(usual * 1.5, Double(todayWords))
        return (Double(todayWords) / scale, usual / scale)
    }

    struct TalkShare: Equatable, Identifiable {
        let speakerID: String
        let name: String
        let seconds: TimeInterval
        let share: Double
        /// Order of first appearance; picks the ink of the bar and the lane.
        let index: Int
        var id: String { speakerID }
    }

    /// Talk time per speaker from transcript segments, longest first.
    static func talkTime(_ transcript: Transcript) -> [TalkShare] {
        var order: [String] = []
        var seconds: [String: TimeInterval] = [:]
        var names: [String: String] = [:]
        for segment in transcript.segments {
            if seconds[segment.speakerID] == nil { order.append(segment.speakerID) }
            seconds[segment.speakerID, default: 0] += max(0, segment.endTime - segment.startTime)
            names[segment.speakerID] = DesktopFormat.speakerName(segment)
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }
        return order.enumerated()
            .map { index, id in
                TalkShare(speakerID: id, name: names[id] ?? id, seconds: seconds[id] ?? 0, share: (seconds[id] ?? 0) / total, index: index)
            }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Who spoke when, as shares of the recording, for the lane under the waveform.
    static func lane(_ transcript: Transcript, duration: TimeInterval, limit: Int = 60) -> [(share: Double, speaker: Int)] {
        guard duration > 0, !transcript.segments.isEmpty else { return [] }
        var order: [String: Int] = [:]
        var runs: [(start: TimeInterval, end: TimeInterval, speaker: Int)] = []
        for segment in transcript.segments.sorted(by: { $0.startTime < $1.startTime }) {
            let speaker = order[segment.speakerID] ?? order.count
            order[segment.speakerID] = speaker
            if let last = runs.last, last.speaker == speaker {
                runs[runs.count - 1].end = max(last.end, segment.endTime)
            } else {
                runs.append((segment.startTime, max(segment.startTime, segment.endTime), speaker))
            }
        }
        // Too many turns would turn the lane into noise; merge the shortest neighbours away.
        while runs.count > limit, let shortest = runs.indices.dropFirst().min(by: { runs[$0].end - runs[$0].start < runs[$1].end - runs[$1].start }) {
            runs[shortest - 1].end = runs[shortest].end
            runs.remove(at: shortest)
        }
        return runs.map { (share: max(0.002, ($0.end - $0.start) / duration), speaker: $0.speaker) }
    }
}

// MARK: - Systems

/// One telltale of the sidebar's Systems panel, read from the real permission state.
struct DesktopSystem: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case calendar, reminders, microphone, callAudio, muteSync, keyboard }

    let kind: Kind
    let glyph: HudGlyph
    let state: Hud.LampColor
    var paren = false
    var badge: HudGlyphBadge?
    let help: String
    let category: SettingsCategory

    var id: Kind { kind }
    var isOn: Bool { state == .teal }
    var needsUser: Bool { paren || badge != nil }

    static func == (lhs: DesktopSystem, rhs: DesktopSystem) -> Bool {
        lhs.kind == rhs.kind && lhs.state == rhs.state && lhs.paren == rhs.paren && lhs.help == rhs.help
            && (lhs.badge == nil) == (rhs.badge == nil)
    }

    @MainActor
    static func all(_ state: AppState) -> [DesktopSystem] {
        [calendar(state), reminders(state.taskStorageStatus), microphone(state.audioCapturePermissions.microphone),
         callAudio(state.audioCapturePermissions.systemAudio), muteSync(state.accessibilityPermissionGranted),
         keyboard(state.dictationAvailability)]
    }

    @MainActor
    private static func calendar(_ state: AppState) -> DesktopSystem {
        func make(_ lamp: Hud.LampColor, paren: Bool = false, badge: HudGlyphBadge? = nil, _ help: String) -> DesktopSystem {
            DesktopSystem(kind: .calendar, glyph: .calendar, state: lamp, paren: paren, badge: badge, help: help, category: .calendar)
        }
        guard state.isCalendarEnabled else { return make(.off, "Calendar is off") }
        switch state.calendarAccessState {
        case .authorized: return make(.teal, "Calendar")
        case .denied, .restricted: return make(.amber, paren: true, "Calendar access is off")
        case .failed: return make(.red, badge: .bang, "Calendar can’t refresh")
        case .notDetermined, .requesting: return make(.off, "Calendar isn’t connected")
        }
    }

    private static func reminders(_ status: TaskStorageStatus) -> DesktopSystem {
        func make(_ lamp: Hud.LampColor, paren: Bool = false, badge: HudGlyphBadge? = nil, _ help: String) -> DesktopSystem {
            DesktopSystem(kind: .reminders, glyph: .queue, state: lamp, paren: paren, badge: badge, help: help, category: .tasks)
        }
        switch status {
        case .reminders: return make(.teal, "Reminders")
        case .localDenied: return make(.amber, paren: true, "Reminders access is off")
        case .localAfterError: return make(.red, badge: .bang, "Reminders can’t sync")
        case .localNotConnected: return make(.off, "Reminders isn’t connected")
        case .localByChoice: return make(.off, "Tasks stay on this Mac")
        }
    }

    private static func microphone(_ status: AudioCapturePermissionStatus) -> DesktopSystem {
        func make(_ lamp: Hud.LampColor, paren: Bool = false, _ help: String) -> DesktopSystem {
            DesktopSystem(kind: .microphone, glyph: .mic, state: lamp, paren: paren, help: help, category: .recording)
        }
        switch status {
        case .authorized: return make(.teal, "Microphone")
        case .denied, .restricted: return make(.red, paren: true, "Microphone is off")
        case .notDetermined, .verificationRequired: return make(.off, "Microphone isn’t allowed yet")
        }
    }

    private static func callAudio(_ status: AudioCapturePermissionStatus) -> DesktopSystem {
        func make(_ lamp: Hud.LampColor, paren: Bool = false, _ help: String) -> DesktopSystem {
            DesktopSystem(kind: .callAudio, glyph: .speaker, state: lamp, paren: paren, help: help, category: .recording)
        }
        switch status {
        case .authorized, .verificationRequired: return make(.teal, "Call audio")
        case .denied, .restricted: return make(.red, paren: true, "Call audio is off")
        case .notDetermined: return make(.off, "Call audio isn’t allowed yet")
        }
    }

    private static func muteSync(_ granted: Bool) -> DesktopSystem {
        DesktopSystem(kind: .muteSync, glyph: .accessibility, state: granted ? .teal : .amber, paren: !granted,
                      help: granted ? "Mute sync" : "Mute sync needs Accessibility", category: .recording)
    }

    private static func keyboard(_ availability: DictationAvailability) -> DesktopSystem {
        func make(_ lamp: Hud.LampColor, paren: Bool = false, _ help: String) -> DesktopSystem {
            DesktopSystem(kind: .keyboard, glyph: .keyboard, state: lamp, paren: paren, help: help, category: .dictation)
        }
        switch availability {
        case .ready: return make(.teal, "Dictation key")
        case .needsInputMonitoring: return make(.amber, paren: true, "Input Monitoring is off")
        case .disabled: return make(.off, "Dictation is off")
        }
    }
}

// MARK: - Dictation preferences

/// The dictation settings the desktop shows and edits (shortcut, mode, language, words).
@MainActor
final class DesktopPreferencesModel: ObservableObject {
    @Published private(set) var preferences = CrenelPreferences.default
    @Published private(set) var isLoaded = false
    private var actions = DesktopActions()

    init(preset: CrenelPreferences? = nil) {
        if let preset {
            preferences = preset
            isLoaded = true
        }
    }

    func load(_ actions: DesktopActions) async {
        self.actions = actions
        guard !isPreset else { return }
        preferences = await actions.loadPreferences()
        isLoaded = true
    }

    private var isPreset = false

    static func preset(_ preferences: CrenelPreferences) -> DesktopPreferencesModel {
        let model = DesktopPreferencesModel(preset: preferences)
        model.isPreset = true
        return model
    }

    func update(_ change: (inout CrenelPreferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        preferences = next
        let snapshot = next
        let save = actions.savePreferences
        Task { _ = await save(snapshot) }
    }

    /// The key as printed on the keycap and in the rail: "fn", "⌥", "⌘", "key".
    var keyLabel: String {
        switch preferences.dictationTrigger.trigger {
        case .fnHold: "fn"
        case .rightOptionHold: "⌥"
        case .rightCommandHold: "⌘"
        case .shortcut: "key"
        }
    }

    /// The key as said in a sentence: "fn", "right ⌥", "right ⌘", "the shortcut".
    var keyPhrase: String {
        switch preferences.dictationTrigger.trigger {
        case .fnHold: "fn"
        case .rightOptionHold: "right ⌥"
        case .rightCommandHold: "right ⌘"
        case .shortcut: "the shortcut"
        }
    }
}

// MARK: - Search

/// The toolbar's search well (`.search`) with a focus handle and the ⌘F keycap.
struct DesktopSearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey
    var width: CGFloat = 270
    var focus: FocusState<Bool>.Binding

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 8) {
            HudIcon(.search, size: 14).foregroundStyle(Hud.Ink.ink3)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Hud.Ink.ink3))
                .textFieldStyle(.plain)
                .hud(.label)
                .focused(focus)
                .accessibilityLabel(Text(prompt))
            if text.isEmpty {
                HudKeycap("⌘F")
            } else {
                Button { text = "" } label: { HudIcon(.close, size: 12).foregroundStyle(Hud.Ink.ink3).frame(width: 20, height: 20).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(width: width, height: 30)
        .background(
            shape.fill(Color(white: 1, opacity: focus.wrappedValue ? 0.075 : 0.045)
                .shadow(.inner(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 1)))
        )
        .overlay(shape.strokeBorder(Color(white: 1, opacity: 0.05), lineWidth: 1))
        .animation(Hud.Motion.hover, value: focus.wrappedValue)
    }
}

// MARK: - Toolbar

/// The 60 pt page toolbar (`.tb`): title and meta at the leading edge, the page's
/// actions and search at the trailing edge.
struct DesktopToolbar<Actions: View>: View {
    let title: LocalizedStringKey
    var meta: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).hud(.hero).accessibilityAddTraits(.isHeader)
                if let meta {
                    Text(verbatim: meta).hud(.meta)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            actions()
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .frame(height: Hud.Window.toolbarHeight)
    }
}
