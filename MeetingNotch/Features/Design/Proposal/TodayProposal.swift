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
    /// For static renders: which row shows the hover highlight.
    var forcedHover: AnyHashable?

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
                ProposalEvent(title: "Ürün haftalık senkron", start: soon, end: soon.addingTimeInterval(45 * 60), venue: .online("Google Meet")),
                ProposalEvent(title: "Tasarım incelemesi", start: soon.addingTimeInterval(95 * 60), end: soon.addingTimeInterval(155 * 60), venue: .place("Oda 2")),
                ProposalEvent(title: "Edda Dev. Sync", start: at(18, 0, day: 1), end: at(18, 30, day: 1), venue: .online("Google Meet")),
                ProposalEvent(title: "BB Dev. Sync", start: at(18, 30, day: 1), end: at(19, 0, day: 1), venue: .online("Zoom")),
                ProposalEvent(title: "Selin ile 1:1", start: at(10, 0, day: 2), end: at(10, 30, day: 2))
            ],
            tasks: [
                ProposalTask(title: "Onboarding akışını bitir", state: .inProgress, due: "Bugün"),
                ProposalTask(title: "Hukuk onayı", state: .blocked),
                ProposalTask(title: "Haftalık raporu yaz", state: .open, due: "17:00"),
                ProposalTask(title: "Annemi ara", state: .open),
                ProposalTask(title: "Sprint notlarını paylaş", state: .completed)
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
            HudTabs(items: [
                .init(tab: .today, glyph: .calendar, title: "Bugün"),
                .init(tab: .tasks, glyph: .queue, title: "Görevler", badge: model.tasks.filter { $0.state != .completed }.count)
            ], selection: $model.tab)
            .padding(.top, Hud.Space.x4)

            ZStack(alignment: .top) {
                switch model.tab {
                case .today:
                    ProposalToday(model: model)
                        .transition(.opacity.combined(with: .offset(x: -18)))
                case .tasks:
                    ProposalTasks(model: model)
                        .transition(.opacity.combined(with: .offset(x: 18)))
                }
            }
            .padding(.top, Hud.Space.x7)
        }
        .padding(.horizontal, Hud.Size.panelInset - Hud.Size.rowInset)
        .padding(.bottom, Hud.Space.x5)
        .frame(width: Hud.Size.panelWidth)
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
                    .padding(.bottom, Hud.Space.x4)
            }
            if !today.isEmpty {
                group("Bugün", today)
            }
            if !later.isEmpty {
                group("Sonra", later)
                    .padding(.top, today.isEmpty ? 0 : Hud.Space.x5)
            }
            footer.padding(.top, Hud.Space.x6)
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

    private var footer: some View {
        HStack(spacing: Hud.Space.x1) {
            Button {} label: {
                HStack(spacing: 8) { HudIcon(.history, size: Hud.Size.smallIcon); Text("Geçmiş") }
            }
            .buttonStyle(HudButtonStyle(kind: .ghost))
            Spacer()
            Button {} label: { HudIcon(.window) }.buttonStyle(HudButtonStyle(kind: .icon))
            Button {} label: { HudIcon(.pin) }.buttonStyle(HudButtonStyle(kind: .icon))
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
            HStack(alignment: .top, spacing: Hud.Space.x3 + 2) {
                ProposalKindIcon(venue: event.venue, tint: isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 7) {
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
                        HudSegmentMeter(segments: 32, progress: progress, tint: isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                            .padding(.top, Hud.Space.x3)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x3 + 2)
    }

    private var primaryValue: String {
        if isLive { return "\(max(1, Int(event.end.timeIntervalSince(now) / 60))) dk" }
        if isNear { return "\(Int((untilStart / 60).rounded(.up))) dk" }
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
        HStack(alignment: .top, spacing: Hud.Space.x3 + 2) {
            ProposalKindIcon(venue: event.venue).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
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

// MARK: - Tasks (to show tab switching)

struct ProposalTasks: View {
    @ObservedObject var model: ProposalNotchModel
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .frame(height: 46)
                .hudGlide(task.id, hovered: $hovered, in: glide)
            }
            HStack {
                Button {} label: {
                    HStack(spacing: 7) { HudIcon(.plus, size: Hud.Size.smallIcon); Text("Yeni görev") }
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
                Spacer()
            }
            .padding(.top, Hud.Space.x5)
        }
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
                Text(minutes > 60 ? ProposalFormat.day(next.start, now: model.now) : "\(max(0, minutes)) dk")
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
    private static let turkish = Locale(identifier: "tr_TR")

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = turkish
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Yarın", or a short weekday and day ("Sal 17").
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Bugün" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Yarın"
        }
        let formatter = DateFormatter()
        formatter.locale = turkish
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
