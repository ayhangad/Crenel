import AppKit
import SwiftUI

/// What the calendar can show right now. Every state but `.ready` is an empty state:
/// the gauge at rest, one sentence, one fix.
enum TodayCalendarState: Equatable, Sendable {
    /// Calendar is switched off in Settings.
    case off
    /// Access was never asked for.
    case connect
    /// The system dialog is open.
    case waiting
    /// Access was refused or is restricted.
    case accessOff
    /// The last refresh failed; `lastRefresh` is when the list was last read.
    case failed(lastRefresh: Date?)
    /// Access granted, first read still running.
    case reading
    /// Access granted, but there is no calendar on this Mac.
    case noCalendars
    /// Events can be shown.
    case ready

    init(enabled: Bool, access: CalendarAccessState, snapshot: CalendarIntegrationSnapshot?) {
        guard enabled else {
            self = .off
            return
        }
        switch access {
        case .notDetermined: self = .connect
        case .requesting: self = .waiting
        case .denied, .restricted: self = .accessOff
        case .failed: self = .failed(lastRefresh: snapshot?.refreshedAt)
        case .authorized:
            guard let snapshot else {
                self = .reading
                return
            }
            self = snapshot.readableCalendarCount == 0 ? .noCalendars : .ready
        }
    }
}

/// The Google Meet audio bridge, when a Meet call is detected and it is not connected.
enum TodayMeetBridge: Equatable, Sendable {
    case none
    /// The extension has to be clicked in the call's tab.
    case waiting
    /// The bridge cannot be reached; recording cannot start.
    case unavailable
}

/// The single fix of each calendar empty state.
struct TodayCalendarFixes {
    var openPrivacySettings: () -> Void = {}
    var retry: () -> Void = {}
    var turnOn: () -> Void = {}
    var openAccounts: () -> Void = {}

    /// Wired to the running app.
    @MainActor static var live: TodayCalendarFixes {
        TodayCalendarFixes(
            openPrivacySettings: { (NSApp.delegate as? AppDelegate)?.openCalendarPrivacySettings() },
            retry: { (NSApp.delegate as? AppDelegate)?.refreshCalendar() },
            turnOn: {
                NotificationCenter.default.post(
                    name: .openDesktopSettings, object: nil, userInfo: ["category": SettingsCategory.calendar.rawValue]
                )
            },
            openAccounts: { (NSApp.delegate as? AppDelegate)?.openInternetAccountsSettings() }
        )
    }
}

/// "Today" while nothing is recording: the next event as one instrument, the shape of
/// the day on a ruler, then a timetable of what is left today and what comes later.
/// The console under the hero opens only when the call is near or on.
struct TodaySurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let events: [Meeting]
    let emptyMessage: String
    let canRequestCalendarAccess: Bool
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    /// nil: derived from `canRequestCalendarAccess` (older call sites).
    var calendar: TodayCalendarState?
    var meetBridge: TodayMeetBridge = .none
    var fixes: TodayCalendarFixes?
    /// A fixed clock, for renders and tests.
    var now: Date?
    /// Sweep the gauge once: only when the panel opens from closed.
    var ignite = false
    /// A row (its event id) or the hero (`TodaySurface.heroHoverID`) drawn as hovered, for renders.
    var previewHover: AnyHashable?
    static let heroHoverID: AnyHashable = "today.hero"
    @State private var appeared = false

    init(
        events: [Meeting],
        emptyMessage: String,
        canRequestCalendarAccess: Bool,
        onRequestCalendarAccess: @escaping () -> Void,
        onOpenMeetingURL: @escaping (URL) -> Void,
        onStartRecording: @escaping () -> Void,
        calendar: TodayCalendarState? = nil,
        meetBridge: TodayMeetBridge = .none,
        fixes: TodayCalendarFixes? = nil,
        now: Date? = nil,
        ignite: Bool = false,
        previewHover: AnyHashable? = nil
    ) {
        self.events = events
        self.emptyMessage = emptyMessage
        self.canRequestCalendarAccess = canRequestCalendarAccess
        self.onRequestCalendarAccess = onRequestCalendarAccess
        self.onOpenMeetingURL = onOpenMeetingURL
        self.onStartRecording = onStartRecording
        self.calendar = calendar
        self.meetBridge = meetBridge
        self.fixes = fixes
        self.now = now
        self.ignite = ignite
        self.previewHover = previewHover
    }

    var body: some View {
        Group {
            if let now {
                content(now: now)
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    content(now: context.date)
                }
            }
        }
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let agenda = TodayAgenda(events: events, now: now)
        let state = calendar ?? (canRequestCalendarAccess ? .connect : .ready)
        let console = TodayConsoleModel(focus: agenda.focus, now: now, bridge: meetBridge)

        VStack(alignment: .leading, spacing: 0) {
            if let focus = agenda.focus {
                TodayHero(
                    event: focus, now: now, ignite: ignite,
                    // The open console carries Record and Join itself.
                    onRecord: console == nil ? onStartRecording : nil,
                    onJoin: console == nil ? join(focus) : nil,
                    forcedHover: previewHover == Self.heroHoverID
                )
                .modifier(EventActions(event: focus, join: join(focus), onStartRecording: onStartRecording))
                    .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)
            }
            if let console {
                TodayConsole(
                    model: console,
                    onRecord: onStartRecording,
                    onJoin: agenda.focus.flatMap { event in event.meetingURL.map { url in { onOpenMeetingURL(url) } } }
                )
                .padding(.horizontal, 2)
                .padding(.bottom, 12)
                .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)
            }

            if agenda.hasRows || agenda.focus != nil {
                ruler(agenda, now: now)
                    .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
                timetable(agenda, now: now)
                    .padding(.top, 4)
                    .hudStagger(3, shown: appeared, reduceMotion: reduceMotion)
            } else if state == .ready {
                ruler(agenda, now: now)
                    .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
                nothingElseRow(agenda, now: now, canRecord: console == nil)
                    .hudStagger(3, shown: appeared, reduceMotion: reduceMotion)
                if !agenda.later.isEmpty {
                    group(String(localized: "Later"), agenda.later, now: now, isFirst: false)
                        .hudStagger(4, shown: appeared, reduceMotion: reduceMotion)
                }
            } else {
                TodayEmptyState(
                    state: state,
                    onConnect: onRequestCalendarAccess,
                    fixes: fixes ?? .live,
                    onRecord: console == nil ? onStartRecording : nil
                )
                .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ruler

    private func ruler(_ agenda: TodayAgenda, now: Date) -> some View {
        let scale = TodayRulerScale(agenda: agenda, now: now)
        return HudDayRuler(span: scale.span, now: scale.now, events: scale.events)
            .padding(.horizontal, 10)
    }

    // MARK: Timetable

    @ViewBuilder
    private func timetable(_ agenda: TodayAgenda, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !agenda.today.isEmpty {
                group(String(localized: "Today"), agenda.today, now: now, isFirst: true)
            }
            if !agenda.later.isEmpty {
                group(String(localized: "Later"), agenda.later, now: now, isFirst: agenda.today.isEmpty)
            }
        }
    }

    private func group(_ title: String, _ events: [Meeting], now: Date, isFirst: Bool) -> some View {
        TodayEventGroup(title: title, events: events, now: now, isFirst: isFirst, previewHover: previewHover,
                        onOpenMeetingURL: onOpenMeetingURL, onStartRecording: onStartRecording)
    }

    /// Calendars are connected and today is clear: say so, and name what comes next.
    private func nothingElseRow(_ agenda: TodayAgenda, now: Date, canRecord: Bool) -> some View {
        HStack(spacing: 12) {
            HudLamp(.teal)
            Text("Nothing else today").hud(.body, Hud.Ink.ink2)
            Spacer(minLength: 8)
            if canRecord {
                TodayRecordButton(action: onStartRecording)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, canRecord ? 4 : 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    /// Joining is only ever the Join button (or the menu), never a click on the event.
    private func join(_ event: Meeting) -> (() -> Void)? {
        event.meetingURL.map { url in { onOpenMeetingURL(url) } }
    }
}

// MARK: - Agenda

/// The events split the way the surface shows them. The hero is the next timed event
/// of today or tomorrow; what is further away is only named in "Later".
struct TodayAgenda {
    let focus: Meeting?
    let today: [Meeting]
    let later: [Meeting]
    /// Timed events of today, the hero included, for the ruler.
    let rulerEvents: [Meeting]

    var hasRows: Bool { !today.isEmpty || (focus != nil && !later.isEmpty) }

    init(events: [Meeting], now: Date, calendar: Calendar = .current) {
        let upcoming = events
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 1 : 0, $0.startDate) < ($1.isAllDay ? 1 : 0, $1.startDate) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let next = upcoming.first { !$0.isAllDay }
        let focus = next.flatMap { event in
            calendar.isDate(event.startDate, inSameDayAs: now) || event.startDate <= now
                || calendar.isDate(event.startDate, inSameDayAs: tomorrow) ? event : nil
        }
        let rest = upcoming.filter { $0.id != focus?.id }
        func isToday(_ event: Meeting) -> Bool {
            calendar.isDate(event.startDate, inSameDayAs: now) || event.startDate <= now
        }
        self.focus = focus
        today = rest.filter(isToday)
        later = rest.filter { !isToday($0) }.sorted { $0.startDate < $1.startDate }
        rulerEvents = events.filter { !$0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: now) }
    }
}

/// The day ruler's scale: 08–20, widened by whole hours when now or an event falls
/// outside it.
struct TodayRulerScale {
    let span: ClosedRange<Double>
    let now: Double
    let events: [HudDayRuler.Event]

    init(agenda: TodayAgenda, now date: Date, calendar: Calendar = .current) {
        func hours(_ value: Date) -> Double {
            let startOfDay = calendar.startOfDay(for: date)
            return min(24, max(0, value.timeIntervalSince(startOfDay) / 3_600))
        }
        let nowHours = hours(date)
        var lower = 8.0, upper = 20.0
        var blocks: [HudDayRuler.Event] = []
        for event in agenda.rulerEvents {
            let start = hours(event.startDate), end = max(hours(event.endDate), start + 0.25)
            lower = min(lower, start.rounded(.down))
            upper = max(upper, min(24, end.rounded(.up)))
            let kind: HudDayRuler.Event.Kind
            if event.id == agenda.focus?.id {
                let untilStart = event.startDate.timeIntervalSince(date)
                kind = untilStart <= 10 * 60 ? .amber : .focus
            } else if event.responseStatus == .pending {
                kind = .invite
            } else if event.kind == .event || event.responseStatus == .tentative || event.isSuggestion {
                kind = .dim
            } else {
                kind = .normal
            }
            blocks.append(HudDayRuler.Event(start, end, kind))
        }
        lower = min(lower, nowHours.rounded(.down))
        upper = max(upper, min(24, nowHours.rounded(.up)))
        span = lower...upper
        now = nowHours
        events = blocks
    }
}

/// Strings of the Today surface.
enum TodayText {
    /// "Wed" within the week, "12 Nov" further out.
    static func dayWord(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        formatter.dateFormat = days < 7 ? "EEE" : "d MMM"
        return formatter.string(from: date)
    }

    /// "Wed 10:00", or "Wed" for an all-day event.
    static func dayAndTime(_ event: Meeting, now: Date) -> String {
        let day = dayWord(event.startDate, now: now)
        return event.isAllDay ? day : "\(day) \(HudFormat.clock(event.startDate))"
    }

    /// "in 3 h 48", "in 2 h".
    static func distance(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "in \(rest) min" }
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(String(format: "%02d", rest))"
    }

    /// Whole minutes, rounded up, never below 1.
    static func minutes(_ interval: TimeInterval) -> Int {
        max(1, Int((interval / 60).rounded(.up)))
    }
}

/// One group of the timetable. It owns its hover slab, so hovering a row redraws the
/// rows and not the hero's gauge and the ruler above them.
private struct TodayEventGroup: View {
    let title: String
    let events: [Meeting]
    let now: Date
    let isFirst: Bool
    let previewHover: AnyHashable?
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void

    @State private var hovered: AnyHashable?
    @Namespace private var glide

    var body: some View {
        VStack(alignment: .leading, spacing: RecordingRow.spacing) {
            HudListHeader(title, count: events.count, isFirst: isFirst)
                .padding(.bottom, -RecordingRow.spacing)
            ForEach(events) { event in
                let join = event.meetingURL.map { url in { onOpenMeetingURL(url) } }
                TodayEventRow(event: event, now: now, isHovered: previewHover == AnyHashable(event.id), onJoin: join)
                    .modifier(EventActions(event: event, join: join, onStartRecording: onStartRecording))
                    .hudGlide(event.id, hovered: $hovered, in: glide, forced: previewHover)
            }
        }
    }
}

/// A click on an event does nothing: joining is the Join button that shows on hover.
/// The context menu holds the rest.
private struct EventActions: ViewModifier {
    @Environment(\.crenelActions) private var actions
    let event: Meeting
    let join: (() -> Void)?
    let onStartRecording: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .contextMenu {
                if let url = event.meetingURL, let join {
                    Button("Join meeting", action: join)
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    Button("Open in Calendar") { actions.openInCalendar(event) }
                    Divider()
                    Button("Record now", action: onStartRecording)
                } else {
                    Button("Open in Calendar") { actions.openInCalendar(event) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AgendaRowText.accessibilityLabel(for: event))
    }
}

/// Record, always within reach on Today: the hero's free trailing edge, or the empty
/// state's. Hidden while the console is open, which has its own.
private struct TodayRecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HudButtonLabel("Record", lamp: .red, key: "⌘R")
        }
        .buttonStyle(HudButtonStyle(kind: .secondary, size: .small))
            .hudShortcut("r")
            .accessibilityLabel("Record")
    }
}

/// Join, shown only while its event is hovered. It keeps its place in the layout so
/// nothing shifts when it appears.
private struct TodayHoverJoin: View {
    let shown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HudButtonLabel("Join")
        }
        // The same key face as Record beside it, so the two read as one size.
        .buttonStyle(HudButtonStyle(kind: .secondary, size: .small))
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .accessibilityLabel("Join")
            // Appears with the pointer, not after it.
            .transaction { $0.animation = nil }
    }
}

// MARK: - Hero

/// The next event as one instrument. The gauge is the last hour before it, one tick
/// per minute; while it runs, the share that is left.
private struct TodayHero: View {
    let event: Meeting
    let now: Date
    let ignite: Bool
    /// nil while the console under the hero is open.
    var onRecord: (() -> Void)?
    var onJoin: (() -> Void)?
    var forcedHover = false
    @State private var isHovering = false

    private var untilStart: TimeInterval { event.startDate.timeIntervalSince(now) }
    private var isLive: Bool { untilStart <= 0 }
    private var isUrgent: Bool { !isLive && untilStart <= 10 * 60 }
    private var isNear: Bool { !isLive && untilStart <= 60 * 60 }
    private var isToday: Bool { Calendar.current.isDate(event.startDate, inSameDayAs: now) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            gauge
                .opacity(isDimmed ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title).hud(.hero).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(verbatim: timeWord).hud(.meta)
                    if let venue = event.venueWord, !venue.isEmpty {
                        Text(verbatim: "·").hud(.meta, Hud.Ink.ink4)
                        Text(verbatim: venue).hud(.meta).lineLimit(1)
                    }
                }
                if let people = MeetingPeopleFormatter.short(event.attendees) {
                    HStack(spacing: 6) {
                        HudIcon(.people, size: 12).foregroundStyle(Hud.Ink.ink4)
                        Text(verbatim: people).hud(.meta).lineLimit(1).truncationMode(.tail)
                    }
                    .accessibilityElement(children: .combine)
                }
                if event.responseStatus == .pending {
                    HStack(spacing: 8) {
                        HudStatusShape(.warn)
                        Text("Invite").hud(.meta, Hud.Ink.ink2)
                    }
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isDimmed ? 0.55 : 1)
            HStack(spacing: 6) {
                if let onJoin {
                    TodayHoverJoin(shown: isHovering || forcedHover, action: onJoin)
                }
                if let onRecord {
                    TodayRecordButton(action: onRecord)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, onRecord == nil ? 10 : 4)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var isDimmed: Bool { event.isSuggestion || event.responseStatus == .tentative }

    @ViewBuilder
    private var gauge: some View {
        if isLive {
            let length = max(60, event.endDate.timeIntervalSince(event.startDate))
            let left = max(0, event.endDate.timeIntervalSince(now))
            HudGauge(value: min(1, left / length), tint: Hud.Ink.signal, ignite: ignite) {
                HudSegmentDigits("\(TodayText.minutes(left))", height: 24, cells: 2, color: Hud.Ink.signal)
                Text("min left").hud(.micro, Hud.Ink.signal.opacity(0.7))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TodayText.minutes(left)) minutes left")
        } else if isUrgent {
            HudGauge(value: min(1, untilStart / 3_600), tint: Hud.Ink.signal, zones: HudGaugeZone.redline, ignite: ignite) {
                HudSegmentDigits("\(TodayText.minutes(untilStart))", height: 24, cells: 2, color: Hud.Ink.signal)
                Text("min").hud(.micro, Hud.Ink.signal.opacity(0.7))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starts in \(TodayText.minutes(untilStart)) minutes")
        } else if isNear {
            HudGauge(value: min(1, untilStart / 3_600), zones: HudGaugeZone.countdown, ignite: ignite) {
                HudSegmentDigits("\(TodayText.minutes(untilStart))", height: 24, cells: 2)
                Text("min").hud(.micro, Hud.Ink.ink3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starts in \(TodayText.minutes(untilStart)) minutes")
        } else {
            HudGauge(value: 0, ignite: ignite) {
                HudSegmentDigits(HudFormat.clock(event.startDate), height: 17)
                Text(verbatim: isToday ? TodayText.distance(untilStart) : TodayText.dayWord(event.startDate, now: now))
                    .hud(.micro, Hud.Ink.ink3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starts at \(HudFormat.clock(event.startDate))")
        }
    }

    /// One time only: the start, or "Until 11:00" while it runs.
    private var timeWord: String {
        if isLive { return "Until \(HudFormat.clock(event.endDate))" }
        if isToday { return HudFormat.clock(event.startDate) }
        return "\(HudFormat.day(event.startDate, now: now)) \(HudFormat.clock(event.startDate))"
    }
}

// MARK: - Console

/// What the console says and which of the call's two actions it offers.
struct TodayConsoleModel: Equatable {
    enum Note: Equatable {
        /// Before the start: Crenel offers to record when the call begins.
        case willAsk
        /// The meeting runs and nothing is being recorded.
        case notRecorded
        case meetWaiting
        case meetUnavailable
    }

    let note: Note
    let canRecord: Bool
    let canJoin: Bool

    /// nil when the console stays closed: the event is further than 10 minutes away and
    /// no Meet call is waiting for its bridge.
    init?(focus: Meeting?, now: Date, bridge: TodayMeetBridge) {
        let near = focus.map { $0.startDate.timeIntervalSince(now) <= 10 * 60 && $0.endDate > now } ?? false
        let callLike = focus.map { $0.isMeetingLike || $0.meetingURL != nil } ?? false
        let hasFocusConsole = near && callLike
        guard hasFocusConsole || bridge != .none else { return nil }
        switch bridge {
        case .waiting: note = .meetWaiting
        case .unavailable: note = .meetUnavailable
        case .none: note = (focus?.startDate ?? now) <= now ? .notRecorded : .willAsk
        }
        canRecord = bridge != .unavailable
        canJoin = hasFocusConsole && focus?.meetingURL != nil
    }
}

/// The console (`.console`): state on the left, Record ⌘R and Join ⌘J on the right.
private struct TodayConsole: View {
    let model: TodayConsoleModel
    let onRecord: () -> Void
    let onJoin: (() -> Void)?

    var body: some View {
        HudConsole {
            switch model.note {
            case .willAsk:
                HudLamp(.teal)
                Text("Crenel will ask to record when it starts")
            case .notRecorded:
                HudLamp(.off)
                Text("Not being recorded")
            case .meetWaiting:
                HudStatusShape(.warn, loop: .blink)
                Text("Click Crenel in the Meet tab")
            case .meetUnavailable:
                HudStatusShape(.err)
                Text("Meet audio bridge unavailable")
            }
        } buttons: {
            if model.canRecord {
                HudButton("Record", lamp: .red, key: "⌘R", size: .small, action: onRecord)
                    .hudShortcut("r")
                    .accessibilityLabel("Record")
            }
            if model.canJoin, let onJoin {
                HudButton("Join", key: "⌘J", kind: .primary, size: .small, action: onJoin)
                    .hudShortcut("j")
                    .accessibilityLabel("Join")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Row

/// An event in the row language of Recordings: the day tile (with an amber lamp only for
/// an invite waiting for an answer), the title, and when · where under it; the length at
/// the trailing edge, which Join replaces while the row is hovered.
private struct TodayEventRow: View {
    let event: Meeting
    let now: Date
    var isHovered = false
    var onJoin: (() -> Void)?

    private var isToday: Bool {
        Calendar.current.isDate(event.startDate, inSameDayAs: now) || event.startDate <= now
    }
    private var isDimmed: Bool { event.isSuggestion || event.responseStatus == .tentative }
    private var isPending: Bool { event.responseStatus == .pending }
    /// The row's own hover, so Join follows the pointer at once.
    @State private var hovering = false
    private var hovered: Bool { isHovered || hovering }
    private var showsJoin: Bool { hovered && onJoin != nil }

    var body: some View {
        HStack(alignment: .center, spacing: Hud.Row.gap) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).hud(.body).lineLimit(1).truncationMode(.tail)
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let length {
                Text(verbatim: length)
                    .hud(.meta, Hud.Ink.ink2)
                    .monospacedDigit()
                    .fixedSize()
                    .opacity(showsJoin ? 0 : 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Hud.Row.inset)
        .padding(.vertical, RecordingRow.verticalPadding)
        .contentShape(Rectangle())
        .opacity(isDimmed ? 0.55 : 1)
        .overlay(alignment: .trailing) {
            // Over the row, not in it: the row keeps its height and nothing shifts.
            if let onJoin {
                TodayHoverJoin(shown: hovered, action: onJoin)
                    .padding(.trailing, 6)
            }
        }
        .onHover { hovering = $0 }
    }

    /// Today: just the start time (or "All day"). Other days: the date and weekday.
    @ViewBuilder private var tile: some View {
        let lamp: Hud.LampColor? = isPending ? .amber : nil
        if isToday {
            if event.isAllDay {
                HudDateTile(allDay: now, lamp: lamp)
            } else {
                HudDateTile(time: event.startDate, lamp: lamp)
            }
        } else {
            HudDateTile(date: event.isAllDay ? max(event.startDate, now) : event.startDate, caption: .weekday, lamp: lamp)
        }
    }

    /// Today the tile already says when, so the line starts with the place.
    @ViewBuilder private var metaLine: some View {
        let parts = (isToday ? [] : [when]) + [place].compactMap { $0 }
        if !parts.isEmpty || isPending {
        HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Text(verbatim: "·").foregroundStyle(Hud.Ink.ink5) }
                Text(verbatim: part).monospacedDigit()
            }
            if isPending {
                if !parts.isEmpty { Text(verbatim: "·").foregroundStyle(Hud.Ink.ink5) }
                HStack(spacing: 5) {
                    HudStatusShape(.warn).scaleEffect(0.8)
                    Text("Invite").foregroundStyle(Hud.Ink.signal)
                }
                .help("Invite, waiting for your answer")
            }
        }
        .hud(.meta)
        .lineLimit(1)
        }
    }

    /// "18:30", or "All day".
    private var when: String {
        event.isAllDay ? String(localized: "All day") : HudFormat.clock(event.startDate)
    }

    /// The call service or place for timed events; the calendar for all-day ones.
    private var place: String? {
        let word = event.isAllDay ? event.calendarTitle : event.venueWord
        return word?.isEmpty == false ? word : nil
    }

    /// "45m", "1h 30m"; none for all-day events.
    private var length: String? {
        guard !event.isAllDay, event.endDate > event.startDate else { return nil }
        return RecordingsFormat.length(event.endDate.timeIntervalSince(event.startDate))
    }
}

// MARK: - Empty states
/// One instrument at rest, one sentence, one fix at the trailing edge.
private struct TodayEmptyState: View {
    let state: TodayCalendarState
    let onConnect: () -> Void
    let fixes: TodayCalendarFixes
    var onRecord: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HudRestingGauge(status: gaugeStatus)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).hud(.title)
                if let detail {
                    Text(verbatim: detail).hud(.meta).fixedSize(horizontal: false, vertical: true)
                }
                if state == .waiting {
                    HStack(spacing: 8) {
                        HudStatusShape(.warn, loop: .blink)
                        Text("System dialog is open").hud(.meta)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            fix
            if let onRecord {
                TodayRecordButton(action: onRecord)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var gaugeStatus: HudStatus? {
        switch state {
        case .failed: .err
        case .accessOff: .off
        default: nil
        }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .off: "Calendar is off"
        case .connect: "Your calendar isn’t connected"
        case .waiting: "Waiting for calendar access"
        case .accessOff: "Calendar access is off"
        case .failed: "Couldn’t refresh calendars"
        case .reading: "Reading calendars"
        case .noCalendars: "No calendars on this Mac"
        case .ready: "Nothing else today"
        }
    }

    private var detail: String? {
        switch state {
        case .connect, .accessOff, .waiting:
            String(localized: "Meetings and their countdown appear here.")
        case .failed(let lastRefresh):
            lastRefresh.map { "Showing what was there at \(HudFormat.clock($0))." }
        case .noCalendars:
            String(localized: "Add an account in Internet Accounts.")
        case .off, .reading, .ready:
            nil
        }
    }

    @ViewBuilder
    private var fix: some View {
        switch state {
        case .connect:
            HudButton("Connect", key: "↩", kind: .primary, size: .small, action: onConnect)
                .hudShortcut(.defaultAction)
        case .accessOff:
            HudButton("Privacy settings", glyph: .link, size: .small, action: fixes.openPrivacySettings)
        case .failed:
            HudButton("Try again", size: .small, action: fixes.retry)
        case .off:
            HudButton("Turn on", size: .small, action: fixes.turnOn)
        case .noCalendars:
            HudButton("Accounts", glyph: .link, size: .small, action: fixes.openAccounts)
        case .reading:
            // Nothing to fix: the working shape sits where the fix would.
            HudBusy().padding(.trailing, 10)
        case .waiting, .ready:
            EmptyView()
        }
    }
}

// MARK: - Kind

/// What kind of event this is: a call, a place, or a plain calendar entry.
struct MeetingKindIcon: View {
    let meeting: Meeting
    var tint: Color = Hud.Ink.text3

    var body: some View {
        Group {
            if meeting.meetingURL != nil {
                HudIcon(.video)
            } else if meeting.location?.isEmpty == false {
                HudIcon(.place)
            } else {
                HudIcon(.calendar)
            }
        }
        .foregroundStyle(tint)
    }
}

extension Meeting {
    /// The shortest word for where it happens: the call service, or the place.
    var venueWord: String? {
        if let host = meetingURL?.host()?.lowercased() {
            if host.contains("meet.google") { return "Google Meet" }
            if host.contains("zoom") { return "Zoom" }
            if host.contains("teams") { return "Teams" }
            if host.contains("webex") { return "Webex" }
            if host.contains("whereby") { return "Whereby" }
            if host.contains("facetime") || host.contains("apple.com") { return "FaceTime" }
            return host.replacingOccurrences(of: "www.", with: "")
        }
        if let location, !location.isEmpty, !location.contains("://") { return location }
        return calendarTitle
    }
}

extension Color {
    /// "#RRGGBB" calendar colours from EventKit.
    init?(crenelHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
