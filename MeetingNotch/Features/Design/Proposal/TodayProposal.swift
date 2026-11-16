import SwiftUI

/// Design proposal for the open notch's Today surface, built on the `Hud` language.
/// Self-contained (takes plain values) so it can be reviewed before it replaces the
/// live surface.
struct TodayProposalModel {
    struct Event: Identifiable {
        let id = UUID()
        let title: String
        let start: Date
        let end: Date
        var hasLink = false
        var place: String?
    }

    var now: Date
    var events: [Event]
    var taskCount: Int
    var hoveredTitle: String?
}

struct TodayProposalView: View {
    let model: TodayProposalModel
    let hardware: CGSize

    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private let turkish = Locale(identifier: "tr_TR")

    var body: some View {
        VStack(spacing: 0) {
            ears
            VStack(alignment: .leading, spacing: Hud.Space.x5) {
                if let next { focus(next) }
                agenda
            }
            .padding(.top, Hud.Space.x5)
            footer
                .padding(.top, Hud.Space.x4)
        }
        .padding(.horizontal, Hud.Size.panelInset - Hud.Space.x2)
        .padding(.bottom, Hud.Space.x3)
    }

    // MARK: Ears

    private var ears: some View {
        NotchFlankLayout(gap: hardware.width + Hud.Space.x6) {
            HStack {
                HudEarTab(title: "Bugün", key: "1", isSelected: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, Hud.Space.x2)
            HStack {
                Spacer(minLength: 0)
                HudEarTab(title: "Görevler", key: "2", count: model.taskCount, isSelected: false)
            }
            .padding(.trailing, Hud.Space.x2)
        }
        .frame(height: hardware.height)
        .frame(maxWidth: .infinity)
    }

    // MARK: Focus — the next thing that needs you

    private var next: TodayProposalModel.Event? {
        model.events.first { $0.end > model.now }
    }

    @ViewBuilder
    private func focus(_ event: TodayProposalModel.Event) -> some View {
        let untilStart = event.start.timeIntervalSince(model.now)
        let isLive = untilStart <= 0
        let isNear = untilStart > 0 && untilStart <= 60 * 60
        let tint: Color = isLive || untilStart <= 10 * 60 ? Hud.Ink.signal : Hud.Ink.text3

        VStack(alignment: .leading, spacing: 0) {
            HudSectionLabel(title: isLive ? "Şimdi" : "Sıradaki",
                            value: countdown(untilStart: untilStart, event: event),
                            tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).hud(.title).lineLimit(1)
                Text(detail(event)).hud(.meta, Hud.Ink.text2).lineLimit(1)
            }
            .padding(.horizontal, Hud.Space.x2)
            .padding(.top, Hud.Space.x1)

            if isNear || isLive {
                HStack(spacing: Hud.Space.x3) {
                    HudSegmentMeter(segments: 24, lit: litSegments(event: event, untilStart: untilStart), tint: tint)
                    Text(clock(isLive ? event.end : event.start)).hud(.numeral, Hud.Ink.text3)
                }
                .padding(.horizontal, Hud.Space.x2)
                .padding(.top, Hud.Space.x3)

                HStack(spacing: Hud.Space.x1) {
                    if event.hasLink {
                        Button {} label: {
                            HStack(spacing: 6) { HudIcon(.video, size: 13); Text("Katıl") }
                        }
                        .buttonStyle(HudButtonStyle(kind: .primary))
                    }
                    Button {} label: {
                        HStack(spacing: 6) {
                            HudIcon(.record, size: 13).foregroundStyle(Hud.Ink.live)
                            Text("Kaydet")
                            HudKeyHint(keys: "⌘R")
                        }
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                }
                .padding(.horizontal, Hud.Space.x1)
                .padding(.top, Hud.Space.x3)
            }
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        let rest = model.events.filter { $0.id != next?.id && $0.end > model.now }
        let groups = Dictionary(grouping: rest) { calendar.startOfDay(for: $0.start) }
        let days = groups.keys.sorted()

        return VStack(alignment: .leading, spacing: Hud.Space.x3) {
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 0) {
                    HudSectionLabel(title: dayTitle(day), value: "\(groups[day]?.count ?? 0)")
                    ForEach(groups[day] ?? []) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: TodayProposalModel.Event) -> some View {
        HudRow(forceHover: model.hoveredTitle == event.title) {
            Text(clock(event.start))
                .hud(.numeral, Hud.Ink.text2)
                .fixedSize()
                .frame(width: Hud.Size.timeColumn - Hud.Space.x3, alignment: .leading)
            Text(event.title).hud(.body).lineLimit(1)
            Spacer(minLength: Hud.Space.x2)
            if event.hasLink {
                HudIcon(.video, size: 13).foregroundStyle(Hud.Ink.text3)
            }
            Text(duration(event))
                .hud(.numeral, Hud.Ink.text3)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Hud.Space.x2) {
            Rectangle().fill(Hud.Ink.line).frame(height: 1).padding(.horizontal, Hud.Space.x2)
            HStack(spacing: Hud.Space.x1) {
                Button {} label: {
                    HStack(spacing: 6) { HudIcon(.history, size: 13); Text("Geçmiş") }
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
                Spacer()
                Button {} label: { HudIcon(.window) }.buttonStyle(HudButtonStyle(kind: .icon))
                Button {} label: { HudIcon(.pin) }.buttonStyle(HudButtonStyle(kind: .icon))
            }
        }
    }

    // MARK: Formatting

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = turkish
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dayTitle(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = turkish
        formatter.dateFormat = "d MMM EEE"
        let date = formatter.string(from: day)
        if calendar.isDate(day, inSameDayAs: model.now) { return "Bugün · \(date)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: model.now),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Yarın · \(date)" }
        return date
    }

    private func detail(_ event: TodayProposalModel.Event) -> String {
        var parts = ["\(clock(event.start))–\(clock(event.end))"]
        if event.hasLink { parts.append("Google Meet") }
        if let place = event.place { parts.append(place) }
        return parts.joined(separator: "  ·  ")
    }

    private func relativeDay(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: model.now) { return "Bugün" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: model.now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Yarın" }
        let formatter = DateFormatter()
        formatter.locale = turkish
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func duration(_ event: TodayProposalModel.Event) -> String {
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        return minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60)sa" : "\(minutes)dk"
    }

    /// Countdown only when it is useful (under an hour); otherwise the day and time.
    private func countdown(untilStart: TimeInterval, event: TodayProposalModel.Event) -> String {
        if untilStart <= 0 {
            let left = Int(event.end.timeIntervalSince(model.now) / 60)
            return "\(left) dk kaldı"
        }
        if untilStart <= 60 * 60 { return "\(Int((untilStart / 60).rounded(.up))) dk" }
        return relativeDay(event.start)
    }

    /// Before the start, the bar empties toward zero across the last hour; during the
    /// meeting it fills with elapsed time.
    private func litSegments(event: TodayProposalModel.Event, untilStart: TimeInterval) -> Int {
        if untilStart <= 0 {
            let total = event.end.timeIntervalSince(event.start)
            return Int((model.now.timeIntervalSince(event.start) / total * 24).rounded())
        }
        return Int((untilStart / 3_600 * 24).rounded(.up))
    }
}

// MARK: - Closed notch

/// The closed notch: status in the ears beside the camera, same type and icons as the
/// open panel.
struct CompactProposalView: View {
    enum State {
        case nextMeeting(time: String, minutes: Int)
        case recording(elapsed: String, levels: [Double])
        case dictation(levels: [Double])
        case processing(step: String, lit: Int)
        case tasks(count: Int)
    }

    let state: State
    let hardware: CGSize
    /// Both ears keep one width in every state, so the closed notch never changes size
    /// when its content changes.
    static let ear: CGFloat = 64

    var body: some View {
        NotchFlankLayout(gap: hardware.width + Hud.Space.x3) {
            leading.frame(width: Self.ear, alignment: .leading).padding(.leading, Hud.Space.x3)
            trailing.frame(width: Self.ear, alignment: .trailing).padding(.trailing, Hud.Space.x3)
        }
        .frame(height: hardware.height)
    }

    @ViewBuilder
    private var leading: some View {
        switch state {
        case .nextMeeting(let time, _):
            HStack(spacing: 6) { HudIcon(.calendar, size: 13).foregroundStyle(Hud.Ink.text3); Text(time).hud(.numeral, Hud.Ink.text1) }
        case .recording(let elapsed, _):
            HStack(spacing: 6) { HudIcon(.record, size: 13).foregroundStyle(Hud.Ink.live); Text(elapsed).hud(.numeral, Hud.Ink.text1) }
        case .dictation:
            HudIcon(.mic, size: 13).foregroundStyle(Hud.Ink.text1)
        case .processing:
            HudIcon(.spark, size: 13).foregroundStyle(Hud.Ink.text2)
        case .tasks:
            HudIcon(.queue, size: 13).foregroundStyle(Hud.Ink.text2)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .nextMeeting(_, let minutes):
            Text("\(minutes) dk").hud(.numeral, minutes <= 10 ? Hud.Ink.signal : Hud.Ink.text2)
        case .recording(_, let levels):
            HudLevelMeter(levels: levels, tint: Hud.Ink.text1)
        case .dictation(let levels):
            HudLevelMeter(levels: levels, tint: Hud.Ink.text1)
        case .processing(let step, let lit):
            HStack(spacing: 6) {
                Text(step).hud(.label, Hud.Ink.text2)
                HudSegmentMeter(segments: 5, lit: lit, tint: Hud.Ink.text2, height: 6, spacing: 1.5).frame(width: 22)
            }
        case .tasks(let count):
            Text("\(count)").hud(.numeral, Hud.Ink.text2)
        }
    }
}
