import SwiftUI

/// The "bugün" surface while nothing is recording: the coming days as a time-column
/// agenda with the next item lit, then the top of the task list.
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
            VStack(alignment: .leading, spacing: Crenel.Space.l) {
                agenda(now: now)
                tasks(now: now)
            }
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agenda(now: Date) -> some View {
        let upcoming = events.filter { $0.endDate > now }.prefix(6)
        let next = upcoming.first { !$0.isAllDay }
        VStack(alignment: .leading, spacing: 0) {
            CrenelSectionHeader(title: Self.dayTitle(now, now: now), tint: Crenel.Palette.textSecondary) {
                Button(action: onStartRecording) {
                    HStack(spacing: 6) {
                        CrenelIcon(.record, size: 9).foregroundStyle(Crenel.Palette.record)
                        Text("kaydet")
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
                .help("Toplantı kaydını başlat")
                .accessibilityLabel("Kaydı başlat")
            }
            .padding(.horizontal, Crenel.Space.s)
            .padding(.bottom, Crenel.Space.xxs)

            if upcoming.isEmpty {
                HStack(spacing: Crenel.Space.m) {
                    CrenelIcon(.calendar, size: 13.5).foregroundStyle(Crenel.Palette.calendar)
                    Text(emptyMessage.lowercased(with: Locale(identifier: "tr_TR")))
                        .crenelText(.callout, color: Crenel.Palette.textSecondary)
                    Spacer(minLength: 0)
                    if canRequestCalendarAccess {
                        Button("takvime bağlan", action: onRequestCalendarAccess)
                            .buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.calendar), size: .small))
                    }
                }
                .padding(.horizontal, Crenel.Space.s)
                .frame(height: 40)
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                    let previous = index > 0 ? upcoming[upcoming.index(upcoming.startIndex, offsetBy: index - 1)] : nil
                    if let previous, !Calendar.current.isDate(previous.startDate, inSameDayAs: event.startDate) {
                        Text(Self.dayTitle(event.startDate, now: now))
                            .eyebrow()
                            .padding(.horizontal, Crenel.Space.s)
                            .padding(.top, Crenel.Space.s)
                            .frame(height: 26, alignment: .bottom)
                    } else if previous == nil, !Calendar.current.isDate(event.startDate, inSameDayAs: now), event.startDate > now {
                        Text(Self.dayTitle(event.startDate, now: now))
                            .eyebrow()
                            .padding(.horizontal, Crenel.Space.s)
                            .frame(height: 22, alignment: .bottom)
                    }
                    AgendaLine(
                        event: event,
                        now: now,
                        isNext: event.id == next?.id,
                        onJoin: onOpenMeetingURL
                    )
                }
            }
        }
    }

    // MARK: Tasks

    private func tasks(now: Date) -> some View {
        let tasks = Array(appState.tasks.filter(\.isActive)
            .sorted { lhs, rhs in
                (Self.rank(lhs.status), lhs.dueDate ?? .distantFuture) < (Self.rank(rhs.status), rhs.dueDate ?? .distantFuture)
            }
            .prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            CrenelSectionHeader(title: "görevler", count: appState.activeTaskCount > 0 ? appState.activeTaskCount : nil) {
                Button {
                    appState.selectedTab = .tasks
                } label: {
                    HStack(spacing: 6) {
                        Text("tümü")
                        CrenelIcon(.chevronRight, size: 9)
                    }
                }
                .buttonStyle(CrenelButtonStyle(kind: .ghost, size: .small))
            }
            .padding(.horizontal, Crenel.Space.s)
            .padding(.bottom, Crenel.Space.xxs)
            if tasks.isEmpty {
                Text("açık görev yok")
                    .crenelText(.callout, color: Crenel.Palette.textTertiary)
                    .padding(.horizontal, Crenel.Space.s)
                    .frame(height: 30)
            } else {
                ForEach(tasks) { task in
                    TaskPeekLine(task: task, now: now)
                }
            }
        }
    }

    private static func rank(_ status: TaskStatus) -> Int {
        switch status {
        case .inProgress: 0
        case .blocked: 1
        default: 2
        }
    }

    static func dayTitle(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "EEE d MMM"
        let formatted = formatter.string(from: date).lowercased(with: Locale(identifier: "tr_TR"))
        if calendar.isDate(date, inSameDayAs: now) { return "bugün · \(formatted)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "yarın · \(formatted)"
        }
        return formatted
    }
}

// MARK: - Lines

private struct AgendaLine: View {
    @Environment(\.crenelActions) private var actions
    let event: Meeting
    let now: Date
    let isNext: Bool
    let onJoin: (URL) -> Void

    var body: some View {
        let ongoing = !event.isAllDay && event.startDate <= now
        Button {
            if let url = event.meetingURL { onJoin(url) } else { actions.openInCalendar(event) }
        } label: {
            HStack(spacing: Crenel.Space.m) {
                Text(event.isAllDay ? "gün" : NotchAgendaFormatter.clockText(event.startDate, calendar: .current))
                    .crenelText(.callout, color: isNext ? Crenel.Palette.textPrimary : Crenel.Palette.textTertiary)
                    .frame(width: 42, alignment: .leading)
                Rectangle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .crenelText(isNext ? .bodyEmphasis : .body)
                        .lineLimit(1)
                    if isNext {
                        Text(subtitle.lowercased(with: Locale(identifier: "tr_TR")))
                            .crenelText(.caption, color: Crenel.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Crenel.Space.s)
                if event.responseStatus == .pending {
                    CrenelChip(title: "yanıt bekliyor", tint: Crenel.Palette.warning)
                }
                if isNext {
                    Text(countdown(ongoing: ongoing))
                        .crenelText(.callout, color: ongoing ? Crenel.Palette.success : accent)
                        .contentTransition(.numericText())
                    if event.meetingURL != nil {
                        HStack(spacing: 5) {
                            CrenelIcon(.video, size: 9)
                            Text("katıl")
                        }
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Crenel.Palette.ink)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(PixelCornerShape().fill(accent))
                    }
                } else if event.meetingURL != nil {
                    CrenelIcon(.video, size: 9).foregroundStyle(Crenel.Palette.textQuaternary)
                }
            }
            .padding(.horizontal, Crenel.Space.s)
            .frame(height: isNext ? 46 : 32)
            .background {
                if isNext {
                    PixelCornerShape(steps: 3).fill(accent.opacity(0.08))
                    PixelCornerShape(steps: 3).stroke(accent.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(CrenelRowStyle())
        .opacity(event.isSuggestion || event.responseStatus == .tentative ? 0.6 : 1)
        .contextMenu {
            if let url = event.meetingURL { Button("Toplantıya katıl") { onJoin(url) } }
            Button("Takvim’de aç") { actions.openInCalendar(event) }
        }
        .accessibilityLabel(AgendaRowText.accessibilityLabel(for: event))
    }

    private var accent: Color {
        if let hex = event.calendarColorHex, let color = Color(crenelHex: hex) { return color }
        return event.isMeetingLike ? Crenel.Palette.calendar : Crenel.Palette.textTertiary
    }

    private var subtitle: String {
        let minutes = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
        var parts = ["\(minutes) dk"]
        if let location = event.location, event.meetingURL == nil || !location.contains("://") {
            parts.append(location)
        } else if let calendar = event.calendarTitle {
            parts.append(calendar)
        }
        return parts.joined(separator: " · ")
    }

    private func countdown(ongoing: Bool) -> String {
        if ongoing {
            return "\(NotchAgendaFormatter.durationText(max(60, event.endDate.timeIntervalSince(now)))) kaldı"
        }
        let interval = event.startDate.timeIntervalSince(now)
        if interval > 12 * 3_600 { return "" }
        return "\(NotchAgendaFormatter.durationText(interval)) sonra"
    }
}

private struct TaskPeekLine: View {
    @EnvironmentObject private var appState: AppState
    let task: TaskItem
    let now: Date

    var body: some View {
        Button {
            appState.selectedTab = .tasks
        } label: {
            HStack(spacing: Crenel.Space.m) {
                TaskStateGlyph(status: task.status, size: 9)
                    .frame(width: 42, alignment: .leading)
                Color.clear.frame(width: 6, height: 1)
                Text(task.title)
                    .crenelText(.body)
                    .lineLimit(1)
                Spacer(minLength: Crenel.Space.s)
                if let due = TaskDueFormatter.label(for: task, now: now) {
                    Text(due.lowercased(with: Locale(identifier: "tr_TR")))
                        .crenelText(.caption, color: Crenel.Palette.textTertiary)
                }
            }
            .padding(.horizontal, Crenel.Space.s)
            .frame(height: 30)
        }
        .buttonStyle(CrenelRowStyle())
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
            VStack(alignment: .leading, spacing: 0) {
                CrenelSectionHeader(title: "son kayıtlar")
                    .padding(.horizontal, Crenel.Space.s)
                    .padding(.bottom, Crenel.Space.xxs)
                ForEach(meetings) { meeting in
                    Button { onOpen(meeting) } label: {
                        HStack(spacing: Crenel.Space.m) {
                            Text(CrenelCompactView.elapsed(meeting.duration))
                                .crenelText(.caption, color: Crenel.Palette.textTertiary)
                                .frame(width: 42, alignment: .leading)
                            CrenelIcon(glyph(meeting), size: 9)
                                .foregroundStyle(tint(meeting))
                            Text(meeting.title).crenelText(.body).lineLimit(1)
                            Spacer(minLength: Crenel.Space.s)
                            Text(detail(meeting)).crenelText(.caption, color: Crenel.Palette.textTertiary).lineLimit(1)
                        }
                        .padding(.horizontal, Crenel.Space.s)
                        .frame(height: 30)
                    }
                    .buttonStyle(CrenelRowStyle())
                    .contextMenu {
                        Button("Toplantıyı aç") { onOpen(meeting) }
                        if meeting.processingStatus == .failed {
                            Button("İşlemeyi tekrar dene") { onRetry(meeting) }
                        }
                        Divider()
                        Button("Toplantıyı sil", role: .destructive) { onDelete(meeting) }
                    }
                    .accessibilityLabel("\(meeting.title), \(detail(meeting))")
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
        case .recorded, .processing: return Crenel.Palette.agent
        case .completed: return Crenel.Palette.success
        case .failed: return Crenel.Palette.warning
        }
    }

    private func detail(_ meeting: StoredMeeting) -> String {
        let date = meeting.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "tr_TR")))
            .lowercased(with: Locale(identifier: "tr_TR"))
        if meeting.summaryNeedsAttention == true { return "özet bekliyor · \(date)" }
        switch meeting.processingStatus {
        case .processing: return "işleniyor · \(date)"
        case .failed: return "işlenemedi · \(date)"
        default: return date
        }
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
