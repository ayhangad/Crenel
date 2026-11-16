import Combine
import SwiftUI

// MARK: - Model

/// Plain values for the proposal surfaces, so they can be reviewed before they replace
/// the live ones.
struct ProposalEvent: Identifiable, Equatable {
    enum Venue: Equatable { case none, online(String), place(String) }

    let id = UUID()
    let title: String
    let start: Date
    let end: Date
    var venue: Venue = .none
}

struct ProposalTask: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var state: TaskStatus
    var due: String?
}

enum ProposalTab: Hashable { case today, tasks }

enum ProposalCompact: Equatable {
    case nextMeeting
    case recording(started: Date)
    case dictation
    case processing(step: Int)
    case tasks
    case idle
}

@MainActor
final class ProposalNotchModel: ObservableObject {
    @Published var isOpen: Bool
    @Published var tab: ProposalTab
    @Published var now: Date
    @Published var events: [ProposalEvent]
    @Published var tasks: [ProposalTask]
    @Published var compact: ProposalCompact
    @Published var levels: [Double] = [0.3, 0.6, 0.9, 0.5, 0.25]
    /// Titles used before, for inline completion while typing a task.
    @Published var history: [String] = ["Write weekly report", "Pay invoice", "Gym", "Sprint planning"]
    /// For static renders: which row shows the hover highlight.
    var forcedHover: AnyHashable?
    /// For static renders: text shown in the task input instead of a live field.
    var staticInput: String?

    init(isOpen: Bool = false, tab: ProposalTab = .today, now: Date, events: [ProposalEvent],
         tasks: [ProposalTask], compact: ProposalCompact = .nextMeeting) {
        self.isOpen = isOpen
        self.tab = tab
        self.now = now
        self.events = events
        self.tasks = tasks
        self.compact = compact
    }

    /// Sample day built around `now`: a meeting starting in eight minutes.
    static func sample(now: Date = Date(), isOpen: Bool = false) -> ProposalNotchModel {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int, day: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        let soon = now.addingTimeInterval(8 * 60)
        return ProposalNotchModel(
            isOpen: isOpen,
            now: now,
            events: [
                ProposalEvent(title: "Product weekly sync", start: soon, end: soon.addingTimeInterval(45 * 60), venue: .online("Google Meet")),
                ProposalEvent(title: "Design review", start: soon.addingTimeInterval(95 * 60), end: soon.addingTimeInterval(155 * 60), venue: .place("Room 2")),
                ProposalEvent(title: "Edda Dev. Sync", start: at(18, 0, day: 1), end: at(18, 30, day: 1), venue: .online("Google Meet")),
                ProposalEvent(title: "BB Dev. Sync", start: at(18, 30, day: 1), end: at(19, 0, day: 1), venue: .online("Zoom")),
                ProposalEvent(title: "1:1 with Selin", start: at(10, 0, day: 2), end: at(10, 30, day: 2))
            ],
            tasks: [
                ProposalTask(title: "Finish onboarding flow", state: .inProgress, due: "Today"),
                ProposalTask(title: "Legal sign-off", state: .blocked),
                ProposalTask(title: "Write weekly report", state: .open, due: "17:00"),
                ProposalTask(title: "Call mom", state: .open),
                ProposalTask(title: "Share sprint notes", state: .completed)
            ]
        )
    }
}

// MARK: - Root: one shape that morphs between closed and open

/// The notch is one shape that always contains its content. Content is laid out at its
/// natural size; the shape's frame follows that size with a spring and clips whatever
/// is still outside it, so opening reads as the notch growing, not content appearing.
struct ProposalNotchView: View {
    @ObservedObject var model: ProposalNotchModel
    let hardware: CGSize
    @State private var size: CGSize = .zero

    var body: some View {
        let shape = CrenelNotchShape(topRadius: model.isOpen ? 12 : 6, bottomRadius: model.isOpen ? 20 : 10)
        ZStack(alignment: .top) {
            if model.isOpen {
                ProposalPanel(model: model, hardware: hardware)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.24).delay(0.12)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))
                    ))
            } else {
                ProposalCompactView(model: model, hardware: hardware)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.16)),
                        removal: .opacity.animation(.easeOut(duration: 0.06))
                    ))
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            if size == .zero {
                size = newSize
            } else {
                withAnimation(Hud.Motion.morph) { size = newSize }
            }
        }
        .frame(width: max(size.width, 1), height: max(size.height, 1), alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .animation(Hud.Motion.morph, value: model.isOpen)
    }
}

// MARK: - Open panel

struct ProposalPanel: View {
    @ObservedObject var model: ProposalNotchModel
    let hardware: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: hardware.height)
            toolbar.padding(.top, Hud.Space.x2)

            ZStack(alignment: .top) {
                switch model.tab {
                case .today:
                    ProposalToday(model: model)
                        .transition(.opacity.combined(with: .offset(x: -14)))
                case .tasks:
                    ProposalTasks(model: model)
                        .transition(.opacity.combined(with: .offset(x: 14)))
                }
            }
            .padding(.top, Hud.Space.x4)
        }
        .padding(.horizontal, Hud.Size.panelInset - Hud.Size.rowInset)
        .padding(.bottom, Hud.Space.x3)
        .frame(width: Hud.Size.panelWidth)
    }

    /// Tabs centred; tools on both sides, so the row is one toolbar.
    private var toolbar: some View {
        ZStack {
            HudTabs(items: [
                .init(tab: .today, glyph: .calendar, title: "Today"),
                .init(tab: .tasks, glyph: .queue, title: "Tasks", badge: model.tasks.filter { $0.state != .completed }.count)
            ], selection: $model.tab)
            HStack(spacing: 2) {
                Button {} label: { HudIcon(.history) }
                    .buttonStyle(HudButtonStyle(kind: .icon)).help("History")
                Spacer()
                Button {} label: { HudIcon(.window) }
                    .buttonStyle(HudButtonStyle(kind: .icon)).help("Open in window")
                Button {} label: { HudIcon(.pin) }
                    .buttonStyle(HudButtonStyle(kind: .icon)).help("Keep open")
            }
        }
    }
}

// MARK: - Today

struct ProposalToday: View {
    @ObservedObject var model: ProposalNotchModel
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    private var upcoming: [ProposalEvent] { model.events.filter { $0.end > model.now } }
    private var focus: ProposalEvent? { upcoming.first }
    private var rest: [ProposalEvent] { Array(upcoming.dropFirst()) }
    private var today: [ProposalEvent] { rest.filter { Calendar.current.isDate($0.start, inSameDayAs: model.now) } }
    private var later: [ProposalEvent] { rest.filter { !Calendar.current.isDate($0.start, inSameDayAs: model.now) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let focus {
                ProposalFocus(event: focus, now: model.now)
                    .hudGlide(focus.id, hovered: $hovered, in: glide, forced: model.forcedHover)
                    .padding(.bottom, Hud.Space.x3)
            }
            if !today.isEmpty {
                group("Today", today)
            }
            if !later.isEmpty {
                group("Later", later)
                    .padding(.top, today.isEmpty ? 0 : Hud.Space.x3)
            }
        }
    }

    private func group(_ title: String, _ events: [ProposalEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: title)
            ForEach(events) { event in
                ProposalEventRow(event: event, now: model.now)
                    .hudGlide(event.id, hovered: $hovered, in: glide, forced: model.forcedHover)
            }
        }
    }
}

/// What kind of event this is, as the row's leading icon: online, in a place, or a
/// plain calendar entry.
struct ProposalKindIcon: View {
    let venue: ProposalEvent.Venue
    var tint: Color = Hud.Ink.text3

    var body: some View {
        Group {
            switch venue {
            case .online: HudIcon(.video)
            case .place: HudIcon(.place)
            case .none: HudIcon(.calendar)
            }
        }
        .foregroundStyle(tint)
    }
}

extension ProposalEvent.Venue {
    /// The shortest word for where it happens; nil for plain events.
    var word: String? {
        switch self {
        case .none: nil
        case .online(let service): service
        case .place(let place): place
        }
    }
}

/// The next thing that needs you. No label and no buttons: its size and colour say
/// "next"; clicking it opens the meeting.
struct ProposalFocus: View {
    let event: ProposalEvent
    let now: Date

    private var untilStart: TimeInterval { event.start.timeIntervalSince(now) }
    private var isLive: Bool { untilStart <= 0 }
    private var isNear: Bool { untilStart > 0 && untilStart <= 60 * 60 }
    private var isUrgent: Bool { isLive || untilStart <= 10 * 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Hud.Space.x3) {
                ProposalKindIcon(venue: event.venue, tint: isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
                        Text(event.title).hud(.title).lineLimit(1)
                        Spacer(minLength: Hud.Space.x2)
                        Text(primaryValue).hud(.title, isUrgent ? Hud.Ink.signal : Hud.Ink.text1)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    HStack(spacing: Hud.Space.x2) {
                        Text(event.venue.word ?? "").hud(.meta, Hud.Ink.text3)
                        Spacer(minLength: Hud.Space.x2)
                        Text(secondaryValue).hud(.meta, Hud.Ink.text3)
                    }
                    if isNear || isLive {
                        HudSegmentMeter(segments: 28, progress: progress, tint: isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                            .padding(.top, Hud.Space.x2)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x3)
    }

    private var primaryValue: String {
        if isLive { return "\(max(1, Int(event.end.timeIntervalSince(now) / 60))) min" }
        if isNear { return "\(Int((untilStart / 60).rounded(.up))) min" }
        return ProposalFormat.clock(event.start)
    }

    private var secondaryValue: String {
        if isLive || isNear { return "\(ProposalFormat.clock(event.start)) – \(ProposalFormat.clock(event.end))" }
        return ProposalFormat.day(event.start, now: now)
    }

    /// Before the start the bar empties across the last hour; during the meeting it
    /// fills with elapsed time.
    private var progress: Double {
        if isLive { return now.timeIntervalSince(event.start) / event.end.timeIntervalSince(event.start) }
        return untilStart / 3_600
    }
}

/// Kind icon, then two lines: title and start on top; venue and end (or day) below.
struct ProposalEventRow: View {
    let event: ProposalEvent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: Hud.Space.x3) {
            ProposalKindIcon(venue: event.venue).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
                    Text(event.title).hud(.body).lineLimit(1)
                    Spacer(minLength: Hud.Space.x2)
                    Text(ProposalFormat.clock(event.start)).hud(.value, Hud.Ink.text2)
                }
                HStack(spacing: Hud.Space.x2) {
                    Text(event.venue.word ?? "").hud(.meta, Hud.Ink.text3)
                    Spacer(minLength: Hud.Space.x2)
                    Text(Calendar.current.isDate(event.start, inSameDayAs: now)
                         ? ProposalFormat.clock(event.end)
                         : ProposalFormat.day(event.start, now: now))
                        .hud(.meta, Hud.Ink.text3)
                }
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
    }
}

// MARK: - Tasks

struct ProposalTasks: View {
    @ObservedObject var model: ProposalNotchModel
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProposalTaskInput(model: model)
                .padding(.bottom, Hud.Space.x2)
            ForEach(model.tasks) { task in
                HStack(spacing: Hud.Space.x3) {
                    HudStateMark(state: task.state)
                    Text(task.title)
                        .hud(.body, task.state == .completed ? Hud.Ink.text3 : Hud.Ink.text1)
                        .lineLimit(1)
                    Spacer(minLength: Hud.Space.x2)
                    if let due = task.due {
                        Text(due).hud(.meta, Hud.Ink.text3)
                    }
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .frame(height: 38)
                .hudGlide(task.id, hovered: $hovered, in: glide)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
            }
        }
        .animation(Hud.Motion.glide, value: model.tasks)
    }
}

/// Type and press Return. While typing, dates, repeats and priority are recognised
/// live and shown as chips; a known title is completed inline (Tab accepts). When
/// nothing is recognised yet, quick picks offer the common dates.
struct ProposalTaskInput: View {
    @ObservedObject var model: ProposalNotchModel
    @State private var text = ""
    @FocusState private var focused: Bool
    private let parser = TaskInputParser()

    private var current: String { model.staticInput ?? text }
    private var suggestions: [TaskInputSuggestion] { parser.suggestions(for: current, now: model.now) }

    /// Inline completion from titles used before.
    private var completion: String? {
        let typed = current
        guard typed.count >= 2 else { return nil }
        let lower = typed.lowercased(with: Locale(identifier: "tr_TR"))
        return model.history.first { $0.lowercased(with: Locale(identifier: "tr_TR")).hasPrefix(lower) && $0.count > typed.count }
            .map { String($0.dropFirst(typed.count)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Hud.Space.x3) {
                HudIcon(.plus).foregroundStyle(current.isEmpty ? Hud.Ink.text3 : Hud.Ink.text1)
                ZStack(alignment: .leading) {
                    // Ghost completion sits behind the field, aligned to the typed text.
                    (Text(current).foregroundColor(.clear) + Text(completion ?? "").foregroundColor(Hud.Ink.text4))
                        .font(Hud.Style.body.font)
                        .lineLimit(1)
                    if let staticInput = model.staticInput {
                        Text(staticInput.isEmpty ? "Add task" : staticInput)
                            .hud(.body, staticInput.isEmpty ? Hud.Ink.text3 : Hud.Ink.text1)
                            .lineLimit(1)
                    } else {
                        TextField("", text: $text, prompt: Text("Add task").foregroundColor(Hud.Ink.text3))
                            .textFieldStyle(.plain)
                            .font(Hud.Style.body.font)
                            .foregroundStyle(Hud.Ink.text1)
                            .focused($focused)
                            .onSubmit(add)
                            .onKeyPress(.tab) {
                                guard let completion else { return .ignored }
                                text += completion
                                return .handled
                            }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous).fill(Hud.Ink.hover))

            // Below the field: what was recognised, or quick picks while nothing is.
            if !current.isEmpty {
                HStack(spacing: 4) {
                    if suggestions.isEmpty {
                        ForEach(["today", "tomorrow", "!!"], id: \.self) { pick in
                            Button {
                                text = current.trimmingCharacters(in: .whitespaces) + " " + pick
                            } label: {
                                chip(pick == "!!" ? "Priority" : pick.capitalized(with: AppLanguage.locale),
                                     glyph: pick == "!!" ? .bell : .calendar, tint: Hud.Ink.text3, dashed: true)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    } else {
                        ForEach(suggestions) { suggestion in
                            chip(suggestion.label, glyph: glyph(for: suggestion.kind), tint: tint(for: suggestion.kind))
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .animation(Hud.Motion.glide, value: suggestions.map(\.id))
                .padding(.horizontal, Hud.Size.rowInset)
                .padding(.top, Hud.Space.x2)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(Hud.Motion.change, value: current.isEmpty)
        .animation(Hud.Motion.change, value: suggestions.isEmpty)
    }

    private func chip(_ label: String, glyph: HudGlyph, tint: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            HudIcon(glyph, size: 11)
            Text(label).font(Hud.Style.meta.font)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background {
            if dashed {
                Capsule().strokeBorder(Hud.Ink.track, lineWidth: 1)
            } else {
                Capsule().fill(Hud.Ink.selected)
            }
        }
    }

    private func glyph(for kind: TaskInputSuggestion.Kind) -> HudGlyph {
        switch kind {
        case .due: .calendar
        case .recurrence: .history
        case .priority: .bell
        }
    }

    private func tint(for kind: TaskInputSuggestion.Kind) -> Color {
        if case .priority = kind { return Hud.Ink.signal }
        return Hud.Ink.text1
    }

    private func add() {
        let accepted = suggestions
        let result = parser.apply(accepted, to: text)
        guard !result.title.isEmpty else { return }
        let due = result.dueDate.map { parser.dueLabel(for: $0, hasTime: result.dueHasTime, now: model.now) }
        model.tasks.insert(ProposalTask(title: result.title, state: .open, due: due), at: 0)
        if !model.history.contains(result.title) { model.history.append(result.title) }
        text = ""
    }
}

// MARK: - Closed notch

/// Places the two ears beside the camera housing. Both ears share one width — the
/// wider content plus padding — and each content is centred in its ear, so the notch
/// stays balanced and only as wide as the current state needs.
struct ProposalEarsLayout: Layout {
    var gap: CGFloat
    var padding: CGFloat

    private func side(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max().map { $0 + padding * 2 } ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: side(subviews) * 2 + gap, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let ear = side(subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX + ear / 2, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.maxX - ear / 2, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}

struct ProposalCompactView: View {
    @ObservedObject var model: ProposalNotchModel
    let hardware: CGSize

    var body: some View {
        ProposalEarsLayout(gap: hardware.width, padding: Hud.Space.x4) {
            leading
            trailing
        }
        .frame(height: hardware.height)
        .animation(Hud.Motion.change, value: model.compact)
    }

    private var next: ProposalEvent? { model.events.first { $0.end > model.now } }

    @ViewBuilder
    private var leading: some View {
        switch model.compact {
        case .nextMeeting:
            HStack(spacing: 7) {
                if let next { ProposalKindIcon(venue: next.venue, tint: Hud.Ink.text3) }
                Text(next.map { ProposalFormat.clock($0.start) } ?? "").hud(.label, Hud.Ink.text1)
            }
        case .recording(let started):
            HStack(spacing: 7) {
                ProposalPulse(color: Hud.Ink.live)
                Text(ProposalFormat.elapsed(model.now.timeIntervalSince(started))).hud(.label, Hud.Ink.text1)
                    .contentTransition(.numericText())
            }
        case .dictation:
            HudIcon(.mic).foregroundStyle(Hud.Ink.text1)
        case .processing:
            HudIcon(.transcript).foregroundStyle(Hud.Ink.text2)
                .phaseAnimator([0.45, 1.0]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
        case .tasks:
            HudIcon(.queue).foregroundStyle(Hud.Ink.text2)
        case .idle:
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.compact {
        case .nextMeeting:
            if let next {
                let minutes = Int((next.start.timeIntervalSince(model.now) / 60).rounded(.up))
                Text(minutes > 60 ? ProposalFormat.day(next.start, now: model.now) : "\(max(0, minutes)) min")
                    .hud(.label, minutes <= 10 ? Hud.Ink.signal : Hud.Ink.text2)
                    .contentTransition(.numericText(countsDown: true))
            }
        case .recording, .dictation:
            HudLevelMeter(levels: model.levels, tint: Hud.Ink.text1)
        case .processing(let step):
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < step ? Hud.Ink.text2 : (index == step ? Hud.Ink.text1 : Hud.Ink.track))
                        .frame(width: index == step ? 10 : 4, height: 4)
                }
            }
        case .tasks:
            Text("\(model.tasks.filter { $0.state != .completed }.count)").hud(.label, Hud.Ink.text2)
        case .idle:
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

/// A dot that breathes while something is live.
struct ProposalPulse: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .phaseAnimator([1.0, 0.35]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
            .frame(width: Hud.Size.smallIcon, height: Hud.Size.smallIcon)
    }
}

// MARK: - Formatting

enum ProposalFormat {
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Today", "Tomorrow", or a short weekday and day ("Tue 17").
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
