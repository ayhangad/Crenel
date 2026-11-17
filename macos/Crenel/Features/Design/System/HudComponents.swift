import SwiftUI

// MARK: - Surfaces

extension View {
    /// Well (`.well`): the recessed display window instruments sit in — `#050505 →
    /// #0a0a09`, a 2 px dark inner shadow, a 1 px 4.5 % ring and a 1 px 3.5 % light under
    /// the lower edge. Readouts, the player and the live recording card live in a well.
    func hudWell(radius: CGFloat = Hud.Radius.well) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            ZStack {
                shape.fill(Color(white: 1, opacity: 0.035)).offset(y: 1)
                shape.fill(
                    LinearGradient(colors: [Hud.Layer.wellTop, Hud.Layer.wellBottom], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(0.8), radius: 1, x: 0, y: 1))
                )
                shape.strokeBorder(Color(white: 1, opacity: 0.045), lineWidth: 1)
            }
        }
    }

    /// Panel (`.panel`, `.tile`): raised a hair off the window floor. Radius 16.
    func hudPanel(radius: CGFloat = Hud.Radius.panel, isHovering: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            ZStack {
                shape.fill(
                    LinearGradient(colors: [Color(white: 1, opacity: isHovering ? 0.05 : 0.035), Color(white: 1, opacity: isHovering ? 0.026 : 0.018)],
                                   startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: Color(white: 1, opacity: 0.035), radius: 0, x: 0, y: 1))
                )
                shape.strokeBorder(Color(white: 1, opacity: 0.05), lineWidth: 1)
            }
        }
    }

    /// Sheet (`.sheet`): the detail page, one layer up — `#121211`, radius 14.
    func hudSheet(radius: CGFloat = Hud.Radius.sheet) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            ZStack {
                shape.fill(Color.black.opacity(0.35)).blur(radius: 15).offset(y: 10)
                shape.fill(Hud.Layer.sheet.shadow(.inner(color: Color(white: 1, opacity: 0.04), radius: 0, x: 0, y: 1)))
                shape.strokeBorder(Color(white: 1, opacity: 0.055), lineWidth: 1)
            }
        }
        .clipShape(shape)
        .hudSurface(Hud.Layer.sheet)
    }

    /// Settings group card (`.sgroup`): radius 14, 6 pt padding, the header inside.
    func hudGroupCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Hud.Radius.sheet, style: .continuous)
        return padding(6).background {
            ZStack {
                shape.fill(Color(white: 1, opacity: 0.022))
                shape.strokeBorder(Color(white: 1, opacity: 0.045), lineWidth: 1)
            }
        }
    }

    /// The one line under the ears of a strip notch (`.strip`): 38 pt, radius 12.
    func hudStrip() -> some View {
        padding(.leading, 10).padding(.trailing, 6)
            .frame(height: Hud.Notch.stripHeight)
            .background(RoundedRectangle(cornerRadius: Hud.Notch.stripRadius, style: .continuous).fill(Hud.Ink.field))
    }
}

/// A hairline between compartments of a well: a 4 % 1 px shade, not a rule.
struct HudWellDivider: View {
    var body: some View {
        Rectangle().fill(Color(white: 1, opacity: 0.04)).frame(width: 1)
    }
}

/// Frame (`.frame`): a 1 px 8 % printed outline with its label inside, top-left. Only
/// for the Details group of a meeting.
///
///     HudFrame("Details") { rows }
struct HudFrame<Content: View>: View {
    let label: Text
    @ViewBuilder var content: () -> Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.label = Text(label)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .overlay(alignment: .topLeading) {
                label.hud(.micro, Hud.Ink.ink3).padding(.top, 7).padding(.leading, 12)
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(white: 1, opacity: 0.08), lineWidth: 1))
    }
}

// MARK: - Group header

/// A group title (`.group-h`): label in ink-3, an optional dim count beside it, an
/// optional trailing readout (cells, a small button). No rule, no caps.
///
///     HudGroupHeader(title: "Today", count: 3)
///     HudGroupHeader(title: "Today") { HudCells(done: 1, total: 5) }
struct HudGroupHeader<Trailing: View>: View {
    let title: Text
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    init(title: LocalizedStringKey, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Text(title)
        self.count = count
        self.trailing = trailing
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Text(title)
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            title.hud(.label, Hud.Ink.ink3)
            if let count {
                Text(verbatim: "\(count)").hud(.label, Hud.Ink.ink4)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .lineLimit(1)
        .padding(.horizontal, Hud.Row.inset)
        .padding(.top, 6)
        .frame(height: Hud.Row.groupHeader, alignment: .top)
        .padding(.bottom, 2)
    }
}

extension HudGroupHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

// MARK: - Rows

/// Row boxes. Text never moves: every row keeps its height and insets in every state;
/// the hover slab (`hudGlide`) slides underneath.
///
///     HudRow(.twoLine) { HudTimeColumn("16:00"); HudIcon(.place); titles }
///         .hudGlide(id, hovered: $hovered, in: namespace)
struct HudRow<Content: View>: View {
    enum Kind: Sendable {
        /// `.row` — 50 pt, content top-aligned 9 pt down.
        case twoLine
        /// `.row-1` — 48 pt, centred.
        case oneLine
        /// `.trow` — 38 pt, centred.
        case task
    }

    var kind: Kind = .twoLine
    @ViewBuilder var content: () -> Content

    init(_ kind: Kind = .twoLine, @ViewBuilder content: @escaping () -> Content) {
        self.kind = kind
        self.content = content
    }

    var body: some View {
        HStack(alignment: kind == .twoLine ? .top : .center, spacing: Hud.Row.gap) { content() }
            .padding(.horizontal, Hud.Row.inset)
            .padding(.top, kind == .twoLine ? Hud.Row.twoLineTop : 0)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: kind == .twoLine ? .topLeading : .leading)
            .contentShape(Rectangle())
    }

    private var height: CGFloat {
        switch kind {
        case .twoLine: Hud.Row.twoLine
        case .oneLine: Hud.Row.oneLine
        case .task: Hud.Row.task
        }
    }
}

/// The 42 pt time column of timetable rows (`.tcol`): the start time, and under it an
/// optional meta (a duration in Recordings). Right-aligned.
struct HudTimeColumn: View {
    let top: String
    var bottom: String?
    var dim = false

    init(_ top: String, _ bottom: String? = nil, dim: Bool = false) {
        self.top = top
        self.bottom = bottom
        self.dim = dim
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            // "24 Nov" is a little wider than the column: shrink it rather than cut it.
            Text(verbatim: top).hud(.body, dim ? Hud.Ink.ink2 : Hud.Ink.ink1).minimumScaleFactor(0.8)
            if let bottom {
                Text(verbatim: bottom).hud(.meta)
            }
        }
        .lineLimit(1)
        .frame(width: Hud.Row.timeColumn, alignment: .trailing)
    }
}

// MARK: - Date tile

/// A day as a small well (`.dtile`): the day of the month in segment digits over a short
/// word — the month in Recordings, the weekday in Today's later events — or, for an
/// event today, just its start time. It is at least as tall as its own content plus
/// 6 pt above and below, and stretches to the row when the row is taller; centre the
/// row (`HStack(alignment: .center)`) and fix its height
/// (`.fixedSize(horizontal: false, vertical: true)`). An optional corner lamp marks a row
/// that needs something; rows that are fine have none.
///
///     HudDateTile(date: meeting.startedAt, caption: .month)
///     HudDateTile(date: event.startDate, caption: .weekday, lamp: .amber)
///     HudDateTile(time: event.startDate)          // today: "16:00"
///     HudDateTile(allDay: Date())                 // today, all day
struct HudDateTile: View {
    enum Caption { case month, weekday }
    enum Content { case day(Caption), time, allDay }

    let date: Date
    var content: Content = .day(.month)
    var lamp: Hud.LampColor?
    var lampLoop: HudLoop = .steady
    var calendar: Calendar = .current

    static let width: CGFloat = 44
    static let verticalPadding: CGFloat = 6

    init(date: Date, caption: Caption = .month, lamp: Hud.LampColor? = nil, lampLoop: HudLoop = .steady,
         calendar: Calendar = .current) {
        self.date = date
        content = .day(caption)
        self.lamp = lamp
        self.lampLoop = lampLoop
        self.calendar = calendar
    }

    init(time: Date, lamp: Hud.LampColor? = nil, lampLoop: HudLoop = .steady) {
        date = time
        content = .time
        self.lamp = lamp
        self.lampLoop = lampLoop
    }

    init(allDay date: Date, lamp: Hud.LampColor? = nil) {
        self.date = date
        content = .allDay
        self.lamp = lamp
    }

    var body: some View {
        Group {
            switch content {
            case .day:
                VStack(spacing: 4) {
                    HudSegmentDigits(String(format: "%02d", calendar.component(.day, from: date)), height: 15, cells: 2)
                    Text(verbatim: word).hud(.micro, Hud.Ink.ink3)
                }
            case .time:
                HudSegmentDigits(HudFormat.clock(date), height: 12)
            case .allDay:
                Text("All day").hud(.micro, Hud.Ink.ink3).multilineTextAlignment(.center)
            }
        }
        .lineLimit(2)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                }
        }
        .overlay(alignment: .topTrailing) {
            if let lamp {
                HudLamp(lamp, form: .dot, loop: lampLoop).offset(x: 2, y: -2)
            }
        }
        .accessibilityHidden(true)
    }

    private var word: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if case .day(.weekday) = content { formatter.dateFormat = "EEE" } else { formatter.dateFormat = "MMM" }
        return formatter.string(from: date)
    }
}

/// A list's group header in the row language: the name on the left, the count at the
/// trailing edge, both quiet.
///
///     HudListHeader("September", count: 2)
struct HudListHeader: View {
    let title: String
    var count: Int?
    var isFirst = false

    init(_ title: String, count: Int? = nil, isFirst: Bool = false) {
        self.title = title
        self.count = count
        self.isFirst = isFirst
    }

    var body: some View {
        HStack {
            Text(verbatim: title)
            Spacer(minLength: 8)
            if let count { Text(verbatim: "\(count)").monospacedDigit() }
        }
        .hud(.meta, Hud.Ink.ink4)
        .padding(.horizontal, Hud.Row.inset)
        .padding(.top, isFirst ? 2 : 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Glide highlight (hover slab)

/// One hover slab per list (`.slab`) that slides between rows instead of each row
/// fading its own fill: 0.18 s `cubic-bezier(.2,.8,.2,1)`. Rows report hover; the list
/// owns the slab.
struct HudGlide: ViewModifier {
    let id: AnyHashable
    @Binding var hovered: AnyHashable?
    let namespace: Namespace.ID
    var forced: AnyHashable?

    func body(content: Content) -> some View {
        content
            .background {
                if (forced ?? hovered) == id {
                    RoundedRectangle(cornerRadius: Hud.Row.radius, style: .continuous)
                        .fill(Hud.Ink.hover)
                        .matchedGeometryEffect(id: "hud.glide", in: namespace)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    withAnimation(Hud.Motion.slab) { hovered = id }
                } else {
                    // Leaving one row and entering the next arrive as two events in either
                    // order. Clearing at once would drop the slab between them, so it fades
                    // out and back in instead of sliding. Wait a beat: if another row took
                    // over meanwhile, there is nothing to clear.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        guard hovered == id else { return }
                        withAnimation(Hud.Motion.slab) { hovered = nil }
                    }
                }
            }
    }
}

extension View {
    func hudGlide(_ id: AnyHashable, hovered: Binding<AnyHashable?>, in namespace: Namespace.ID, forced: AnyHashable? = nil) -> some View {
        modifier(HudGlide(id: id, hovered: hovered, namespace: namespace, forced: forced))
    }
}

// MARK: - Tabs

private struct HudLampBoundsKey: PreferenceKey {
    static let defaultValue: [AnyHashable: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Tabs (`.tabs`): words with a lamp under the live one. The lamp — a 2 pt lit line the
/// width of the word — slides between tabs: 0.32 s `cubic-bezier(.3,1.25,.4,1)`.
///
///     HudTabs(items: [.init(tab: Tab.today, title: "Today"), .init(tab: .tasks, title: "Tasks", badge: 5)],
///             selection: $tab)
struct HudTabs<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        /// Unused by the night-drive tabs (words only); kept for older call sites.
        var glyph: HudGlyph?
        let title: String
        var badge: Int?

        init(tab: Tab, glyph: HudGlyph? = nil, title: String, badge: Int? = nil) {
            self.tab = tab
            self.glyph = glyph
            self.title = title
            self.badge = badge
        }
    }

    let items: [Item]
    @Binding var selection: Tab
    @State private var hovered: Tab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items, id: \.tab) { item in
                let isSelected = item.tab == selection
                Button {
                    selection = item.tab
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.title)
                            .hud(.label, isSelected ? Hud.Ink.ink1 : (hovered == item.tab ? Hud.Ink.ink2 : Hud.Ink.ink3))
                            .anchorPreference(key: HudLampBoundsKey.self, value: .bounds) { [AnyHashable(item.tab): $0] }
                        if let badge = item.badge {
                            Text(verbatim: "\(badge)").hud(.meta, isSelected ? Hud.Ink.ink3 : Hud.Ink.ink4)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, 7)
                    .frame(height: 30, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.tab : (hovered == item.tab ? nil : hovered) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlayPreferenceValue(HudLampBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[AnyHashable(selection)] {
                    let rect = proxy[anchor]
                    Capsule().fill(Hud.Ink.ink1)
                        .shadow(color: Hud.Ink.ink1.opacity(0.6), radius: 3)
                        .frame(width: rect.width, height: 2)
                        .offset(x: rect.minX, y: proxy.size.height - 3)
                        .animation(reduceMotion ? nil : Hud.Motion.tabLamp, value: rect)
                }
            }
            .allowsHitTesting(false)
        }
        .animation(Hud.Motion.hover, value: hovered)
    }
}

// MARK: - Rail

/// Rail (`.rail`): a vertical list whose selection lamp — 3×14 pt, lit — slides between
/// items: 0.34 s `cubic-bezier(.3,1.2,.4,1)`. The selected place lights its icon (line →
/// solid). Each item can carry a dim readout on the right ("in 33 min", a count, "fn").
///
///     HudRail(items: [.init(value: Page.today, glyph: .gauge, title: "Today", readout: "in 33 min")],
///             selection: $page)
struct HudRail<Value: Hashable>: View {
    struct Item {
        let value: Value
        let glyph: HudGlyph
        let title: String
        var readout: String?
        /// A status lamp instead of a readout (the settings rail).
        var lamp: Hud.LampColor?

        init(value: Value, glyph: HudGlyph, title: String, readout: String? = nil, lamp: Hud.LampColor? = nil) {
            self.value = value
            self.glyph = glyph
            self.title = title
            self.readout = readout
            self.lamp = lamp
        }
    }

    let items: [Item]
    @Binding var selection: Value
    @State private var hovered: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 12) {
                        HudIcon(item.glyph, size: 16, solid: isSelected)
                            .foregroundStyle(isSelected ? Hud.Ink.ink1 : Hud.Ink.ink3)
                        Text(item.title).hud(.label, isSelected ? Hud.Ink.ink1 : Hud.Ink.ink2)
                        Spacer(minLength: 4)
                        if let lamp = item.lamp {
                            HudLamp(lamp)
                        }
                        if let readout = item.readout {
                            Text(readout).hud(.meta, isSelected ? Hud.Ink.ink3 : Hud.Ink.ink4)
                        }
                    }
                    .lineLimit(1)
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .frame(height: Hud.Window.railItem)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                        if isSelected {
                            shape.fill(LinearGradient(colors: [Color(white: 1, opacity: 0.075), Color(white: 1, opacity: 0.04)],
                                                      startPoint: .leading, endPoint: .trailing))
                        } else if hovered == item.value {
                            shape.fill(Color(white: 1, opacity: 0.04))
                        }
                    }
                    .contentShape(Rectangle())
                    .anchorPreference(key: HudLampBoundsKey.self, value: .bounds) { [AnyHashable(item.value): $0] }
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .overlayPreferenceValue(HudLampBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[AnyHashable(selection)] {
                    let rect = proxy[anchor]
                    Capsule().fill(Hud.Ink.ink1)
                        .shadow(color: Hud.Ink.ink1.opacity(0.75), radius: 3)
                        .shadow(color: Hud.Ink.ink1.opacity(0.22), radius: 7)
                        .frame(width: 3, height: 14)
                        .offset(x: 0, y: rect.midY - 7)
                        .animation(reduceMotion ? nil : Hud.Motion.railLamp, value: rect)
                }
            }
            .allowsHitTesting(false)
        }
        .animation(Hud.Motion.hover, value: hovered)
    }
}

// MARK: - Toggle

/// Switch (`.toggle`): a knob with a lamp in it. 32×18; on, the track is ink-1, the knob
/// is black and a teal lamp lights in its centre.
///
///     Toggle("Open at login", isOn: $value).toggleStyle(HudToggleStyle()).labelsHidden()
struct HudToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Button {
                configuration.isOn.toggle()
            } label: {
                HudSwitch(isOn: configuration.isOn)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

/// The switch body, for custom rows.
struct HudSwitch: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? Hud.Ink.ink1 : Color(white: 1, opacity: 0.1))
            Circle().fill(isOn ? Color.black : Hud.Ink.ink2)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().fill(Hud.Ink.ok).frame(width: 4, height: 4)
                        .shadow(color: Hud.Ink.ok, radius: 2.5)
                        .opacity(isOn ? 1 : 0)
                }
                .offset(x: isOn ? 16 : 2)
        }
        .frame(width: 32, height: 18)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Hud.Motion.toggle, value: isOn)
        .contentShape(Capsule())
    }
}

// MARK: - Select

/// The face of a select (`.select`): 28 pt field with the value and a small chevron.
struct HudSelectStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HudSelectBody(configuration: configuration)
    }
}

private struct HudSelectBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            configuration.label.hud(.label).lineLimit(1)
            HudIcon(.chevronDown, size: Hud.Size.smallIcon).foregroundStyle(Hud.Ink.ink3)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isHovering ? Hud.Ink.fieldFocus : Hud.Ink.field))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.hover, value: isHovering)
    }
}

/// A select: the value in a field; choosing opens the native menu.
///
///     HudSelect(selection: $retention, options: [(.forever, "Forever"), (.week, "7 days")])
struct HudSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// Listed but not choosable (announced options).
    var disabled: Set<Value> = []

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.title) { selection = option.value }
                    .disabled(disabled.contains(option.value))
            }
        } label: {
            Text(options.first { $0.value == selection }?.title ?? "")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HudSelectStyle())
        .fixedSize()
    }
}

// MARK: - Fields

extension View {
    /// A field well behind an input: white 5.5 %, 9 % when focused.
    /// `.sfield` is 32 pt / radius 8; the task input is 44 pt / radius 12 (8 % focused).
    func hudField(height: CGFloat = 32, radius: CGFloat = 8, isFocused: Bool = false, padding: CGFloat = 12) -> some View {
        self
            .padding(.horizontal, padding)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(isFocused ? Hud.Ink.fieldFocus : Hud.Ink.field))
            .animation(Hud.Motion.hover, value: isFocused)
    }
}

/// A one-line text field in a field well (`.sfield`).
///
///     HudTextField(text: $key, prompt: "sk-…")
struct HudTextField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey = ""
    var height: CGFloat = 32
    var radius: CGFloat = 8
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Hud.Ink.ink3))
            .textFieldStyle(.plain)
            .hud(.body)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .hudField(height: height, radius: radius, isFocused: isFocused)
    }
}

/// The toolbar search field (`.search`): 30 pt, sunken, with the search glyph.
struct HudSearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey = "Search"
    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 8) {
            HudIcon(.search, size: 14).foregroundStyle(Hud.Ink.ink3)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Hud.Ink.ink3))
                .textFieldStyle(.plain)
                .hud(.label)
                .focused($isFocused)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 30)
        .background(
            shape.fill(Color(white: 1, opacity: isFocused ? 0.075 : 0.045).shadow(.inner(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 1)))
        )
        .overlay(shape.strokeBorder(Color(white: 1, opacity: 0.05), lineWidth: 1))
        .animation(Hud.Motion.hover, value: isFocused)
    }
}

/// The lit text cursor of live dictation (`.caret`): 7×14, blinking once a second.
struct HudCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let block = RoundedRectangle(cornerRadius: 1).fill(Hud.Ink.ink1)
            .shadow(color: Hud.Ink.ink1.opacity(0.6), radius: 3)
            .frame(width: 7, height: 14)
        if reduceMotion {
            block
        } else {
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: Hud.Motion.caretPeriod / 2)) { timeline in
                block.opacity(Int(timeline.date.timeIntervalSinceReferenceDate / (Hud.Motion.caretPeriod / 2)) % 2 == 0 ? 1 : 0)
            }
        }
    }
}

// MARK: - Chips

/// Chips. Parsed task values are chips with a lamp; clicking one drops the value.
///
///     HudChip("Today 15:00", lamp: .amber)                       // `.chip`
///     HudChip("High priority", glyph: .plus, style: .outline)    // `.chip-out`
///     HudChip("48 min", glyph: .clock, style: .tag)              // `.chip-s`
struct HudChip<Leading: View>: View {
    enum Style: Sendable {
        /// `.chip` — 22 pt, white 6 %, ink-2.
        case filled
        /// `.chip-out` — 22 pt, no fill, ink-3: a suggestion.
        case outline
        /// `.chip-s` — 24 pt, white 4.5 % with a ring: static meta (date, length, people).
        case tag
    }

    let title: Text
    var style: Style = .filled
    @ViewBuilder var leading: () -> Leading
    @State private var isHovering = false

    init(_ title: LocalizedStringKey, style: Style = .filled, @ViewBuilder leading: @escaping () -> Leading) {
        self.title = Text(title)
        self.style = style
        self.leading = leading
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, style: Style = .filled, @ViewBuilder leading: @escaping () -> Leading) {
        self.title = Text(title)
        self.style = style
        self.leading = leading
    }

    var body: some View {
        let radius: CGFloat = style == .tag ? 7 : 6
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        HStack(spacing: 6) {
            leading()
            title.hud(.meta, style == .outline ? (isHovering ? Hud.Ink.ink2 : Hud.Ink.ink3) : Hud.Ink.ink2)
        }
        .lineLimit(1)
        .padding(.leading, 8)
        .padding(.trailing, style == .filled ? 10 : 8)
        .frame(height: style == .tag ? 24 : 22)
        .background {
            switch style {
            case .filled: shape.fill(Color(white: 1, opacity: isHovering ? 0.09 : 0.06))
            case .outline: shape.fill(Color(white: 1, opacity: isHovering ? 0.05 : 0))
            case .tag: shape.fill(Color(white: 1, opacity: 0.045))
            }
        }
        .overlay {
            if style == .tag { shape.strokeBorder(Color(white: 1, opacity: 0.04), lineWidth: 1) }
        }
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.hover, value: isHovering)
    }
}

extension HudChip where Leading == AnyView {
    init(_ title: LocalizedStringKey, lamp: Hud.LampColor? = nil, glyph: HudGlyph? = nil, style: Style = .filled) {
        self.init(title, style: style) { Self.leadingView(lamp: lamp, glyph: glyph) }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, lamp: Hud.LampColor? = nil, glyph: HudGlyph? = nil, style: Style = .filled) {
        self.init(title, style: style) { Self.leadingView(lamp: lamp, glyph: glyph) }
    }

    private static func leadingView(lamp: Hud.LampColor?, glyph: HudGlyph?) -> AnyView {
        AnyView(Group {
            if let lamp { HudLamp(lamp) }
            if let glyph { HudIcon(glyph, size: Hud.Size.smallIcon).foregroundStyle(Hud.Ink.ink3) }
        })
    }
}

// MARK: - Segmented control and pills

/// Segmented control (`.seg-ctl`): 26 pt items in a 4 % tray; the chosen one is white
/// 10 %. Items can carry a leading view (priority bars).
///
///     HudSegmented(items: [(Priority.none, "None"), (.low, "Low")], selection: $priority)
///     HudSegmented(items: items, selection: $priority) { HudPriorityBars(level: $0.level) }
struct HudSegmented<Value: Hashable, Leading: View>: View {
    let items: [(value: Value, title: String)]
    @Binding var selection: Value
    @ViewBuilder var leading: (Value) -> Leading
    @State private var hovered: Value?

    init(items: [(value: Value, title: String)], selection: Binding<Value>, @ViewBuilder leading: @escaping (Value) -> Leading) {
        self.items = items
        _selection = selection
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 6) {
                        leading(item.value)
                        Text(item.title).hud(.label, isSelected ? Hud.Ink.ink1 : (hovered == item.value ? Hud.Ink.ink2 : Hud.Ink.ink3))
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isSelected ? Hud.Ink.selected : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 1, opacity: 0.04)))
        .animation(Hud.Motion.hover, value: selection)
    }
}

extension HudSegmented where Leading == EmptyView {
    init(items: [(value: Value, title: String)], selection: Binding<Value>) {
        self.init(items: items, selection: selection) { _ in EmptyView() }
    }
}

/// Pill (`.pill`): a 26 pt toggle word; on, white 10 %.
struct HudPillStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        HudPillBody(isOn: isOn, configuration: configuration)
    }
}

private struct HudPillBody: View {
    let isOn: Bool
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .hud(.label, isOn ? Hud.Ink.ink1 : Hud.Ink.ink2)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(white: 1, opacity: isOn ? 0.10 : (isHovering ? 0.06 : 0))))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(Hud.Motion.hover, value: isHovering)
    }
}

// MARK: - Annunciator

/// Mode indicator (`.annun`): printed words; the chosen one lights (ink-1 with an 8 px
/// glow), the rest stay as ghosts (`#3a3936`). Sentence case, natural tracking. A word
/// can carry a count, which lights amber. Used for the Meetings filter and the
/// Dictation mode.
///
///     HudAnnunciator(items: [.init(Filter.all, "All"), .init(.needsYou, "Needs you", count: 2)], selection: $filter)
struct HudAnnunciator<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var count: Int?

        init(_ value: Value, _ title: String, count: Int? = nil) {
            self.value = value
            self.title = title
            self.count = count
        }
    }

    let items: [Item]
    @Binding var selection: Value
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.value) { item in
                let isOn = item.value == selection
                let ink = isOn ? Hud.Ink.ink1 : (hovered == item.value ? Hud.Ink.ink3 : Hud.Ink.ghostWord)
                Button {
                    selection = item.value
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.title).hud(.label, ink)
                            .shadow(color: isOn ? Hud.Ink.ink1.opacity(0.45) : .clear, radius: 4)
                        if let count = item.count {
                            Text(verbatim: "\(count)").hud(.label, isOn ? Hud.Ink.signal : ink)
                                .shadow(color: isOn ? Hud.Ink.signal.opacity(0.5) : .clear, radius: 4)
                        }
                    }
                    .lineLimit(1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item.value : (hovered == item.value ? nil : hovered) }
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .animation(Hud.Motion.toggle, value: selection)
        .animation(Hud.Motion.toggle, value: hovered)
    }
}

// MARK: - Small parts

/// Stacked initials (`.faces`): 22 pt discs overlapping by 6 pt.
struct HudFaces: View {
    let initials: [String]
    @Environment(\.hudSurface) private var surface

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(initials.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text)
                    .font(Hud.font(10, .semibold))
                    .foregroundStyle(Hud.Ink.ink2)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(hud: 0x1B1B1A)))
                    .overlay(Circle().strokeBorder(Color(white: 1, opacity: 0.08), lineWidth: 1))
                    .background(Circle().fill(surface).padding(-2))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The printed key of the Dictation page (`.keycap`): 76×72 with a lamp in the corner.
///
///     HudBigKeycap("fn", glyph: .globe, lamp: .teal)
struct HudBigKeycap: View {
    let label: String
    var glyph: HudGlyph?
    var lamp: Hud.LampColor = .off

    init(_ label: String, glyph: HudGlyph? = nil, lamp: Hud.LampColor = .off) {
        self.label = label
        self.glyph = glyph
        self.lamp = lamp
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .trailing, spacing: 0) {
            HudLamp(lamp)
            Spacer(minLength: 0)
            HStack {
                Text(verbatim: label).font(Hud.font(13, .medium)).foregroundStyle(Hud.Ink.ink2)
                Spacer(minLength: 0)
                if let glyph {
                    HudIcon(glyph, size: 14).foregroundStyle(Hud.Ink.ink3)
                }
            }
        }
        .padding(10)
        .frame(width: 76, height: 72)
        .background {
            ZStack {
                shape.fill(Color.black.opacity(0.6)).blur(radius: 6).offset(y: 5)
                shape.fill(Color(hud: 0x050505)).offset(y: 4)
                shape.fill(
                    LinearGradient(colors: [Color(hud: 0x232321), Color(hud: 0x161615)], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: Color(white: 1, opacity: 0.1), radius: 0, x: 0, y: 1))
                )
                shape.strokeBorder(Color(white: 1, opacity: 0.06), lineWidth: 1)
            }
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

/// Page header icon tile (`.ph-icon`): a 40 pt raised tile for settings pages.
struct HudIconTile: View {
    let glyph: HudGlyph
    var solid = true

    init(_ glyph: HudGlyph, solid: Bool = true) {
        self.glyph = glyph
        self.solid = solid
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        HudIcon(glyph, size: 16, solid: solid)
            .foregroundStyle(Hud.Ink.ink1)
            .frame(width: 40, height: 40)
            .background {
                ZStack {
                    HudOuterShadow(shape: shape, color: .black.opacity(0.5), radius: 1.5, y: 1)
                    shape.fill(
                        LinearGradient(colors: [Color(white: 1, opacity: 0.09), Color(white: 1, opacity: 0.03)],
                                       startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
                            .shadow(.inner(color: Color(white: 1, opacity: 0.07), radius: 0, x: 0, y: 1))
                    )
                    shape.strokeBorder(Color(white: 1, opacity: 0.07), lineWidth: 1)
                }
            }
    }
}

/// A small ring spinner (`.spin`) for sub-second waits (saving a key). For anything
/// longer use `HudBusy` or the scanner.
struct HudSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hudVisibility) private var visibility
    private var motionPaused: Bool { visibility?.isHidden ?? false }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || motionPaused)) { timeline in
            ZStack {
                Circle().stroke(Color(white: 1, opacity: 0.2), lineWidth: 1.5)
                Circle().trim(from: 0, to: 0.25).stroke(Color(white: 1, opacity: 0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }
            .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Legacy meters

/// Legacy segmented bar; new screens use `HudCells`, `HudVUMeter` or `HudStations`.
struct HudSegmentMeter: View {
    let segments: Int
    /// 0…1.
    let progress: Double
    var tint: Color = Hud.Ink.text1
    var height: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - spacing * CGFloat(segments - 1)) / CGFloat(segments)
            HStack(spacing: spacing) {
                ForEach(0..<segments, id: \.self) { index in
                    let fill = min(1, max(0, progress * Double(segments) - Double(index)))
                    ZStack {
                        RoundedRectangle(cornerRadius: 1).fill(Color(white: 1, opacity: 0.07))
                        RoundedRectangle(cornerRadius: 1).fill(tint).opacity(fill)
                    }
                    .frame(width: max(1, width))
                }
            }
        }
        .frame(height: height)
        .animation(Hud.Motion.change, value: progress)
    }
}

/// Legacy voice meter: bars that rise with the level. New screens use `HudLadder`.
struct HudLevelMeter: View {
    let levels: [Double]
    var tint: Color = Hud.Ink.text1

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: 3 + 11 * max(0, min(1, level)))
            }
        }
        .frame(height: 14)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: levels)
    }
}

// MARK: - Ears

/// Places the two ears of the closed notch beside the camera housing. Both ears share
/// one width — the wider content plus padding — and each content is centred in its ear,
/// so the notch stays balanced and only as wide as the current state needs.
struct HudEarsLayout: Layout {
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

// MARK: - Formatting

enum HudFormat {
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Today", "Tomorrow", or a short weekday and day ("Tue 17").
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    /// Time left as segment text: "2h 37m", "45m". The gap is `HudSegmentArt.thinSpace`.
    static func remaining(minutes: Int) -> String {
        let minutes = max(0, minutes)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h\(HudSegmentArt.thinSpace)\(String(format: "%02d", minutes % 60))m"
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
