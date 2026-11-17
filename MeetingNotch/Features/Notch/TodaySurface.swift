import SwiftUI

/// "Today" while nothing is recording: the next thing that needs you, then the rest of
/// today and what comes later. Rows say what kind of event it is with their icon; times
/// sit on the right; colour appears only when something needs you.
struct TodaySurface: View {
    @Environment(\.crenelActions) private var actions
    let events: [Meeting]
    let emptyMessage: String
    let canRequestCalendarAccess: Bool
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let upcoming = events.filter { $0.endDate > now }
            let focus = upcoming.first { !$0.isAllDay }
            let rest = upcoming.filter { $0.id != focus?.id }
            let today = rest.filter { Calendar.current.isDate($0.startDate, inSameDayAs: now) }
            let later = rest.filter { !Calendar.current.isDate($0.startDate, inSameDayAs: now) }

            VStack(alignment: .leading, spacing: 0) {
                if let focus {
                    TodayFocus(event: focus, now: now)
                        .modifier(EventActions(event: focus, open: open, onStartRecording: onStartRecording))
                        .hudGlide(focus.id, hovered: $hovered, in: glide)
                        .padding(.bottom, Hud.Space.x3)
                }
                if !today.isEmpty {
                    group("Today", today, now: now)
                }
                if !later.isEmpty {
                    group("Later", later, now: now)
                        .padding(.top, today.isEmpty ? 0 : Hud.Space.x3)
                }
                if upcoming.isEmpty {
                    emptyRow
                }
            }
        }
    }

    private func group(_ title: LocalizedStringKey, _ events: [Meeting], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: title)
            ForEach(events) { event in
                TodayEventRow(event: event, now: now)
                    .modifier(EventActions(event: event, open: open, onStartRecording: onStartRecording))
                    .hudGlide(event.id, hovered: $hovered, in: glide)
            }
        }
    }

    /// No events: the calendar state in one row, with the one action that fixes it.
    private var emptyRow: some View {
        HStack(spacing: Hud.Space.x3) {
            HudIcon(.calendar).foregroundStyle(Hud.Ink.text3)
            Text(emptyMessage).hud(.body, Hud.Ink.text2).lineLimit(1)
            Spacer(minLength: Hud.Space.x2)
            if canRequestCalendarAccess {
                Button("Connect", action: onRequestCalendarAccess)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
    }

    private func open(_ event: Meeting) {
        if let url = event.meetingURL { onOpenMeetingURL(url) } else { actions.openInCalendar(event) }
    }
}

/// Click opens the event (its call link, or Calendar); the context menu holds the rest.
private struct EventActions: ViewModifier {
    @Environment(\.crenelActions) private var actions
    let event: Meeting
    let open: (Meeting) -> Void
    let onStartRecording: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture { open(event) }
            .contextMenu {
                if let url = event.meetingURL {
                    Button("Join meeting") { open(event) }
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                Button("Open in Calendar") { actions.openInCalendar(event) }
                if event.isMeetingLike {
                    Divider()
                    Button("Record now", action: onStartRecording)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(AgendaRowText.accessibilityLabel(for: event))
    }
}

// MARK: - Focus

/// The next thing that needs you. No label and no buttons: its size and colour say
/// "next". Within the hour a segmented bar empties toward the start; during the
/// meeting it fills with elapsed time.
private struct TodayFocus: View {
    let event: Meeting
    let now: Date

    private var untilStart: TimeInterval { event.startDate.timeIntervalSince(now) }
    private var isLive: Bool { untilStart <= 0 }
    private var isNear: Bool { untilStart > 0 && untilStart <= 60 * 60 }
    private var isUrgent: Bool { isLive || untilStart <= 10 * 60 }

    var body: some View {
        HStack(alignment: .top, spacing: Hud.Space.x3) {
            MeetingKindIcon(meeting: event, tint: isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
                    Text(event.title).hud(.title).lineLimit(1)
                    Spacer(minLength: Hud.Space.x2)
                    Text(primaryValue).hud(.title, isUrgent ? Hud.Ink.signal : Hud.Ink.text1)
                        .contentTransition(.numericText(countsDown: true))
                        .fixedSize()
                }
                HStack(spacing: Hud.Space.x2) {
                    Text(event.venueWord ?? "").hud(.meta, Hud.Ink.text3).lineLimit(1)
                    Spacer(minLength: Hud.Space.x2)
                    Text(secondaryValue).hud(.meta, Hud.Ink.text3).fixedSize()
                }
                if isNear || isLive {
                    HudSegmentMeter(segments: 28, progress: progress, tint: isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                        .padding(.top, Hud.Space.x2)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x3)
        .opacity(event.isSuggestion || event.responseStatus == .tentative ? 0.6 : 1)
    }

    private var primaryValue: String {
        if isLive { return "\(max(1, Int((event.endDate.timeIntervalSince(now) / 60).rounded(.up)))) min" }
        if isNear { return "\(max(1, Int((untilStart / 60).rounded(.up)))) min" }
        return HudFormat.clock(event.startDate)
    }

    private var secondaryValue: String {
        if isLive || isNear { return "\(HudFormat.clock(event.startDate)) – \(HudFormat.clock(event.endDate))" }
        return HudFormat.day(event.startDate, now: now)
    }

    private var progress: Double {
        if isLive {
            return now.timeIntervalSince(event.startDate) / max(60, event.endDate.timeIntervalSince(event.startDate))
        }
        return untilStart / 3_600
    }
}

// MARK: - Row

/// Kind icon, then two lines: title and start on top; venue and end (or day) below.
private struct TodayEventRow: View {
    let event: Meeting
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: Hud.Space.x3) {
            MeetingKindIcon(meeting: event).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
                    Text(event.title).hud(.body).lineLimit(1)
                    Spacer(minLength: Hud.Space.x2)
                    Text(event.isAllDay ? String(localized: "All day") : HudFormat.clock(event.startDate))
                        .hud(.value, event.responseStatus == .pending ? Hud.Ink.signal : Hud.Ink.text2)
                        .fixedSize()
                }
                HStack(spacing: Hud.Space.x2) {
                    Text(detail).hud(.meta, Hud.Ink.text3).lineLimit(1)
                    Spacer(minLength: Hud.Space.x2)
                    Text(trailingDetail).hud(.meta, Hud.Ink.text3).fixedSize()
                }
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
        .opacity(event.isSuggestion || event.responseStatus == .tentative ? 0.6 : 1)
    }

    private var detail: String {
        if event.responseStatus == .pending { return String(localized: "Invite") }
        return event.venueWord ?? ""
    }

    private var trailingDetail: String {
        if !Calendar.current.isDate(event.startDate, inSameDayAs: now) { return HudFormat.day(event.startDate, now: now) }
        return event.isAllDay ? "" : HudFormat.clock(event.endDate)
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
