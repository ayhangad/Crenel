import SwiftUI

// MARK: - Shared page pieces

/// Sections of a page drift in 28 ms apart when the page opens (`[data-stagger]`).
private struct DesktopEnter: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.desktopFixedNow) private var fixedNow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .hudStagger(index, shown: shown || fixedNow != nil, reduceMotion: reduceMotion)
            .onAppear { shown = true }
    }
}

extension View {
    func desktopEnter(_ index: Int) -> some View { modifier(DesktopEnter(index: index)) }
}

/// Where a stored recording stands, as the lists print it.
enum DesktopMeetingState: Equatable {
    case ready, processing, failed, transcriptOnly, notTranscribed

    @MainActor
    static func resolve(_ meeting: StoredMeeting, jobs: [ProcessingJob]) -> DesktopMeetingState {
        if jobs.contains(where: { $0.meetingID == meeting.id && $0.state != .failed }) { return .processing }
        switch meeting.processingStatus {
        case .failed: return .failed
        case .processing: return .processing
        case .recorded: return .notTranscribed
        case .completed: return meeting.summaryNeedsAttention == true ? .transcriptOnly : .ready
        }
    }
}

// MARK: - Today

/// The dashboard: the next meeting as a big gauge, the day as a labelled ruler, three
/// instrument tiles, recent meetings.
struct DesktopTodayPage: View {
    let actions: DesktopActions
    @ObservedObject var navigation: DesktopNavigation
    @ObservedObject var preferences: DesktopPreferencesModel
    @ObservedObject var index: DesktopMeetingIndex
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    @Environment(\.desktopFixedNow) private var fixedNow
    @State private var hoveredRecent: AnyHashable?
    @State private var copiedLink = false
    @Namespace private var recentSpace

    var body: some View {
        DesktopClock { now in
            VStack(spacing: 0) {
                DesktopToolbar(title: "Today", meta: DesktopFormat.longDay(now)) {
                    HudButton("Task", glyph: .plus, key: "⌘N", size: .small) { navigation.section = .tasks }
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityLabel("New task")
                    HudButton("Record", lamp: .red, key: "⌘R", size: .small, action: actions.startRecording)
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(appState.requiresTerminationConfirmation)
                }
                ScrollView {
                    VStack(spacing: Hud.Layout.block) {
                        hero(now: now).desktopEnter(0)
                        HStack(alignment: .top, spacing: Hud.Layout.block) {
                            tasksTile(now: now)
                            tapeTile(now: now)
                            dictationTile(now: now)
                        }
                        .desktopEnter(1)
                        recent(now: now).desktopEnter(2)
                    }
                    .padding(.horizontal, DesktopPageLayout.gutter)
                    .padding(.bottom, DesktopPageLayout.gutter)
                }
                .scrollIndicators(.never)
            }
        }
    }

    // MARK: Hero

    private func hero(now: Date) -> some View {
        let status = NotchAgendaStatus.resolve(items: appState.upcomingMeetings, now: now, horizon: 24 * 3_600)
        return VStack(spacing: 0) {
            HStack(spacing: Hud.Layout.section) {
                if let status {
                    heroGauge(status)
                    heroText(status, now: now)
                    heroActions(status)
                } else {
                    restingHero
                }
            }
            HudDayRuler(span: rulerSpan(now: now), now: DesktopFormat.decimalHour(now), events: rulerEvents(now: now, focus: status), wide: true)
                .padding(.top, DesktopPageLayout.gaugeToRuler)
        }
        .padding(.horizontal, Hud.Layout.edge)
        .padding(.top, Hud.Layout.edge - DesktopPageLayout.gaugeTop)
        .padding(.bottom, Hud.Layout.edge - DesktopPageLayout.rulerFoot)
        .hudPanel()
    }

    private func heroGauge(_ status: NotchAgendaStatus) -> some View {
        let ignite = fixedNow == nil
        return Group {
            switch status.phase {
            case .upcoming(let startsIn):
                let minutes = max(1, Int((startsIn / 60).rounded(.up)))
                let tint = minutes <= 2 ? Hud.Ink.live : (minutes <= 10 ? Hud.Ink.signal : Hud.Ink.ink1)
                HudGauge(value: min(1, Double(minutes) / 60), size: DesktopPageLayout.gauge, tint: Hud.Ink.ink1, zones: HudGaugeZone.countdown,
                         labels: ["0", "15", "30", "45", "60"], ignite: ignite) {
                    if minutes <= 99 {
                        HudSegmentDigits("\(minutes)", height: 36, cells: 2, color: tint)
                        Text("min").hud(.micro, Hud.Ink.ink3)
                    } else {
                        HudSegmentDigits(DesktopFormat.clock(status.item.startDate), height: 20)
                        Text("starts").hud(.micro, Hud.Ink.ink3)
                    }
                }
            case .ongoing(let remaining):
                let length = max(60, status.item.endDate.timeIntervalSince(status.item.startDate))
                let minutes = max(1, Int((remaining / 60).rounded(.up)))
                HudGauge(value: min(1, max(0, remaining / length)), size: DesktopPageLayout.gauge, tint: Hud.Ink.signal, zones: HudGaugeZone.redline, ignite: ignite) {
                    if minutes <= 99 {
                        HudSegmentDigits("\(minutes)", height: 36, cells: 2, color: Hud.Ink.signal)
                        Text("left").hud(.micro, Hud.Ink.ink3)
                    } else {
                        HudSegmentDigits(DesktopFormat.clock(status.item.endDate), height: 20, color: Hud.Ink.signal)
                        Text("ends").hud(.micro, Hud.Ink.ink3)
                    }
                }
            }
        }
        .frame(width: DesktopPageLayout.gauge, height: DesktopPageLayout.gauge)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: NotchAgendaFormatter.accessibilityText(for: status)))
    }

    private func heroText(_ status: NotchAgendaStatus, now: Date) -> some View {
        let item = status.item
        return VStack(alignment: .leading, spacing: Hud.Layout.pair) {
            Text(status.phase.isOngoing ? "Happening now" : (item.isMeetingLike ? "Next meeting" : "Next event")).hudTrimmed(.meta)
            Text(verbatim: item.title).hudTrimmed(.page).truncationMode(.tail)
            HStack(spacing: 8) {
                Text(verbatim: status.phase.isOngoing ? "Until \(DesktopFormat.clock(item.endDate))" : startText(item, now: now))
                    .hudTrimmed(.label, Hud.Ink.ink2)
                if let venue = DesktopFormat.venue(item) {
                    Text(verbatim: "·").hudTrimmed(.label, Hud.Ink.ink4)
                    HudIcon(DesktopFormat.venueGlyph(item), size: 12).foregroundStyle(Hud.Ink.ink3).padding(.vertical, -2)
                    Text(verbatim: venue).hudTrimmed(.label, Hud.Ink.ink2)
                }
            }
            // The last line is its own block: who, or what waits for you.
            Group {
                if item.responseStatus == .pending {
                    HStack(spacing: 12) {
                        HudLamp(.amber).frame(width: 13)
                        Text("Invite, waiting for your answer").hudTrimmed(.meta)
                    }
                } else if let people = MeetingPeopleFormatter.short(item.attendees) {
                    HStack(spacing: 10) {
                        HudFaces(initials: MeetingPeopleFormatter.initials(item.attendees))
                        Text(verbatim: people).hudTrimmed(.meta).truncationMode(.tail)
                    }
                } else if let calendar = item.calendarTitle, DesktopFormat.venue(item) != calendar {
                    Text(verbatim: calendar).hudTrimmed(.meta)
                }
            }
            .padding(.top, Hud.Layout.block - Hud.Layout.pair)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startText(_ item: Meeting, now: Date) -> String {
        let clock = DesktopFormat.clock(item.startDate)
        return Calendar.current.isDate(item.startDate, inSameDayAs: now) ? clock : "\(DesktopFormat.weekday(item.startDate)) \(clock)"
    }

    private func heroActions(_ status: NotchAgendaStatus) -> some View {
        let item = status.item
        let joinOpens = item.startDate.addingTimeInterval(-NotchAgendaStatus.defaultHandoff)
        let canJoin: Bool = {
            guard item.meetingURL != nil else { return false }
            if case .upcoming(let startsIn) = status.phase { return startsIn <= NotchAgendaStatus.defaultHandoff }
            return true
        }()
        return VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 12) {
                if canJoin {
                    HudLamp(.amber).frame(width: 13)
                    Text(status.phase.isOngoing ? "In progress" : "Starting soon").hudTrimmed(.meta)
                } else if item.meetingURL != nil {
                    HudLamp(.off).frame(width: 13)
                    Text(verbatim: "Join opens at \(DesktopFormat.clock(joinOpens))").hudTrimmed(.meta)
                }
            }
            .padding(.top, DesktopPageLayout.gaugeTop)
            Spacer(minLength: Hud.Layout.block)
            HStack(spacing: 8) {
                if let url = item.meetingURL {
                    HudButton(copiedLink ? "Copied" : "Copy link", glyph: .copy, size: .small) {
                        actions.copyText(url.absoluteString)
                        copiedLink = true
                    }
                }
                HudButton("Calendar", glyph: .calendar, size: .small) { crenelActions.openInCalendar(item) }
                if canJoin, let url = item.meetingURL {
                    HudButton("Join", key: "⌘J", kind: .primary, size: .small) { actions.openMeetingURL(url) }
                        .keyboardShortcut("j", modifiers: .command)
                }
            }
        }
        // The buttons end where the gauge's ink ends, not its open-bottomed box.
        .frame(height: DesktopPageLayout.gauge - DesktopPageLayout.gaugeFoot)
        .frame(height: DesktopPageLayout.gauge, alignment: .top)
        .task(id: copiedLink) {
            guard copiedLink else { return }
            try? await Task.sleep(for: .seconds(1.6))
            copiedLink = false
        }
    }

    /// Nothing coming up: a resting gauge, one sentence, one fix at the trailing edge.
    @ViewBuilder private var restingHero: some View {
        let access = appState.calendarAccessState
        let status: HudStatus? = {
            guard appState.isCalendarEnabled else { return nil }
            switch access {
            case .denied, .restricted: return .off
            case .failed: return .err
            default: return nil
            }
        }()
        HudRestingGauge(status: status, size: DesktopPageLayout.gauge)
            .frame(width: DesktopPageLayout.gauge, height: DesktopPageLayout.gauge)
        VStack(alignment: .leading, spacing: Hud.Layout.pair) {
            Text("Next meeting").hudTrimmed(.meta)
            switch status {
            case .off:
                Text("Calendar access is off").hudTrimmed(.page)
                Text("Allow Calendar in System Settings to see what’s next.").hudTrimmed(.label, Hud.Ink.ink2)
            case .err:
                Text("Calendar can’t refresh").hudTrimmed(.page)
                Text("Your events will be back once Calendar answers.").hudTrimmed(.label, Hud.Ink.ink2)
            default:
                if !appState.isCalendarEnabled || access == .notDetermined {
                    Text("Calendar isn’t connected").hudTrimmed(.page)
                    Text("Connect Apple Calendar to see the next meeting here.").hudTrimmed(.label, Hud.Ink.ink2)
                } else {
                    Text("Nothing coming up").hudTrimmed(.page)
                    Text("The rest of the day is clear.").hudTrimmed(.label, Hud.Ink.ink2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if status != nil || !appState.isCalendarEnabled || access == .notDetermined {
            HudButton("Calendar settings", glyph: .sliders, size: .small) {
                navigation.settingsCategory = .calendar
                navigation.section = .settings
            }
        }
    }

    // MARK: Ruler

    private func todaysEvents(now: Date) -> [Meeting] {
        appState.upcomingMeetings.filter { !$0.isAllDay && Calendar.current.isDate($0.startDate, inSameDayAs: now) && $0.endDate > $0.startDate }
    }

    private func rulerSpan(now: Date) -> ClosedRange<Double> {
        let hours = todaysEvents(now: now).flatMap { [DesktopFormat.decimalHour($0.startDate), min(24, DesktopFormat.decimalHour($0.startDate) + $0.endDate.timeIntervalSince($0.startDate) / 3_600)] }
            + [DesktopFormat.decimalHour(now)]
        let lower = min(8, (hours.min() ?? 8).rounded(.down)), upper = max(20, (hours.max() ?? 20).rounded(.up))
        return lower...upper
    }

    private func rulerEvents(now: Date, focus: NotchAgendaStatus?) -> [HudDayRuler.Event] {
        todaysEvents(now: now).map { event in
            let start = DesktopFormat.decimalHour(event.startDate)
            let end = min(24, start + event.endDate.timeIntervalSince(event.startDate) / 3_600)
            let kind: HudDayRuler.Event.Kind
            if event.id == focus?.item.id {
                kind = focus?.urgency == .calm && focus?.phase.isOngoing != true ? .focus : .amber
            } else if event.responseStatus == .pending {
                kind = .invite
            } else {
                kind = event.isMeetingLike ? .normal : .dim
            }
            return HudDayRuler.Event(start, end, kind, title: event.title)
        }
    }

    // MARK: Tiles

    private func tile<Header: View, Content: View>(_ glyph: HudGlyph, _ title: LocalizedStringKey, help: LocalizedStringKey,
                                                    action: @escaping () -> Void,
                                                    @ViewBuilder header: @escaping () -> Header,
                                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        DesktopTile(help: help, action: action) {
            VStack(alignment: .leading, spacing: Hud.Layout.block) {
                HStack(spacing: 8) {
                    HudIcon(glyph, size: 14).foregroundStyle(Hud.Ink.ink3).padding(-DesktopPageLayout.smallGlyphInset)
                    Text(title).hudTrimmed(.label, Hud.Ink.ink2)
                    Spacer(minLength: 4)
                    header().desktopInline()
                }
                // The tile's own blocks (readout, spacer, rows) keep their own gaps.
                VStack(alignment: .leading, spacing: 0) { content() }
            }
        }
    }

    private func tasksTile(now: Date) -> some View {
        let presentation = appState.taskPresentation(now: now)
        let done = presentation.sections.first { $0.kind == .completedToday }?.tasks.count ?? 0
        let underWay = presentation.sections.first { $0.kind == .inProgress }?.tasks.count ?? 0
        let rows = presentation.sections.filter { $0.kind != .completedToday }.flatMap { section in section.tasks.map { (section.kind, $0) } }.prefix(3)
        let total = min(12, done + presentation.activeCount)
        return tile(.queue, "Tasks", help: "Open Tasks", action: { navigation.section = .tasks }) {
            if total > 0 {
                HudCapsules(done: min(done, total), underWay: min(underWay, total - min(done, total)), total: total)
                    .help("\(done) done · \(underWay) under way · \(max(0, presentation.activeCount - underWay)) to do")
            }
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HudSegmentDigits("\(presentation.activeCount)", height: 30)
                Text("open").hud(.unit)
            }
            Spacer(minLength: 8)
            if rows.isEmpty {
                Text(presentation.activeCount == 0 && done > 0 ? "Everything is done for today." : "Nothing on the list yet.").hudTrimmed(.meta)
            } else {
                // No slab here (the whole tile is the button), so rows stand `item` apart.
                VStack(alignment: .leading, spacing: DesktopPageLayout.tileItem) {
                    ForEach(Array(rows), id: \.1.id) { kind, task in
                        HStack(spacing: 12) {
                            HudStateMark(state: task.status, size: 14).padding(-DesktopPageLayout.smallGlyphInset)
                            Text(verbatim: task.title).hudTrimmed(.label, task.status == .inProgress ? Hud.Ink.ink1 : Hud.Ink.ink2)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            taskTrailing(task, kind: kind, now: now).desktopInline()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func taskTrailing(_ task: TaskItem, kind: TaskListPresentation.SectionKind, now: Date) -> some View {
        if task.status == .inProgress, let startedAt = task.startedAt {
            let minutes = max(0, Int(now.timeIntervalSince(startedAt) / 60))
            if minutes < 600 {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    HudSegmentDigits("\(minutes)", height: 9, color: Hud.Ink.signal)
                    Text("min").font(Hud.font(10, .medium)).foregroundStyle(Hud.Ink.signal.opacity(0.7))
                }
            }
        } else if let label = TaskDueFormatter.label(for: task, now: now) {
            Text(verbatim: label.hasPrefix("Today ") ? String(label.dropFirst(6)) : label)
                .hudTrimmed(.meta, kind == .overdue ? Hud.Ink.live : Hud.Ink.ink3).fixedSize()
        }
    }

    private func tapeTile(now: Date) -> some View {
        let week = DesktopStats.week(meetings: appState.storedMeetings, now: now)
        let total = week.reduce(0) { $0 + $1.seconds }
        return tile(.tape, "On tape", help: "Open Meetings", action: { navigation.section = .meetings }) {
            Text("this week").hudTrimmed(.meta)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HudSegmentDigits(DesktopFormat.hoursMinutes(total), height: 30)
                Text("h").hud(.unit)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week, id: \.date) { day in
                    VStack(spacing: Hud.Layout.pair) {
                        HudLEDStack(lit: DesktopStats.stackCells(day.seconds, week: week), tone: day.isToday ? .today : .past)
                        Text(verbatim: day.label).hudTrimmed(.micro, day.isToday ? Hud.Ink.ink1 : Hud.Ink.ink4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(DesktopFormat.minutes(total)) recorded this week"))
        }
    }

    private func dictationTile(now: Date) -> some View {
        let today = DesktopStats.dictationToday(appState.dictationHistory, now: now)
        let usual = DesktopStats.usualDictationWords(appState.dictationDailyWords, now: now)
            ?? DesktopStats.usualDictationWords(appState.dictationHistory, now: now)
        let scale = DesktopStats.dictationScale(todayWords: today.words, usual: usual)
        let last = appState.dictationHistory.first
        return tile(.waveform, "Dictation", help: "Open Dictation", action: { navigation.section = .dictation }) {
            Text("today").hudTrimmed(.meta)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HudSegmentDigits("\(today.words)", height: 30)
                Text("words").hud(.unit)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: Hud.Layout.block) {
                // Today against your usual day (the triangle); a plain scale until there is one.
                HudDotMatrix(value: scale.value, count: 78, mark: scale.mark)
                    .help(usual.map { "Your usual day: \(Int($0.rounded())) words" } ?? "")
                if let last {
                    Text(verbatim: "“\(last.finalText)”" + (last.appName.map { " · \($0)" } ?? ""))
                        .hudTrimmed(.meta).truncationMode(.tail)
                } else {
                    Text(verbatim: "Hold \(preferences.keyPhrase) and speak to dictate.").hudTrimmed(.meta)
                }
            }
        }
    }

    // MARK: Recent meetings

    private func recent(now: Date) -> some View {
        let meetings = Array(appState.storedMeetings.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: "Recent meetings") {
                HudButton("All meetings", trailingGlyph: .chevronRight, size: .mini) { navigation.section = .meetings }
                    .desktopInline()
            }
            .padding(.top, Hud.Layout.rowPad)
            if meetings.isEmpty {
                HStack(spacing: 12) {
                    Text("No recordings yet").hudTrimmed(.body, Hud.Ink.ink2)
                    Text("Crenel offers to record when a call starts.").hudTrimmed(.meta)
                    Spacer(minLength: 0)
                }
                .hudRow(.icon)
            } else {
                ForEach(meetings) { meeting in
                    Button {
                        navigation.selectedMeeting = meeting.id
                        navigation.section = .meetings
                    } label: {
                        HStack(alignment: .center, spacing: Hud.Row.gap) {
                            DesktopTimeColumn(DesktopFormat.clock(meeting.startedAt), DesktopFormat.runLength(meeting.duration))
                            VStack(alignment: .leading, spacing: Hud.Layout.pair) {
                                Text(verbatim: meeting.title).hudTrimmed(.body).truncationMode(.tail)
                                Text(verbatim: recentMeta(meeting, now: now)).hudTrimmed(.meta).truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            DesktopMeetingStatusWord(state: DesktopMeetingState.resolve(meeting, jobs: appState.processingJobs))
                        }
                        .hudRow(.icon)
                        .contentShape(Rectangle())
                        .hudGlide(meeting.id, hovered: $hoveredRecent, in: recentSpace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // The list sits `rowPad` inside the card; rows add theirs, so text is `edge` in.
        .padding(Hud.Layout.edge - Hud.Layout.rowPad)
        .hudPanel()
    }

    private func recentMeta(_ meeting: StoredMeeting, now: Date) -> String {
        var parts: [String] = []
        if !Calendar.current.isDate(meeting.startedAt, inSameDayAs: now) {
            parts.append(DesktopFormat.dayGroup(meeting.startedAt, now: now))
        }
        if let entry = index.entries[meeting.id] {
            if entry.actionCount > 0 { parts.append("\(entry.actionCount) for you to do") }
            if !entry.speakers.isEmpty { parts.append(entry.speakers.prefix(3).joined(separator: ", ")) }
        }
        if parts.isEmpty, let source = meeting.sourceMeeting, let venue = DesktopFormat.venue(source) { parts.append(venue) }
        return parts.isEmpty ? DesktopFormat.minutes(meeting.duration) : parts.joined(separator: " · ")
    }
}

/// A status word for a recording: lamp when calm, shape when it needs attention.
struct DesktopMeetingStatusWord: View {
    let state: DesktopMeetingState

    var body: some View {
        switch state {
        case .ready:
            HudStatusWord(.ok, "Notes ready").font(Hud.font(11.5, .medium)).desktopInline()
        case .processing:
            HStack(spacing: 8) {
                HudBusy().desktopInline()
                Text("Processing").hudTrimmed(.meta, Hud.Ink.ink2)
            }
        case .failed:
            HStack(spacing: 8) {
                HudStatusShape(.err).desktopInline()
                Text("Failed").hudTrimmed(.meta, Hud.Ink.ink2)
            }
        case .transcriptOnly:
            HStack(spacing: 8) {
                HudStatusShape(.warn).desktopInline()
                Text("Transcript only").hudTrimmed(.meta, Hud.Ink.ink2)
            }
        case .notTranscribed:
            HStack(spacing: 8) {
                HudStatusShape(.wait).desktopInline()
                Text("Not transcribed").hudTrimmed(.meta, Hud.Ink.ink2)
            }
        }
    }
}

/// Page geometry of the desktop dashboard pages, in visible gaps (measure model).
enum DesktopPageLayout {
    /// Window floor → page content, beside and under the cards.
    static let gutter: CGFloat = Hud.Space.x6
    /// The big gauge of the Today hero.
    static let gauge: CGFloat = 148
    /// The 270° gauge is open at the bottom: its lowest ink (the ends of the arc) sits
    /// 16 % above its box (measured on the render).
    static let gaugeFootRatio: CGFloat = 0.16
    static let gaugeFoot: CGFloat = gauge * gaugeFootRatio
    /// Its top tick sits a hair inside the box.
    static let gaugeTop: CGFloat = 1
    /// The wide ruler's box has this much above its event bars and under its hour labels.
    static let rulerHead: CGFloat = 6.2
    static let rulerFoot: CGFloat = 4.4
    /// Gauge ink → ruler ink: `Hud.Layout.block`.
    static let gaugeToRuler: CGFloat = Hud.Layout.block - gaugeFoot - rulerHead
    /// A 14 pt glyph's ink starts this far inside its box (16 pt → 1.5).
    static let smallGlyphInset: CGFloat = 14 * Hud.Layout.glyphInset / 16
    /// Rows without a slab in an instrument tile: `Hud.Layout.item` between inks.
    static let tileItem: CGFloat = Hud.Layout.item
}

/// An instrument tile (`.tile`): a panel that lifts on hover and opens its page.
private struct DesktopTile<Content: View>: View {
    let help: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(Hud.Layout.edge)
                .frame(maxWidth: .infinity, minHeight: 196, maxHeight: 196, alignment: .topLeading)
                .hudPanel(isHovering: isHovering)
                .contentShape(RoundedRectangle(cornerRadius: Hud.Radius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.toggle, value: isHovering)
        .help(help)
    }
}
