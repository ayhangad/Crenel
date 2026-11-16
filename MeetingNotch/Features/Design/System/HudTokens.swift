import CoreText
import SwiftUI

/// Crenel's design language — "instrument".
///
/// A compact tool, read in a glance. Information is carried by position, icon and
/// colour before words: a line of text appears only when nothing else can say it.
/// One typeface (Geist) at natural spacing, one neutral grey scale, one stroke icon
/// family. Colour only ever means state. Rows keep their size and insets in every
/// state; motion is soft and continuous — highlights glide, shapes morph, nothing jumps.
enum Hud {
    // MARK: Grid

    enum Space {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x7: CGFloat = 28
        static let x8: CGFloat = 32
    }

    enum Size {
        /// Two-line list row.
        static let row: CGFloat = 48
        static let icon: CGFloat = 14
        static let smallIcon: CGFloat = 12
        static let panelWidth: CGFloat = 490
        /// Distance from the panel frame to text (includes the 12 pt top-corner flare of
        /// the open notch). Hover fills bleed `rowInset` beyond the text, leaving 8 pt
        /// to the notch wall.
        static let panelInset: CGFloat = 30
        static let rowInset: CGFloat = 10
        static let corner: CGFloat = 9
        static let control: CGFloat = 28
    }

    // MARK: Colour — one neutral grey scale; colour means state

    enum Ink {
        static let canvas = Color.black

        // Text and icons: one scale of pure greys (equal channels, no tint).
        static let text1 = Color(white: 0.95)
        static let text2 = Color(white: 0.66)
        static let text3 = Color(white: 0.45)
        static let text4 = Color(white: 0.30)

        // Surfaces on black: the same white at low opacity.
        static let hover = Color(white: 1, opacity: 0.06)
        static let selected = Color(white: 1, opacity: 0.10)
        static let press = Color(white: 1, opacity: 0.12)
        static let track = Color(white: 1, opacity: 0.09)

        /// "Now": the thing that needs you next.
        static let signal = Color(red: 1.0, green: 0.70, blue: 0.25)
        /// Live capture, blocked work, errors.
        static let live = Color(red: 1.0, green: 0.30, blue: 0.30)
        /// Connected / done confirmation only.
        static let ok = Color(red: 0.42, green: 0.82, blue: 0.58)
    }

    // MARK: Type — Geist only, natural tracking

    enum Face {
        static let regular = "Geist-Regular"
        static let medium = "Geist-Medium"
        static let semibold = "Geist-SemiBold"
    }

    enum Style {
        /// Focus item title.
        case title
        /// Row title.
        case body
        /// Group headers, tab labels, buttons.
        case label
        /// Secondary line.
        case meta
        /// Emphasised value on the right of a row (time, countdown).
        case value
        /// Large live value (timer).
        case display

        var font: Font {
            switch self {
            case .title: Hud.font(15, .semibold)
            case .body: Hud.font(13.5, .medium)
            case .label: Hud.font(12.5, .medium)
            case .meta: Hud.font(12, .regular)
            case .value: Hud.font(13.5, .medium)
            case .display: Hud.font(22, .semibold)
            }
        }
    }

    enum Weight { case regular, medium, semibold }

    /// Geist at any size, for the few places the named styles don't fit (page titles in
    /// windows, large timers).
    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        _ = fontsReady
        let face = switch weight {
        case .regular: Face.regular
        case .medium: Face.medium
        case .semibold: Face.semibold
        }
        return .custom(face, fixedSize: size)
    }

    // MARK: Motion

    enum Motion {
        /// Colour fades on hover.
        static let hover = Animation.easeOut(duration: 0.14)
        /// Highlights and indicators gliding between items.
        static let glide = Animation.spring(response: 0.3, dampingFraction: 0.86)
        /// Content swaps inside a surface.
        static let change = Animation.smooth(duration: 0.28)
        /// The notch changing shape.
        static let morph = Animation.spring(response: 0.46, dampingFraction: 0.84)
    }

    // MARK: Fonts

    /// Registers the bundled Geist faces once, on first use of any Hud font.
    private static let fontsReady: Void = {
        for name in [Face.regular, Face.medium, Face.semibold] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers the bundled Geist faces with the process. Safe to call repeatedly.
    static func registerFonts() {
        _ = fontsReady
    }
}

extension View {
    /// Applies a type style and colour. Digits are tabular so times never shift.
    func hud(_ style: Hud.Style, _ color: Color = Hud.Ink.text1) -> some View {
        font(style.font).monospacedDigit().foregroundStyle(color)
    }
}
