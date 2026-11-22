import SwiftUI

/// Shared layout values for every settings page (`tpl-desktop`, `s-*`), in the measure
/// model (`Hud.Layout`): every gap is a visible gap, ink to ink.
///
/// A page is its header, then one card holding all of its sections, then any page
/// actions, 28 apart. Inside the card the section labels and row ink sit 20 from the
/// card edge; rows carry 10 of padding on every side, so the card itself pads 10 (20 on
/// top, where a label leads). Label → first row 20, row → row 20, last row → next
/// label 28, last row → card edge 20.
enum SettingsLayout {
    /// Cards read best at a comfortable measure, not the full window width.
    static let contentWidth: CGFloat = 640
    /// The leading icon column: a 16 pt glyph laid out by its 13 pt ink.
    static let iconColumn: CGFloat = 16 - 2 * Hud.Layout.glyphInset
    /// Where row text starts, from the row's ink edge: icon ink 13 + 12.
    static let textInset: CGFloat = iconColumn + Hud.Row.gap

    /// Offscreen renders must not wait for entrance animations.
    static let isTesting = NSClassFromString("XCTestCase") != nil
}

// MARK: - Entrance

private struct SettingsShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Flips to true once a settings page is on screen; sections float in after it.
    var settingsShown: Bool {
        get { self[SettingsShownKey.self] }
        set { self[SettingsShownKey.self] = newValue }
    }
}

private struct SettingsStagger: ViewModifier {
    let index: Int
    @Environment(\.settingsShown) private var shown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if SettingsLayout.isTesting {
            content
        } else {
            content.hudStagger(index, shown: shown, reduceMotion: reduceMotion)
        }
    }
}

extension View {
    /// A section of a settings page: floats in 28 ms after the one before it.
    func settingsStagger(_ index: Int) -> some View {
        modifier(SettingsStagger(index: index))
    }
}

/// Holds one page; its sections enter once when the page changes.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Hud.Layout.section) {
            content
        }
        .environment(\.settingsShown, shown)
        .onAppear { shown = true }
    }
}

// MARK: - Page header

/// A page opens with its header (`.ph`): a 40 pt raised icon tile, the title and one
/// sentence 7 apart (both trimmed to their ink), and a readout on the right. The page
/// puts its first card 28 under it.
struct SettingsPageHeader<Readout: View>: View {
    let glyph: HudGlyph
    let title: LocalizedStringKey
    let sentence: LocalizedStringKey
    @ViewBuilder var readout: () -> Readout

    var body: some View {
        // Tile and readout share the page's top line (and the rail's first item's);
        // the title pair is centred on the tile.
        HStack(alignment: .top, spacing: Hud.Layout.block) {
            HStack(spacing: Hud.Layout.block) {
                HudIconTile(glyph, solid: false)
                VStack(alignment: .leading, spacing: Hud.Layout.pair) {
                    Text(title).hudTrimmed(.hero).accessibilityAddTraits(.isHeader)
                    Text(sentence).hudTrimmed(.meta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // A status word centres on the tile; a taller well starts on the top line.
            readout().frame(minHeight: 40)
        }
        .settingsStagger(0)
    }
}

extension SettingsPageHeader where Readout == EmptyView {
    init(glyph: HudGlyph, title: LocalizedStringKey, sentence: LocalizedStringKey) {
        self.init(glyph: glyph, title: title, sentence: sentence) { EmptyView() }
    }
}

/// Segment numbers in a well, one compartment per value (Calendar, Data).
struct SettingsReadoutWell: View {
    struct Value: Identifiable {
        let digits: String
        var unit: String?
        let label: LocalizedStringKey
        var id: String { digits + (unit ?? "") }
    }

    let values: [Value]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                if index > 0 { HudWellDivider() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        HudSegmentDigits(value.digits, height: 15)
                        if let unit = value.unit {
                            Text(verbatim: unit).hud(.unit)
                        }
                    }
                    Text(value.label).hud(.micro, Hud.Ink.ink3)
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 76, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(value.digits) \(value.unit ?? "")") + Text(" ") + Text(value.label))
            }
        }
        .padding(.vertical, 10)
        .fixedSize()
        .hudWell()
    }
}

// MARK: - Card, groups and rows

/// The one card of a page (`.sgroup`, radius 14): every section of the page inside it,
/// no rules between rows. Its edges sit 20 from the ink inside.
struct SettingsCard<Content: View>: View {
    /// A section label leads (the usual case); false when a row does, which carries its
    /// own 10 on top.
    var leadsWithLabel = true
    var index = 1
    @ViewBuilder let content: Content

    init(leadsWithLabel: Bool = true, index: Int = 1, @ViewBuilder content: () -> Content) {
        self.leadsWithLabel = leadsWithLabel
        self.index = index
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Hud.Radius.sheet, style: .continuous)
        VStack(alignment: .leading, spacing: HudRowKind.icon.sectionGap) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Labels and rows pad 10 sideways themselves; rows pad 10 below.
        .padding(.horizontal, Hud.Layout.edge - Hud.Layout.rowPad)
        .padding(.top, leadsWithLabel ? Hud.Layout.edge : Hud.Layout.edge - Hud.Layout.rowPad)
        .padding(.bottom, Hud.Layout.edge - Hud.Layout.rowPad)
        .background {
            ZStack {
                shape.fill(Color(white: 1, opacity: 0.022))
                shape.strokeBorder(Color(white: 1, opacity: 0.045), lineWidth: 1)
            }
        }
        .settingsStagger(index)
    }
}

/// One section of a page's card: its label ("Name · n") and its rows. Sections follow
/// each other 28 apart (the card's spacing).
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: title, count: count, rows: .icon)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The leading icon column of a row: a 16 pt glyph laid out by its 13 pt ink, or the
/// same width empty so every title in a card starts on one line.
private struct SettingsIconColumn: View {
    var glyph: HudGlyph?

    var body: some View {
        if let glyph {
            HudIcon(glyph, size: 16).foregroundStyle(Hud.Ink.ink3)
                .frame(width: 16, height: 16)
                .padding(-Hud.Layout.glyphInset)
        } else {
            Color.clear.frame(width: SettingsLayout.iconColumn, height: 0)
        }
    }
}

/// One setting (`.srow`): glyph · title and its meta line 7 under it · the control or
/// status at the trailing edge, centred. 10 of padding on every side, so row ink to row
/// ink is 20 (a two-line row with a switch is 45, with a select 48).
struct SettingsRow<Trailing: View>: View {
    var glyph: HudGlyph?
    let title: Text
    var detail: Text?
    @ViewBuilder let trailing: Trailing

    init(glyph: HudGlyph? = nil, title: LocalizedStringKey, detail: Text? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.glyph = glyph
        self.title = Text(title)
        self.detail = detail
        self.trailing = trailing()
    }

    @_disfavoredOverload
    init(glyph: HudGlyph? = nil, title: String, detail: Text? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.glyph = glyph
        self.title = Text(verbatim: title)
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Hud.Row.gap) {
            SettingsIconColumn(glyph: glyph)

            VStack(alignment: .leading, spacing: Hud.Layout.pair) {
                title.hudTrimmed(.body)
                if let detail {
                    detail.hudTrimmed(.meta).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .hudRow(.icon)
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(glyph: HudGlyph? = nil, title: LocalizedStringKey, detail: Text? = nil) {
        self.init(glyph: glyph, title: title, detail: detail) { EmptyView() }
    }
}

/// A row holding a field and its button (`.sfrow`): the 34 pt field starts on the row
/// text line.
struct SettingsFieldRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.leading, SettingsLayout.textInset)
            .hudRow(.icon)
    }
}

/// One short secondary line inside a group (`.snote`). A problem is said by its shape,
/// never by coloured text; the shape sits in the 13 pt icon column.
struct SettingsNote: View {
    let text: Text
    var status: HudStatus?

    init(_ key: LocalizedStringKey, status: HudStatus? = nil) {
        self.text = Text(key)
        self.status = status
    }

    @_disfavoredOverload
    init(_ string: String, status: HudStatus? = nil) {
        self.text = Text(verbatim: string)
        self.status = status
    }

    var body: some View {
        HStack(alignment: .center, spacing: Hud.Row.gap) {
            Group {
                if let status {
                    HudStatusShape(status, size: HudStatusShape.row)
                }
            }
            .frame(width: SettingsLayout.iconColumn)
            text.hud(.meta, status == nil ? Hud.Ink.ink3 : Hud.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .hudTrim(.meta)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hudRow(.icon)
    }
}

/// The result of a save: nothing, a plain line, or a failure with its triangle.
struct SettingsMessage: View {
    let message: String?
    let failed: Bool

    var body: some View {
        if let message {
            SettingsNote(message, status: failed ? .err : nil)
        }
    }
}

/// A switch (`.toggle`): the knob carries a teal lamp when on.
struct SettingsToggle: View {
    let title: Text
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = Text(title)
        _isOn = isOn
    }

    @_disfavoredOverload
    init(_ title: String, isOn: Binding<Bool>) {
        self.title = Text(verbatim: title)
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HudSwitch(isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// A quiet line that shows or hides secondary rows below it (`.expand`).
struct SettingsExpand: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                HudIcon(.chevronDown, size: 10)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(reduceMotion ? nil : Hud.Motion.hover, value: isExpanded)
            }
            .hud(.meta, isHovering ? Hud.Ink.ink2 : Hud.Ink.ink3)
            .hudTrim(.meta)
            .padding(.leading, SettingsLayout.textInset)
            .hudRow(.icon)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.hover, value: isHovering)
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
    }
}

/// A value printed at the end of a row.
struct SettingsValue: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text).hud(.label, Hud.Ink.ink2).lineLimit(1)
    }
}

// MARK: - Rail

/// What the lamp at the end of a rail item says about its section.
enum SettingsRailStatus: Equatable {
    /// No lamp (General, Data).
    case none
    /// Calm: connected and ready.
    case ready
    /// Nothing there: off, not connected.
    case idle
    /// Access is off; red when it blocks recording.
    case accessOff(blocking: Bool)
    /// Broken.
    case failed

    var accessibilityValue: String {
        switch self {
        case .none: ""
        case .ready: "Ready"
        case .idle: "Off"
        case .accessOff: "Needs access"
        case .failed: "Error"
        }
    }
}

/// The settings rail (`.rail[data-rail=settings]`): one item per section, the real
/// state of each as a lamp or a status shape, and a lit lamp sliding to the selection.
struct SettingsRail: View {
    let status: (SettingsCategory) -> SettingsRailStatus
    @Binding var selection: SettingsCategory
    @State private var hovered: SettingsCategory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gap: CGFloat = 2

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(SettingsCategory.allCases) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    HStack(spacing: Hud.Row.gap) {
                        HudIcon(item.hudGlyph, size: 16, solid: isSelected)
                            .foregroundStyle(isSelected ? Hud.Ink.ink1 : Hud.Ink.ink3)
                            .frame(width: 16, height: 16)
                            .padding(-Hud.Layout.glyphInset)
                        Text(item.title).hud(.label, isSelected ? Hud.Ink.ink1 : Hud.Ink.ink2)
                        Spacer(minLength: 4)
                        lamp(status(item))
                    }
                    .lineLimit(1)
                    // The slab sits 10 around the icon ink, like every hover slab.
                    .padding(.horizontal, Hud.Layout.rowPad)
                    .frame(height: Hud.Window.railItem)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: Hud.Layout.hitRadius, style: .continuous)
                        if isSelected {
                            shape.fill(LinearGradient(colors: [Color(white: 1, opacity: 0.075), Color(white: 1, opacity: 0.04)],
                                                      startPoint: .leading, endPoint: .trailing))
                        } else if hovered == item {
                            shape.fill(Color(white: 1, opacity: 0.04))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(Text(verbatim: status(item).accessibilityValue))
            }
        }
        // Slabs 10 in from the window, so the icon ink lands on the window's 20 pt edge
        // with the toolbar title; the rail's first slab shares the page's top line.
        .padding(.horizontal, Hud.Layout.edge - Hud.Layout.rowPad)
        .overlay(alignment: .topLeading) {
            let index = CGFloat(SettingsCategory.allCases.firstIndex(of: selection) ?? 0)
            Capsule().fill(Hud.Ink.ink1)
                .shadow(color: Hud.Ink.ink1.opacity(0.75), radius: 3)
                .shadow(color: Hud.Ink.ink1.opacity(0.22), radius: 7)
                .frame(width: 3, height: 14)
                .offset(y: index * (Hud.Window.railItem + Self.gap) + (Hud.Window.railItem - 14) / 2)
                .animation(reduceMotion ? nil : Hud.Motion.railLamp, value: selection)
                .allowsHitTesting(false)
        }
        .animation(Hud.Motion.hover, value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    @ViewBuilder
    private func lamp(_ status: SettingsRailStatus) -> some View {
        switch status {
        case .none: EmptyView()
        case .ready: HudLamp(.teal)
        case .idle: HudLamp(.off)
        case let .accessOff(blocking): HudStatusShape(.off, tint: blocking ? Hud.Ink.live : nil)
        case .failed: HudStatusShape(.err)
        }
    }
}
