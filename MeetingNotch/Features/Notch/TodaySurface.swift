import SwiftUI

/// The "Today" surface while nothing is recording: the next event as a lit hero card,
/// the rest of the day beside it, and the top of the task list.
struct TodaySurface: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var actions
    let events: [Meeting]
    let emptyMessage: String
    let canRequestCalendarAccess: Bool
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let hero = events.first { !$0.isAllDay && $0.endDate > now }
            let rest = events.filter { $0.id != hero?.id }
            // Side by side whenever the open notch is wide enough; stacked on small screens.
            if appState.notchPanelAvailableSize.width >= 560 {
                HStack(alignment: .top, spacing: Crenel.Space.l) {
                    heroCard(hero, now: now)
                        .frame(width: 250)
                    sideColumn(rest, now: now)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: Crenel.Space.l) {
                    heroCard(hero, now: now)
                    sideColumn(rest, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func heroCard(_ event: Meeting?, now: Date) -> some View {
        if let event {
            NextEventHero(event: event, now: now, onJoin: onOpenMeetingURL, onStartRecording: onStartRecording)
        } else {
            VStack(alignment: .leading, spacing: Crenel.Space.m) {
                CrenelIcon(.calendar, size: 20)
                    .foregroundStyle(Crenel.Palette.calendar)
                    .frame(width: 40, height: 40)
                    .background(Crenel.Palette.calendar.opacity(0.12), in: Circle())
                Text(emptyMessage)
                    .crenelText(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Crenel.Space.s) {
                    if canRequestCalendarAccess {
                        Button("Connect calendar", action: onRequestCalendarAccess)
                            .buttonStyle(CrenelButtonStyle(kind: .primary, size: .small))
                    }
                    RecordButton(action: onStartRecording)
                }
            }
            .padding(Crenel.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .crenelSurface()
        }
    }

    private func sideColumn(_ events: [Meeting], now: Date) -> some View {
        let tasks = Array(appState.tasks.filter(\.isActive)
            .sorted { lhs, rhs in
                (lhs.status == .inProgress ? 0 : 1, lhs.dueDate ?? .distantFuture)
                    < (rhs.status == .inProgress ? 0 : 1, rhs.dueDate ?? .distantFuture)
            }
            .prefix(4))
        return VStack(alignment: .leading, spacing: Crenel.Space.l) {
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    CrenelSectionHeader(title: "Later", count: events.count > 1 ? events.count : nil)
                        .padding(.horizontal, Crenel.Space.xs)
                        .padding(.bottom, Crenel.Space.xxs)
                    ForEach(events) { event in
                        AgendaRow(event: event, now: now, onJoin: onOpenMeetingURL)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                CrenelSectionHeader(title: "Tasks", count: appState.activeTaskCount > 0 ? appState.activeTaskCount : nil, tint: Crenel.Palette.textTertiary) {
                    Button {
                        appState.selectedTab = .tasks
                    } label: {
                        HStack(spacing: 3) {
                            Text("All")
                            CrenelIcon(.chevronRight, size: 10, weight: 2.2)
                        }
                        .crenelText(.caption, color: Crenel.Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Crenel.Space.xs)
                .padding(.bottom, Crenel.Space.xxs)
                if tasks.isEmpty {
                    Text("No open tasks today.")
                        .crenelText(.callout, color: Crenel.Palette.textTertiary)
                        .padding(.horizontal, Crenel.Space.xs)
                } else {
                    ForEach(tasks) { task in
                        TaskPeekRow(task: task, now: now)
                    }
                }
            }
        }
    }
}

// MARK: - Hero

private struct NextEventHero: View {
    @Environment(\.crenelActions) private var actions
    let event: Meeting
    let now: Date
    let onJoin: (URL) -> Void
    let onStartRecording: () -> Void

    var body: some View {
        let ongoing = event.startDate <= now
        let tint = accent
        VStack(alignment: .leading, spacing: Crenel.Space.m) {
            HStack(alignment: .center, spacing: Crenel.Space.m) {
                ZStack {
                    CrenelProgressRing(progress: progress, tint: tint, lineWidth: 3.5)
                    Text(ringText)
                        .font(.system(size: ringText.count > 2 ? 15 : 19, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Crenel.Palette.textPrimary)
                        .contentTransition(.numericText())
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ongoing ? "Now" : "Next").eyebrow(color: tint)
                    Text(ringCaption)
                        .crenelText(.callout, color: Crenel.Palette.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if event.responseStatus == .pending {
                        CrenelChip(title: "Awaiting reply", tint: Crenel.Palette.warning)
                    }
                }
                Text(event.title)
                    .crenelText(.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AgendaRowText.subtitle(for: event))
                    .crenelText(.callout, color: Crenel.Palette.textTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: Crenel.Space.s) {
                if let url = event.meetingURL {
                    Button {
                        onJoin(url)
                    } label: {
                        HStack(spacing: 6) {
                            CrenelIcon(.video, size: 14)
                            Text("Join")
                        }
                    }
                    .buttonStyle(CrenelButtonStyle(kind: .accent(tint), size: .regular))
                } else {
                    Button {
                        actions.openInCalendar(event)
                    } label: {
                        HStack(spacing: 6) {
                            CrenelIcon(.arrowUpRight, size: 13)
                            Text("Open in Calendar")
                        }
                    }
                    .buttonStyle(CrenelButtonStyle(kind: .secondary, size: .regular))
                }
                if event.isMeetingLike {
                    RecordButton(action: onStartRecording)
                }
            }
        }
        .padding(Crenel.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Crenel.Radius.l, style: .continuous)
                    .fill(Crenel.Palette.layer1)
                CrenelAura(tint: tint, intensity: 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: Crenel.Radius.l, style: .continuous))
            }
        }
        .crenelSurface(.clear)
        .contextMenu {
            if let url = event.meetingURL { Button("Join meeting") { onJoin(url) } }
            Button("Open in Calendar") { actions.openInCalendar(event) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AgendaRowText.accessibilityLabel(for: event))
    }

    private var accent: Color {
        if let hex = event.calendarColorHex, let color = Color(crenelHex: hex) { return color }
        return Crenel.Palette.calendar
    }

    private var progress: Double {
        if event.startDate <= now {
            let duration = max(60, event.endDate.timeIntervalSince(event.startDate))
            return min(1, now.timeIntervalSince(event.startDate) / duration)
        }
        return min(1, max(0.03, 1 - event.startDate.timeIntervalSince(now) / 3_600))
    }

    /// Minutes in the ring while under an hour; otherwise the start time.
    private var ringText: String {
        let interval = event.startDate <= now ? event.endDate.timeIntervalSince(now) : event.startDate.timeIntervalSince(now)
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)" }
        return NotchAgendaFormatter.clockText(event.startDate <= now ? event.endDate : event.startDate, calendar: .current)
    }

    private var ringCaption: String {
        let interval = event.startDate <= now ? event.endDate.timeIntervalSince(now) : event.startDate.timeIntervalSince(now)
        if event.startDate <= now {
            return "\(NotchAgendaFormatter.durationText(max(60, interval))) left"
        }
        return interval < 3_600 ? "minutes away" : "in \(NotchAgendaFormatter.durationText(interval))"
    }
}

/// The red record action, reused wherever a recording can start.
struct RecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(Crenel.Palette.record).frame(width: 8, height: 8)
                Text("Record")
            }
        }
        .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.record), size: .regular))
        .help("Record meeting")
        .accessibilityLabel("Start recording")
    }
}

// MARK: - Rows

private struct AgendaRow: View {
    @Environment(\.crenelActions) private var actions
    let event: Meeting
    let now: Date
    let onJoin: (URL) -> Void

    var body: some View {
        Button {
            if let url = event.meetingURL { onJoin(url) } else { actions.openInCalendar(event) }
        } label: {
            HStack(spacing: Crenel.Space.m) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .crenelText(.bodyEmphasis)
                        .lineLimit(1)
                    Text(AgendaRowText.subtitle(for: event))
                        .crenelText(.caption, color: Crenel.Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: Crenel.Space.s)
                if event.meetingURL != nil {
                    CrenelIcon(.video, size: 13)
                        .foregroundStyle(Crenel.Palette.textTertiary)
                }
                Text(timeText)
                    .crenelText(.caption, color: Crenel.Palette.textSecondary)
            }
            .padding(.horizontal, Crenel.Space.xs)
            .padding(.vertical, Crenel.Space.s)
        }
        .buttonStyle(CrenelRowStyle())
        .opacity(event.isSuggestion || event.responseStatus == .tentative ? 0.65 : 1)
        .contextMenu {
            if let url = event.meetingURL { Button("Join meeting") { onJoin(url) } }
            Button("Open in Calendar") { actions.openInCalendar(event) }
        }
        .accessibilityLabel(AgendaRowText.accessibilityLabel(for: event))
    }

    private var accent: Color {
        if let hex = event.calendarColorHex, let color = Color(crenelHex: hex) { return color }
        return event.isMeetingLike ? Crenel.Palette.calendar : Crenel.Palette.textTertiary
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        if event.responseStatus == .pending { return "Awaiting reply" }
        return NotchAgendaFormatter.clockText(event.startDate, calendar: .current)
    }
}

private struct TaskPeekRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var actions
    let task: TaskItem
    let now: Date

    var body: some View {
        HStack(spacing: Crenel.Space.m) {
            Button {
                actions.tasks.setStatus(task, task.isCompleted ? .open : .completed)
            } label: {
                TaskStateGlyph(status: task.status, size: 15)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Mark as done")
            Text(task.title)
                .crenelText(.body)
                .lineLimit(1)
            Spacer(minLength: Crenel.Space.s)
            if let due = TaskDueFormatter.label(for: task, now: now) {
                Text(due).crenelText(.caption, color: Crenel.Palette.textTertiary)
            }
        }
        .padding(.horizontal, Crenel.Space.xs)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedTab = .tasks }
    }
}

// MARK: - Recent meetings

struct RecentMeetingsList: View {
    let meetings: [StoredMeeting]
    let onOpen: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void
    let onRetry: (StoredMeeting) -> Void

    var body: some View {
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                CrenelSectionHeader(title: "Recent recordings")
                    .padding(.horizontal, Crenel.Space.xs)
                    .padding(.bottom, Crenel.Space.xxs)
                ForEach(meetings) { meeting in
                    Button { onOpen(meeting) } label: {
                        HStack(spacing: Crenel.Space.m) {
                            CrenelIcon(glyph(meeting), size: 15)
                                .foregroundStyle(tint(meeting))
                                .frame(width: 30, height: 30)
                                .background(tint(meeting).opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title).crenelText(.bodyEmphasis).lineLimit(1)
                                Text(detail(meeting)).crenelText(.caption, color: Crenel.Palette.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: Crenel.Space.s)
                            Text(duration(meeting)).crenelText(.caption, color: Crenel.Palette.textSecondary)
                        }
                        .padding(.horizontal, Crenel.Space.xs)
                        .padding(.vertical, Crenel.Space.xs)
                    }
                    .buttonStyle(CrenelRowStyle())
                    .contextMenu {
                        Button("Open meeting") { onOpen(meeting) }
                        if meeting.processingStatus == .failed {
                            Button("Retry processing") { onRetry(meeting) }
                        }
                        Divider()
                        Button("Delete meeting", role: .destructive) { onDelete(meeting) }
                    }
                    .accessibilityLabel("\(meeting.title), \(detail(meeting)), \(duration(meeting))")
                }
            }
        }
    }

    private func glyph(_ meeting: StoredMeeting) -> CrenelGlyph {
        if meeting.summaryNeedsAttention == true { return .warning }
        switch meeting.processingStatus {
        case .recorded: return .waveform
        case .processing: return .sparkle
        case .completed: return .check
        case .failed: return .warning
        }
    }

    private func tint(_ meeting: StoredMeeting) -> Color {
        if meeting.summaryNeedsAttention == true { return Crenel.Palette.warning }
        switch meeting.processingStatus {
        case .recorded, .processing: return Crenel.Palette.dictation
        case .completed: return Crenel.Palette.success
        case .failed: return Crenel.Palette.warning
        }
    }

    private func detail(_ meeting: StoredMeeting) -> String {
        let date = meeting.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(AppLanguage.locale))
        if meeting.summaryNeedsAttention == true { return "Summary pending · \(date)" }
        switch meeting.processingStatus {
        case .processing: return "Processing · \(date)"
        case .failed: return "Processing failed · \(date)"
        default: return date
        }
    }

    private func duration(_ meeting: StoredMeeting) -> String {
        CrenelCompactView.elapsed(meeting.duration)
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
