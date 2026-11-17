import SwiftUI

/// Shared layout values for every settings page (`tpl-desktop`, `s-*`).
enum SettingsLayout {
    /// Space between the header and the group cards.
    static let groupSpacing: CGFloat = 20
    /// Cards read best at a comfortable measure, not the full window width.
    static let contentWidth: CGFloat = 640
    /// Where row text starts inside a card: 10 inset + 16 icon + 12 gap.
    static let textInset: CGFloat = 38
    static let rowInset: CGFloat = 10
    static let rowHeight: CGFloat = 50

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
        VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
            content
        }
        .environment(\.settingsShown, shown)
        .onAppear { shown = true }
    }
}

// MARK: - Page header

/// A page opens with its header (`.ph`): a 40 pt raised icon tile, the title, one
/// sentence, and a readout on the right.
struct SettingsPageHeader<Readout: View>: View {
    let glyph: HudGlyph
    let title: LocalizedStringKey
    let sentence: LocalizedStringKey
    @ViewBuilder var readout: () -> Readout

    var body: some View {
        HStack(spacing: 16) {
            HudIconTile(glyph, solid: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).hud(.title).accessibilityAddTraits(.isHeader)
                Text(sentence).hud(.meta)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            readout()
        }
        .padding(.vertical, 4)
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

// MARK: - Groups and rows

/// A group is a raised card (`.sgroup`, radius 14) with its title inside.
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    var index: Int
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, index: Int = 1, @ViewBuilder content: () -> Content) {
        self.title = title
        self.index = index
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: title)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudGroupCard()
        .settingsStagger(index)
    }
}

/// One setting (`.srow`): glyph · title and one line of detail · the control or status
/// at the trailing edge.
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
        HStack(spacing: 12) {
            Group {
                if let glyph {
                    HudIcon(glyph, size: 16).foregroundStyle(Hud.Ink.ink3)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                title.hud(.body)
                if let detail {
                    detail.hud(.meta).truncationMode(.tail)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, SettingsLayout.rowInset)
        .frame(minHeight: SettingsLayout.rowHeight)
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(glyph: HudGlyph? = nil, title: LocalizedStringKey, detail: Text? = nil) {
        self.init(glyph: glyph, title: title, detail: detail) { EmptyView() }
    }
}

/// A row holding a field and its button (`.sfrow`), aligned with row text.
struct SettingsFieldRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.leading, SettingsLayout.textInset)
            .padding(.trailing, SettingsLayout.rowInset)
            .padding(.vertical, 4)
    }
}

/// One short secondary line inside a group (`.snote`). A problem is said by its shape,
/// never by coloured text.
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let status {
                HudStatusShape(status, size: HudStatusShape.row)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            }
            text.hud(.meta, status == nil ? Hud.Ink.ink3 : Hud.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, SettingsLayout.textInset)
        .padding(.trailing, SettingsLayout.rowInset)
        .padding(.vertical, 4)
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
            .padding(.leading, SettingsLayout.textInset)
            .frame(height: 30)
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
                    HStack(spacing: 12) {
                        HudIcon(item.hudGlyph, size: 16, solid: isSelected)
                            .foregroundStyle(isSelected ? Hud.Ink.ink1 : Hud.Ink.ink3)
                        Text(item.title).hud(.label, isSelected ? Hud.Ink.ink1 : Hud.Ink.ink2)
                        Spacer(minLength: 4)
                        lamp(status(item))
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
        .padding(.leading, 12)
        .padding(.trailing, 8)
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
