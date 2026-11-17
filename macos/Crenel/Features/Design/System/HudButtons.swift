import SwiftUI

// MARK: - Button style

/// Buttons are keys you press, not words you click.
///
/// - primary — the lit key: one per surface, always rightmost, always with its keycap.
/// - secondary — a raised key in the dark: every other action.
/// - danger — a secondary key with red ink; never next to the primary.
/// - ghost — text only; tertiary navigation inside lists.
/// - icon — a bare icon button (band tools); `isOn` adds a lamp under it.
/// - iconFramed — a square secondary key holding an icon (toolbar "more", copy).
///
/// Sizes: large 32 (radius 9), regular 28 (radius 8), small 26, mini 22 (radius 6,
/// 11.5 pt). Pressed keys sink 0.5 pt and take an inner shadow.
///
///     Button { } label: { HudButtonLabel("Join", key: "⌘J") }
///         .buttonStyle(HudButtonStyle(kind: .primary, size: .small))
///     HudButton("Record", lamp: .red, key: "⌘R", size: .small) { }
struct HudButtonStyle: ButtonStyle {
    enum Kind: Equatable, Sendable {
        case primary, secondary, danger, ghost, icon, iconFramed
        /// Legacy name for `iconFramed`.
        static let iconFilled = Kind.iconFramed
    }

    enum Size: Equatable, Sendable {
        /// `.btn.lg` — 32 pt.
        case large
        /// `.btn` — 28 pt.
        case regular
        /// `.btn.sm` — 26 pt.
        case small
        /// `.btn.xs` — 22 pt.
        case mini

        var height: CGFloat {
            switch self {
            case .large: 32
            case .regular: 28
            case .small: 26
            case .mini: 22
            }
        }

        var radius: CGFloat {
            switch self {
            case .large: 9
            case .regular, .small: 8
            case .mini: 6
            }
        }

        var padding: (leading: CGFloat, trailing: CGFloat) {
            switch self {
            case .large: (14, 14)
            case .regular: (12, 12)
            case .small: (10, 10)
            case .mini: (7, 8)
            }
        }

        /// Space between the icon, the word and the keycap.
        var gap: CGFloat {
            switch self {
            case .large, .regular: 6
            case .small: 5
            case .mini: 4
            }
        }

        var font: Font { self == .mini ? Hud.font(11.5, .medium) : Hud.Style.label.font }
    }

    var kind: Kind = .ghost
    var size: Size = .regular
    /// Icon buttons only: the tool is active (a lamp under the icon).
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        HudButtonBody(kind: kind, size: size, isOn: isOn, configuration: configuration)
    }
}

private struct HudButtonKindKey: EnvironmentKey {
    static let defaultValue: HudButtonStyle.Kind? = nil
}

private struct HudButtonSizeKey: EnvironmentKey {
    static let defaultValue: HudButtonStyle.Size = .regular
}

extension EnvironmentValues {
    /// The kind of the enclosing Hud button, for keycaps and icons inside its label.
    var hudButtonKind: HudButtonStyle.Kind? {
        get { self[HudButtonKindKey.self] }
        set { self[HudButtonKindKey.self] = newValue }
    }

    var hudButtonSize: HudButtonStyle.Size {
        get { self[HudButtonSizeKey.self] }
        set { self[HudButtonSizeKey.self] = newValue }
    }
}

private struct HudButtonBody: View {
    let kind: HudButtonStyle.Kind
    let size: HudButtonStyle.Size
    let isOn: Bool
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isIcon = kind == .icon || kind == .iconFramed
        // Icon buttons are 28 pt squares; `.small` makes them 26.
        let side: CGFloat = size == .small || size == .mini ? 26 : 28
        let height = isIcon ? side : size.height
        let radius = isIcon ? 8 : size.radius
        configuration.label
            .font(size.font)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.leading, isIcon ? 0 : size.padding.leading)
            .padding(.trailing, isIcon ? 0 : size.padding.trailing)
            .frame(width: isIcon ? side : nil, height: height)
            .background(HudKeyFace(kind: kind, radius: radius, isHovering: isHovering, isPressed: configuration.isPressed))
            .overlay(alignment: .bottom) {
                if kind == .icon, isOn {
                    Capsule().fill(Hud.Ink.ink1).frame(width: 8, height: 2)
                        .shadow(color: Hud.Ink.ink1.opacity(0.6), radius: 3)
                        .padding(.bottom, 1)
                }
            }
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .environment(\.hudButtonKind, kind)
            .environment(\.hudButtonSize, size)
            .onHover { isHovering = $0 }
            .animation(Hud.Motion.hover, value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Hud.Ink.onKey
        case .secondary: Hud.Ink.ink1
        case .danger: Hud.Ink.danger
        case .ghost: isHovering ? Hud.Ink.ink1 : Hud.Ink.ink2
        case .icon: isOn || isHovering ? Hud.Ink.ink1 : Hud.Ink.ink3
        case .iconFramed: isHovering ? Hud.Ink.ink1 : Hud.Ink.ink2
        }
    }
}

/// The body of a key: gradient, hairline ring, top highlight, drop to the surface.
struct HudKeyFace: View {
    let kind: HudButtonStyle.Kind
    var radius: CGFloat = 8
    var isHovering = false
    var isPressed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch kind {
        case .primary:
            ZStack {
                if !isPressed {
                    // 0 0 16px ink 9 % — the lit key spills a little light.
                    shape.fill(Hud.Ink.ink1.opacity(0.09)).blur(radius: 8)
                    HudOuterShadow(shape: shape, color: .black.opacity(0.5), radius: 1.5, y: 1)
                }
                shape.inset(by: -0.5).fill(Color.black.opacity(0.7))
                if isPressed {
                    shape.fill(
                        LinearGradient(colors: [Color(hud: 0xD9D5CD), Color(hud: 0xE6E3DC)], startPoint: .top, endPoint: .bottom)
                            .shadow(.inner(color: .black.opacity(0.22), radius: 1, x: 0, y: 1))
                    )
                } else {
                    shape.fill(
                        LinearGradient(colors: isHovering ? [.white, Color(hud: 0xEBE8E2)] : [Color(hud: 0xFDFCF9), Color(hud: 0xE2DFD8)],
                                       startPoint: .top, endPoint: .bottom)
                            .shadow(.inner(color: .white, radius: 0, x: 0, y: 1))
                            .shadow(.inner(color: .black.opacity(0.14), radius: 0, x: 0, y: -1))
                    )
                }
            }
        case .secondary, .danger, .iconFramed:
            ZStack {
                if isPressed {
                    shape.fill(Color(white: 1, opacity: 0.04).shadow(.inner(color: .black.opacity(0.55), radius: 1, x: 0, y: 1)))
                    shape.strokeBorder(Color(white: 1, opacity: 0.06), lineWidth: 1)
                } else {
                    HudOuterShadow(shape: shape, color: .black.opacity(0.45), radius: 1, y: 1)
                    shape.fill(
                        LinearGradient(colors: [Color(white: 1, opacity: isHovering ? 0.125 : 0.088), Color(white: 1, opacity: isHovering ? 0.07 : 0.046)],
                                       startPoint: .top, endPoint: .bottom)
                            .shadow(.inner(color: Color(white: 1, opacity: 0.075), radius: 0, x: 0, y: 1))
                    )
                    shape.strokeBorder(Color(white: 1, opacity: 0.07), lineWidth: 1)
                }
            }
        case .ghost, .icon:
            shape.fill(Color(white: 1, opacity: isPressed ? 0.10 : (isHovering ? 0.06 : 0)))
        }
    }
}

/// A CSS-style box shadow: drawn only outside the shape, so translucent keys don't
/// darken from their own shadow.
struct HudOuterShadow<S: InsettableShape>: View {
    let shape: S
    let color: Color
    var radius: CGFloat = 1
    var y: CGFloat = 1

    var body: some View {
        shape.fill(color)
            .blur(radius: radius)
            .offset(y: y)
            .mask {
                Rectangle().padding(-(radius * 3 + abs(y) + 2))
                    .overlay { shape.fill(.black).blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Keycap

/// The shortcut, drawn as a key inside its button (`.kbd`): 16 pt (15 in small and mini
/// buttons), radius 4, 10.5 pt, a 1 px dark lower edge. Cancel carries `esc`, the
/// primary carries `↩`; other shortcuts carry their own key (`⌘J`, `⌘R`, `⌘Z`, `⇧⌘C`).
///
///     HudKeycap("esc")
struct HudKeycap: View {
    let key: String
    @Environment(\.hudButtonKind) private var kind
    @Environment(\.hudButtonSize) private var size

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        let compact = kind != nil && (size == .small || size == .mini)
        let side: CGFloat = compact ? 15 : 16
        let onKey = kind == .primary
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Text(verbatim: key)
            .font(Hud.font(compact ? 10 : 10.5, .medium))
            .foregroundStyle(onKey ? Color.black.opacity(0.5) : Hud.Ink.ink3)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .background(
                shape.fill(
                    (onKey ? Color.black.opacity(0.06) : Color(white: 1, opacity: 0.055))
                        .shadow(.inner(color: onKey ? .black.opacity(0.14) : .black.opacity(0.5), radius: 0, x: 0, y: -1))
                )
            )
            .overlay(shape.strokeBorder(onKey ? Color.black.opacity(0.12) : Color(white: 1, opacity: 0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Labels and ready-made buttons

/// A button's content: optional lamp or icon, the word, optional keycap.
///
///     HudButtonLabel("Record", lamp: .red, key: "⌘R")
///     HudButtonLabel("Export", glyph: .share, trailingGlyph: .chevronDown)
struct HudButtonLabel: View {
    let title: Text
    var glyph: HudGlyph?
    var lamp: Hud.LampColor?
    var key: String?
    var trailingGlyph: HudGlyph?
    @Environment(\.hudButtonKind) private var kind
    @Environment(\.hudButtonSize) private var size

    init(_ title: LocalizedStringKey, glyph: HudGlyph? = nil, lamp: Hud.LampColor? = nil, key: String? = nil, trailingGlyph: HudGlyph? = nil) {
        self.title = Text(title)
        self.glyph = glyph
        self.lamp = lamp
        self.key = key
        self.trailingGlyph = trailingGlyph
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, glyph: HudGlyph? = nil, lamp: Hud.LampColor? = nil, key: String? = nil, trailingGlyph: HudGlyph? = nil) {
        self.title = Text(title)
        self.glyph = glyph
        self.lamp = lamp
        self.key = key
        self.trailingGlyph = trailingGlyph
    }

    var body: some View {
        HStack(spacing: size.gap) {
            if let lamp {
                HudLamp(lamp, form: .dot)
            }
            if let glyph {
                icon(glyph, color: iconColor)
            }
            title
            if let trailingGlyph {
                icon(trailingGlyph, color: kind == .primary ? Hud.Ink.onKey : Hud.Ink.ink3).padding(.trailing, -2)
            }
            if let key {
                HudKeycap(key).padding(.leading, 4).padding(.trailing, -3)
            }
        }
    }

    @ViewBuilder
    private func icon(_ glyph: HudGlyph, color: Color?) -> some View {
        if let color {
            HudIcon(glyph, size: Hud.Size.smallIcon).foregroundStyle(color)
        } else {
            HudIcon(glyph, size: Hud.Size.smallIcon)
        }
    }

    /// Icons in a secondary key are ink-2; elsewhere they take the label's ink.
    private var iconColor: Color? {
        kind == .secondary ? Hud.Ink.ink2 : nil
    }
}

/// A key with a word.
///
///     HudButton("Join", key: "⌘J", kind: .primary, size: .small) { join() }
///     HudButton("Clear", glyph: .trash, kind: .danger, size: .small) { clear() }
struct HudButton: View {
    let label: HudButtonLabel
    var kind: HudButtonStyle.Kind = .secondary
    var size: HudButtonStyle.Size = .regular
    let action: () -> Void

    init(_ title: LocalizedStringKey, glyph: HudGlyph? = nil, lamp: Hud.LampColor? = nil, key: String? = nil,
         trailingGlyph: HudGlyph? = nil, kind: HudButtonStyle.Kind = .secondary, size: HudButtonStyle.Size = .regular,
         action: @escaping () -> Void) {
        label = HudButtonLabel(title, glyph: glyph, lamp: lamp, key: key, trailingGlyph: trailingGlyph)
        self.kind = kind
        self.size = size
        self.action = action
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, glyph: HudGlyph? = nil, lamp: Hud.LampColor? = nil, key: String? = nil,
                            trailingGlyph: HudGlyph? = nil, kind: HudButtonStyle.Kind = .secondary,
                            size: HudButtonStyle.Size = .regular, action: @escaping () -> Void) {
        label = HudButtonLabel(title, glyph: glyph, lamp: lamp, key: key, trailingGlyph: trailingGlyph)
        self.kind = kind
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(HudButtonStyle(kind: kind, size: size))
    }
}

/// An icon button: bare (`.btn-icon`, band tools) or framed (`.btn-icon.framed`).
///
///     HudIconButton(.tape, isOn: showsRecordings, help: "Recordings") { }
///     HudIconButton(.more, framed: true, small: true, help: "More") { }
struct HudIconButton: View {
    let glyph: HudGlyph
    var framed = false
    var small = false
    var isOn = false
    var tint: Color?
    var help: LocalizedStringKey?
    let action: () -> Void

    init(_ glyph: HudGlyph, framed: Bool = false, small: Bool = false, isOn: Bool = false, tint: Color? = nil,
         help: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.glyph = glyph
        self.framed = framed
        self.small = small
        self.isOn = isOn
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            if let tint {
                HudIcon(glyph, size: small ? 14 : 16).foregroundStyle(tint)
            } else {
                HudIcon(glyph, size: small ? 14 : 16)
            }
        }
        .buttonStyle(HudButtonStyle(kind: framed ? .iconFramed : .icon, size: small ? .small : .regular, isOn: isOn))
        if let help {
            button.help(Text(help)).accessibilityLabel(Text(help))
        } else {
            button
        }
    }
}

// MARK: - Knob

/// Push knobs: round, ringed — the controls you press during a call (`.knob`). 40 pt;
/// `small` is 32 pt (the player's play button).
struct HudKnobStyle: ButtonStyle {
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        HudKnobBody(small: small, configuration: configuration)
    }
}

private struct HudKnobBody: View {
    let small: Bool
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        let side: CGFloat = small ? 32 : 40
        configuration.label
            .foregroundStyle(Hud.Ink.ink1)
            .frame(width: side, height: side)
            .background(
                Circle().fill(
                    RadialGradient(
                        stops: [.init(color: Color(white: 1, opacity: isHovering ? 0.15 : 0.10), location: 0),
                                .init(color: Color(white: 1, opacity: isHovering ? 0.05 : 0.035), location: 0.7)],
                        center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: side * 0.65
                    )
                    .shadow(.inner(color: Color(white: 1, opacity: 0.08), radius: 0, x: 0, y: 1))
                )
            )
            .overlay(Circle().strokeBorder(Color(white: 1, opacity: 0.09), lineWidth: 1))
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(Hud.Motion.hover, value: isHovering)
    }
}

/// A push knob with its icon and, optionally, the lamp that sits 5 pt under it.
///
///     HudKnob(.mic, lamp: .white, help: "Meeting mic on") { toggleMic() }
///     HudKnob(.stop, tint: Hud.Ink.live, help: "Stop") { stop() }
struct HudKnob: View {
    let glyph: HudGlyph
    var tint: Color = Hud.Ink.ink1
    /// nil: no lamp. `.off`: an unlit lamp.
    var lamp: Hud.LampColor?
    var lampLoop: HudLoop = .steady
    var small = false
    var help: LocalizedStringKey?
    let action: () -> Void

    init(_ glyph: HudGlyph, tint: Color = Hud.Ink.ink1, lamp: Hud.LampColor? = nil, lampLoop: HudLoop = .steady,
         small: Bool = false, help: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.glyph = glyph
        self.tint = tint
        self.lamp = lamp
        self.lampLoop = lampLoop
        self.small = small
        self.help = help
        self.action = action
    }

    var body: some View {
        let button = Button(action: action) {
            HudIcon(glyph, size: small ? 14 : 16).foregroundStyle(tint)
        }
        .buttonStyle(HudKnobStyle(small: small))
        .overlay(alignment: .bottom) {
            if let lamp {
                HudLamp(lamp, loop: lampLoop).offset(y: 9)
            }
        }
        if let help {
            button.help(Text(help)).accessibilityLabel(Text(help))
        } else {
            button
        }
    }
}

// MARK: - Action rows

/// The action bar (`.actions`): what is happening on the left (a lamp and a meta note),
/// what you can do on the right. Order, left to right: danger · secondary · primary.
///
///     HudActions {
///         HudLamp(.teal); Text("Synced with Reminders")
///     } buttons: {
///         HudButton("Finished", glyph: .history, size: .small) { }
///     }
struct HudActions<Note: View, Buttons: View>: View {
    @ViewBuilder var note: () -> Note
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) { note() }
                .hud(.meta, Hud.Ink.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            buttons()
        }
    }
}

extension HudActions where Note == EmptyView {
    /// Buttons only, trailing.
    init(@ViewBuilder buttons: @escaping () -> Buttons) {
        self.init(note: { EmptyView() }, buttons: buttons)
    }
}

/// The console (`.console`): a 44 pt bar under the hero when a call is near or on —
/// lamp and state on the left, the call's two actions on the right.
///
///     HudConsole {
///         HudLamp(.teal); Text("Crenel will ask to record when it starts")
///     } buttons: {
///         HudButton("Record", lamp: .red, key: "⌘R", size: .small) { }
///         HudButton("Join", key: "⌘J", kind: .primary, size: .small) { }
///     }
struct HudConsole<Note: View, Buttons: View>: View {
    var height: CGFloat = Hud.Notch.consoleHeight
    @ViewBuilder var note: () -> Note
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Hud.Radius.console, style: .continuous)
        HStack(spacing: 8) {
            HStack(spacing: 10) { note() }
                .hud(.meta, Hud.Ink.ink2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            buttons()
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: height)
        .background(shape.fill(LinearGradient(colors: [Color(white: 1, opacity: 0.045), Color(white: 1, opacity: 0.025)],
                                              startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(Color(white: 1, opacity: 0.05), lineWidth: 1))
    }
}
