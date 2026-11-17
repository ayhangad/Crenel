import SwiftUI

/// Layout, colour and type tokens used by Crenel's screens. They resolve to the `Hud`
/// language: one neutral grey scale, Geist at natural tracking, colour only for state.
enum Crenel {
    // MARK: Spacing — a 4 pt grid

    enum Space {
        static let hair: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 40
    }

    // MARK: Radius

    enum Radius {
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = Hud.Size.corner
        static let l: CGFloat = 12
        static let xl: CGFloat = 14
        /// The expanded notch's bottom corners.
        static let notch: CGFloat = 20
    }

    // MARK: Colour

    enum Palette {
        static let ink = Color.black
        /// Grouped content on black.
        static let layer1 = Color(white: 1, opacity: 0.04)
        /// Hovered rows, raised controls.
        static let layer2 = Hud.Ink.hover
        /// Pressed controls, tracks.
        static let layer3 = Hud.Ink.track

        static let hairline = Color(white: 1, opacity: 0.06)
        static let stroke = Hud.Ink.track
        static let highlight = Color.clear

        static let textPrimary = Hud.Ink.text1
        static let textSecondary = Hud.Ink.text2
        static let textTertiary = Hud.Ink.text3
        static let textQuaternary = Hud.Ink.text4

        // Former module accents. Colour only means state now, so modules are neutral.
        static let calendar = Hud.Ink.text2
        static let tasks = Hud.Ink.text2
        static let dictation = Hud.Ink.text1
        static let record = Hud.Ink.live
        static let agent = Hud.Ink.text1

        // Semantic
        static let success = Hud.Ink.ok
        static let warning = Hud.Ink.signal
        static let danger = Hud.Ink.live
        static let focus = Hud.Ink.text1
    }

    // MARK: Type

    enum TextStyle {
        /// Big rounded numerals (countdowns, timers).
        case display
        /// Rounded numerals inside rings and compact notch values.
        case numeral
        case title
        case headline
        case body
        case bodyEmphasis
        case callout
        case caption
        /// Plain group title.
        case eyebrow

        var font: Font {
            switch self {
            case .display: Hud.font(26, .semibold).monospacedDigit()
            case .numeral: Hud.Style.label.font.monospacedDigit()
            case .title: Hud.Style.title.font
            case .headline: Hud.font(14, .semibold)
            case .body: Hud.font(13.5, .regular)
            case .bodyEmphasis: Hud.Style.body.font
            case .callout: Hud.Style.meta.font
            case .caption: Hud.font(11.5, .regular).monospacedDigit()
            case .eyebrow: Hud.Style.label.font
            }
        }

        var tracking: CGFloat { 0 }
    }

    // MARK: Motion

    enum Motion {
        /// The notch changing shape. Soft landing, no wobble.
        static let morph = Hud.Motion.morph
        /// Quick UI responses: hover, press, toggles.
        static let snappy = Hud.Motion.glide
        /// Playful confirmations: a task completing, a chip appearing.
        static let bouncy = Animation.spring(response: 0.36, dampingFraction: 0.8)
        /// Content swaps inside a stable frame.
        static let gentle = Hud.Motion.change

        static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? .linear(duration: 0.01) : animation
        }
    }
}

extension View {
    /// Applies a Crenel text style: font, tracking and (optionally) colour.
    func crenelText(_ style: Crenel.TextStyle, color: Color? = nil) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .foregroundStyle(color ?? Crenel.Palette.textPrimary)
    }
}

extension Text {
    /// A plain group title: no uppercase, no letterspacing.
    func eyebrow(color: Color = Crenel.Palette.textTertiary) -> some View {
        self.crenelText(.eyebrow, color: color)
    }
}

// MARK: - Transitions

private struct BlurScaleModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: anchor)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Content dissolving through blur, the way the Dynamic Island swaps content.
    static func crenelMorph(anchor: UnitPoint = .top) -> AnyTransition {
        .modifier(
            active: BlurScaleModifier(blur: 0, scale: 0.98, opacity: 0, anchor: anchor),
            identity: BlurScaleModifier(blur: 0, scale: 1, opacity: 1, anchor: anchor)
        )
    }

    /// A row or chip arriving from slightly below.
    static var crenelRise: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleModifier(blur: 0, scale: 1, opacity: 0, anchor: .top),
                identity: BlurScaleModifier(blur: 0, scale: 1, opacity: 1, anchor: .top)
            ).combined(with: .offset(y: -6)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}
