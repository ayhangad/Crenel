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
                    VStack(spacing: 16) {
                        hero(now: now).desktopEnter(0)
                        HStack(alignment: .top, spacing: 16) {
                            tasksTile(now: now)
                            tapeTile(now: now)
                            dictationTile(now: now)
                        }
                        .desktopEnter(1)
                        recent(now: now).desktopEnter(2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
    }

    // MARK: Hero

    private func hero(now: Date) -> some View {
        let status = NotchAgendaStatus.resolve(items: appState.upcomingMeetings, now: now, horizon: 24 * 3_600)
        return VStack(spacing: 0) {
            HStack(spacing: 28) {
                if let status {
                    heroGauge(status)
                    heroText(status, now: now)
                    heroActions(status)
                } else {
                    restingHero
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            HudDayRuler(span: rulerSpan(now: now), now: DesktopFormat.decimalHour(now), events: rulerEvents(now: now, focus: status), wide: true)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
        .hudPanel()
    }

    private func heroGauge(_ status: NotchAgendaStatus) -> some View {
        let ignite = fixedNow == nil
        return Group {
            switch status.phase {
            case .upcoming(let startsIn):
                let minutes = max(1, Int((startsIn / 60).rounded(.up)))
                let tint = minutes <= 2 ? Hud.Ink.live : (minutes <= 10 ? Hud.Ink.signal : Hud.Ink.ink1)
                HudGauge(value: min(1, Double(minutes) / 60), size: 148, tint: Hud.Ink.ink1, zones: HudGaugeZone.countdown,
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
                HudGauge(value: min(1, max(0, remaining / length)), size: 148, tint: Hud.Ink.signal, zones: HudGaugeZone.redline, ignite: ignite) {
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
        .frame(width: 148, height: 148)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: NotchAgendaFormatter.accessibilityText(for: status)))
    }

    private func heroText(_ status: NotchAgendaStatus, now: Date) -> some View {
        let item = status.item
        return VStack(alignment: .leading, spacing: 8) {
            Text(status.phase.isOngoing ? "Happening now" : (item.isMeetingLike ? "Next meeting" : "Next event")).hud(.meta)
            Text(verbatim: item.title).hud(.page).lineLimit(1).truncationMode(.tail)
            HStack(spacing: 8) {
                Text(verbatim: status.phase.isOngoing ? "Until \(DesktopFormat.clock(item.endDate))" : startText(item, now: now))
                if let venue = DesktopFormat.venue(item) {
                    Text(verbatim: "·").foregroundStyle(Hud.Ink.ink4)
                    HudIcon(DesktopFormat.venueGlyph(item), size: 12).foregroundStyle(Hud.Ink.ink3)
                    Text(verbatim: venue).lineLimit(1)
                }
            }
            .hud(.label, Hud.Ink.ink2)
            .padding(.top, 2)
            if item.responseStatus == .pending {
                HStack(spacing: 8) {
                    HudLamp(.amber)
                    Text("Invite — waiting for your answer").hud(.meta)
                }
                .padding(.top, 8)
            } else if let people = MeetingPeopleFormatter.short(item.attendees) {
                HStack(spacing: 10) {
                    HudFaces(initials: MeetingPeopleFormatter.initials(item.attendees))
                    Text(verbatim: people).hud(.meta).lineLimit(1).truncationMode(.tail)
                }
                .padding(.top, 8)
            } else if let calendar = item.calendarTitle, DesktopFormat.venue(item) != calendar {
                Text(verbatim: calendar).hud(.meta).lineLimit(1).padding(.top, 8)
            }
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
            HStack(spacing: 8) {
                if canJoin {
                    HudLamp(.amber)
                    Text(status.phase.isOngoing ? "In progress" : "Starting soon").hud(.meta)
                } else if item.meetingURL != nil {
                    HudLamp(.off)
                    Text(verbatim: "Join opens at \(DesktopFormat.clock(joinOpens))").hud(.meta)
                }
            }
            Spacer(minLength: 12)
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
        .padding(.vertical, 6)
        .frame(height: 148)
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
        HudRestingGauge(status: status, size: 148)
            .frame(width: 148, height: 148)
        VStack(alignment: .leading, spacing: 8) {
            Text("Next meeting").hud(.meta)
            switch status {
            case .off:
                Text("Calendar access is off").hud(.page).lineLimit(1)
                Text("Allow Calendar in System Settings to see what’s next.").hud(.label, Hud.Ink.ink2)
            case .err:
                Text("Calendar can’t refresh").hud(.page).lineLimit(1)
                Text("Your events will be back once Calendar answers.").hud(.label, Hud.Ink.ink2)
            default:
                if !appState.isCalendarEnabled || access == .notDetermined {
                    Text("Calendar isn’t connected").hud(.page).lineLimit(1)
                    Text("Connect Apple Calendar to see the next meeting here.").hud(.label, Hud.Ink.ink2)
                } else {
                    Text("Nothing coming up").hud(.page).lineLimit(1)
                    Text("The rest of the day is clear.").hud(.label, Hud.Ink.ink2)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    HudIcon(glyph, size: 14).foregroundStyle(Hud.Ink.ink3)
                    Text(title).hud(.label, Hud.Ink.ink2)
                    Spacer(minLength: 4)
                    header()
                }
                content()
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
                Text(presentation.activeCount == 0 && done > 0 ? "Everything is done for today." : "Nothing on the list yet.").hud(.meta)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rows), id: \.1.id) { kind, task in
                        HStack(spacing: 10) {
                            HudStateMark(state: task.status, size: 14)
                            Text(verbatim: task.title).hud(.label, task.status == .inProgress ? Hud.Ink.ink1 : Hud.Ink.ink2)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 4)
                            taskTrailing(task, kind: kind, now: now)
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
                .hud(.meta, kind == .overdue ? Hud.Ink.live : Hud.Ink.ink3).lineLimit(1).fixedSize()
        }
    }

    private func tapeTile(now: Date) -> some View {
        let week = DesktopStats.week(meetings: appState.storedMeetings, now: now)
        let total = week.reduce(0) { $0 + $1.seconds }
        return tile(.tape, "On tape", help: "Open Meetings", action: { navigation.section = .meetings }) {
            Text("this week").hud(.meta)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HudSegmentDigits(DesktopFormat.hoursMinutes(total), height: 30)
                Text("h").hud(.unit)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week, id: \.date) { day in
                    VStack(spacing: 8) {
                        HudLEDStack(lit: DesktopStats.stackCells(day.seconds, week: week), tone: day.isToday ? .today : .past)
                        Text(verbatim: day.label).hud(.micro, day.isToday ? Hud.Ink.ink1 : Hud.Ink.ink4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(DesktopFormat.minutes(total)) recorded this week"))
        }
    }

    private func dictationTile(now: Date) -> some View {
        let today = DesktopStats.dictationToday(appState.dictationHistory, now: now)
        let usual = DesktopStats.usualDictationWords(appState.dictationHistory, now: now)
        let scale = DesktopStats.dictationScale(todayWords: today.words, usual: usual)
        let last = appState.dictationHistory.first
        return tile(.waveform, "Dictation", help: "Open Dictation", action: { navigation.section = .dictation }) {
            Text("today").hud(.meta)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HudSegmentDigits("\(today.words)", height: 30)
                Text("words").hud(.unit)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 8) {
                // Today against your usual day (the triangle); a plain scale until there is one.
                HudDotMatrix(value: scale.value, count: 78, mark: scale.mark)
                    .padding(.bottom, 8)
                    .help(usual.map { "Your usual day: \(Int($0.rounded())) words" } ?? "")
                if let last {
                    Text(verbatim: "“\(last.finalText)”" + (last.appName.map { " · \($0)" } ?? ""))
                        .hud(.meta).lineLimit(1).truncationMode(.tail)
                } else {
                    Text(verbatim: "Hold \(preferences.keyPhrase) and speak to dictate.").hud(.meta).lineLimit(1)
                }
            }
        }
    }

    // MARK: Recent meetings

    private func recent(now: Date) -> some View {
        let meetings = Array(appState.storedMeetings.prefix(3))
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Recent meetings").hud(.label, Hud.Ink.ink2)
                Spacer(minLength: 4)
                HudButton("All meetings", trailingGlyph: .chevronRight, size: .mini) { navigation.section = .meetings }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 36)
            if meetings.isEmpty {
                HStack(spacing: 12) {
                    Text("No recordings yet").hud(.body, Hud.Ink.ink2)
                    Text("Crenel offers to record when a call starts.").hud(.meta)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: Hud.Row.twoLine)
            } else {
                ForEach(meetings) { meeting in
                    Button {
                        navigation.selectedMeeting = meeting.id
                        navigation.section = .meetings
                    } label: {
                        HudRow(.twoLine) {
                            HudTimeColumn(DesktopFormat.clock(meeting.startedAt), DesktopFormat.runLength(meeting.duration))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: meeting.title).hud(.body).lineLimit(1).truncationMode(.tail)
                                Text(verbatim: recentMeta(meeting, now: now)).hud(.meta).lineLimit(1).truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            DesktopMeetingStatusWord(state: DesktopMeetingState.resolve(meeting, jobs: appState.processingJobs))
                                .padding(.top, 2)
                        }
                        .hudGlide(meeting.id, hovered: $hoveredRecent, in: recentSpace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
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
            HudStatusWord(.ok, "Notes ready").font(Hud.font(11.5, .medium))
        case .processing:
            HStack(spacing: 8) {
                HudBusy()
                Text("Processing").hud(.meta, Hud.Ink.ink2)
            }
        case .failed:
            HStack(spacing: 8) {
                HudStatusShape(.err)
                Text("Failed").hud(.meta, Hud.Ink.ink2)
            }
        case .transcriptOnly:
            HStack(spacing: 8) {
                HudStatusShape(.warn)
                Text("Transcript only").hud(.meta, Hud.Ink.ink2)
            }
        case .notTranscribed:
            HStack(spacing: 8) {
                HudStatusShape(.wait)
                Text("Not transcribed").hud(.meta, Hud.Ink.ink2)
            }
        }
    }
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
                .padding(16)
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
