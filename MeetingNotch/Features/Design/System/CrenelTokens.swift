import SwiftUI

/// Crenel's design language in one place. Every surface reads its spacing, type, colour,
/// radius and motion from here; nothing hardcodes a magic number.
///
/// The style: the notch is ink. Content sits on layered near-black surfaces lit from
/// above by a hairline highlight. Each module owns one accent colour that tints its
/// glyphs, rings and glows — calendar violet, tasks amber, dictation sky, recording
/// coral. Type is quiet and tight; numbers are rounded and tabular.
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
        static let s: CGFloat = 10
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 26
        /// The expanded notch's bottom corners.
        static let notch: CGFloat = 32
    }

    // MARK: Colour

    enum Palette {
        static let ink = Color.black
        /// Cards and grouped content.
        static let layer1 = Color(white: 0.068)
        /// Raised controls, hovered rows.
        static let layer2 = Color(white: 0.105)
        /// Pressed controls, tracks.
        static let layer3 = Color(white: 0.16)

        static let hairline = Color.white.opacity(0.07)
        static let stroke = Color.white.opacity(0.12)
        static let highlight = Color.white.opacity(0.14)

        static let textPrimary = Color.white.opacity(0.96)
        static let textSecondary = Color.white.opacity(0.62)
        static let textTertiary = Color.white.opacity(0.40)
        static let textQuaternary = Color.white.opacity(0.24)

        // Module accents
        static let calendar = Color(red: 0.58, green: 0.52, blue: 1.0)
        static let tasks = Color(red: 1.0, green: 0.72, blue: 0.30)
        static let dictation = Color(red: 0.36, green: 0.80, blue: 1.0)
        static let record = Color(red: 1.0, green: 0.32, blue: 0.30)
        static let agent = Color(red: 0.90, green: 0.56, blue: 1.0)

        // Semantic
        static let success = Color(red: 0.25, green: 0.86, blue: 0.60)
        static let warning = Color(red: 1.0, green: 0.77, blue: 0.30)
        static let danger = Color(red: 1.0, green: 0.36, blue: 0.38)
        static let focus = Color(red: 0.42, green: 0.66, blue: 1.0)
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
        /// Uppercase section eyebrow.
        case eyebrow

        var font: Font {
            switch self {
            case .display: .system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
            case .numeral: .system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
            case .title: .system(size: 17, weight: .semibold)
            case .headline: .system(size: 14, weight: .semibold)
            case .body: .system(size: 13.5, weight: .regular)
            case .bodyEmphasis: .system(size: 13.5, weight: .medium)
            case .callout: .system(size: 12, weight: .medium)
            case .caption: .system(size: 11, weight: .medium).monospacedDigit()
            case .eyebrow: .system(size: 10.5, weight: .semibold)
            }
        }

        var tracking: CGFloat {
            switch self {
            case .display: -0.6
            case .title: -0.2
            case .eyebrow: 0.7
            default: 0
            }
        }
    }

    // MARK: Motion

    enum Motion {
        /// The notch changing shape. Soft landing, no wobble.
        static let morph = Animation.spring(response: 0.48, dampingFraction: 0.82)
        /// Quick UI responses: hover, press, toggles.
        static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.86)
        /// Playful confirmations: a task completing, a chip appearing.
        static let bouncy = Animation.spring(response: 0.40, dampingFraction: 0.64)
        /// Content swaps inside a stable frame.
        static let gentle = Animation.smooth(duration: 0.32)

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
    func eyebrow(color: Color = Crenel.Palette.textTertiary) -> some View {
        self.textCase(.uppercase).crenelText(.eyebrow, color: color)
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
            active: BlurScaleModifier(blur: 8, scale: 0.94, opacity: 0, anchor: anchor),
            identity: BlurScaleModifier(blur: 0, scale: 1, opacity: 1, anchor: anchor)
        )
    }

    /// A row or chip arriving from slightly below.
    static var crenelRise: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleModifier(blur: 4, scale: 0.97, opacity: 0, anchor: .top),
                identity: BlurScaleModifier(blur: 0, scale: 1, opacity: 1, anchor: .top)
            ).combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}
