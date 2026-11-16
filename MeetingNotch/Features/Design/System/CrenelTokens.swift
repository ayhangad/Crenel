import SwiftUI

/// Crenel's design language.
///
/// The notch is a small terminal made of light. Type is monospaced and set a little
/// heavier than usual so it reads at a glance on black. Icons are drawn on a 9×9 pixel
/// grid. Interactive pieces have stepped pixel corners — the crenel, the notch in a
/// battlement — while the notch itself stays smooth like the hardware. Motion is quiet:
/// colour fades, light travelling along an edge, content resolving pixel by pixel.
/// Nothing bounces, grows or shifts layout under the pointer.
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
        /// Pixel step of the crenel corner on controls.
        static let step: CGFloat = 2
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        /// The open notch's bottom corners.
        static let notch: CGFloat = 26
    }

    // MARK: Colour

    enum Palette {
        static let ink = Color(red: 0.035, green: 0.035, blue: 0.05)
        static let layer1 = Color(red: 0.075, green: 0.075, blue: 0.10)
        static let layer2 = Color(red: 0.11, green: 0.11, blue: 0.145)
        static let layer3 = Color(red: 0.155, green: 0.155, blue: 0.20)

        static let hairline = Color(red: 0.16, green: 0.16, blue: 0.21)
        static let stroke = Color(red: 0.23, green: 0.23, blue: 0.29)

        static let textPrimary = Color(red: 0.93, green: 0.92, blue: 0.95)
        static let textSecondary = Color(red: 0.64, green: 0.63, blue: 0.70)
        static let textTertiary = Color(red: 0.45, green: 0.44, blue: 0.52)
        static let textQuaternary = Color(red: 0.32, green: 0.31, blue: 0.38)

        /// Crenel's own colour: an ember on the wall.
        static let brand = Color(red: 1.0, green: 0.55, blue: 0.30)

        static let calendar = Color(red: 0.56, green: 0.70, blue: 1.0)
        static let tasks = Color(red: 1.0, green: 0.82, blue: 0.40)
        static let dictation = Color(red: 0.43, green: 0.91, blue: 0.85)
        static let record = Color(red: 1.0, green: 0.36, blue: 0.48)
        static let agent = Color(red: 0.78, green: 0.64, blue: 1.0)

        static let success = Color(red: 0.48, green: 0.89, blue: 0.58)
        static let warning = Color(red: 1.0, green: 0.78, blue: 0.36)
        static let danger = Color(red: 1.0, green: 0.36, blue: 0.48)
        static let focus = Color(red: 1.0, green: 0.82, blue: 0.40)
    }

    // MARK: Type — monospaced throughout

    enum TextStyle {
        /// Timers and big counts.
        case display
        /// Compact notch values and countdowns.
        case numeral
        case title
        case headline
        case body
        case bodyEmphasis
        case callout
        case caption
        /// Section labels: lowercase, quiet.
        case eyebrow

        var font: Font {
            switch self {
            case .display: .system(size: 30, weight: .semibold, design: .monospaced)
            case .numeral: .system(size: 13, weight: .semibold, design: .monospaced)
            case .title: .system(size: 16, weight: .semibold, design: .monospaced)
            case .headline: .system(size: 14, weight: .semibold, design: .monospaced)
            case .body: .system(size: 13, weight: .medium, design: .monospaced)
            case .bodyEmphasis: .system(size: 13, weight: .semibold, design: .monospaced)
            case .callout: .system(size: 12, weight: .medium, design: .monospaced)
            case .caption: .system(size: 11.5, weight: .medium, design: .monospaced)
            case .eyebrow: .system(size: 11.5, weight: .medium, design: .monospaced)
            }
        }

        var tracking: CGFloat {
            switch self {
            case .display: -1
            case .title, .headline: -0.3
            default: -0.1
            }
        }
    }

    // MARK: Motion

    enum Motion {
        /// The notch changing shape: a soft landing, no overshoot.
        static let morph = Animation.spring(response: 0.42, dampingFraction: 0.9)
        /// Hover and state colour changes.
        static let fade = Animation.easeOut(duration: 0.14)
        /// Small in-place swaps (a row's state picker sliding in).
        static let slide = Animation.smooth(duration: 0.22)
        /// Kept for call sites that change values in place; same feel as `slide`.
        static let snappy = slide
        static let gentle = Animation.smooth(duration: 0.3)
        static let bouncy = slide

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
        self.textCase(.lowercase).crenelText(.eyebrow, color: color)
    }
}

// MARK: - Transitions

/// Content resolving through a pixel dither (ordered 4×4 Bayer), Crenel's signature swap.
private struct DitherModifier: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // At rest the effect is disabled (same view structure, so no state is lost): a
        // lingering colour effect would cost a render pass and blank out AppKit-backed
        // controls such as text fields.
        let active = progress < 0.999
        content
            .visualEffect { view, _ in
                view.colorEffect(
                    ShaderLibrary.crenelDither(.float(Float(progress)), .float(3)),
                    isEnabled: active
                )
            }
            .opacity(progress <= 0.001 ? 0 : 1)
    }
}

extension AnyTransition {
    /// Content dissolving pixel by pixel. Only for small shape-and-text content (glyphs,
    /// the closed notch, chips): colour effects cannot render AppKit-backed controls, so
    /// containers with text fields or scroll views must use `crenelMorph`.
    static var crenelPixel: AnyTransition {
        .modifier(active: DitherModifier(progress: 0), identity: DitherModifier(progress: 1))
    }

    /// Large content swaps (panels, pages): a quiet fade.
    static func crenelMorph(anchor: UnitPoint = .top) -> AnyTransition {
        .opacity
    }

    /// Rows and chips: a plain fade, no movement.
    static var crenelRise: AnyTransition { .opacity }
}
