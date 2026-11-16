import CoreText
import SwiftUI

/// Design proposal — "instrument" language.
///
/// A compact tool, read in a glance. Neutral greys carry everything; colour only ever
/// means state (now, live, blocked). Inter for words, SF Mono for numbers and small
/// uppercase labels — the one place the retro HUD shows through, together with dotted
/// leaders, segmented meters and one stroke icon family. Every row has a fixed height
/// and fixed insets in every state, so nothing moves under the pointer.
enum Hud {
    // MARK: Grid

    enum Space {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
    }

    enum Size {
        static let row: CGFloat = 32
        static let label: CGFloat = 24
        static let timeColumn: CGFloat = 46
        static let icon: CGFloat = 14
        static let panelInset: CGFloat = 20
        static let corner: CGFloat = 6
    }

    // MARK: Colour — neutral, colour means state

    enum Ink {
        static let canvas = Color.black
        /// Hover / selection fill. Flat, never a border.
        static let hover = Color(white: 1, opacity: 0.055)
        static let press = Color(white: 1, opacity: 0.085)
        static let line = Color(white: 1, opacity: 0.08)
        static let dot = Color(white: 1, opacity: 0.16)

        static let text1 = Color(red: 0.93, green: 0.93, blue: 0.94)
        static let text2 = Color(red: 0.62, green: 0.62, blue: 0.65)
        static let text3 = Color(red: 0.42, green: 0.42, blue: 0.45)
        static let text4 = Color(red: 0.28, green: 0.28, blue: 0.30)

        /// "Now": the thing that needs you next. Used sparingly.
        static let signal = Color(red: 1.0, green: 0.71, blue: 0.24)
        /// Live capture and blocked work.
        static let live = Color(red: 1.0, green: 0.33, blue: 0.33)
        /// Calm confirmation (done, connected). Never decorative.
        static let ok = Color(red: 0.45, green: 0.80, blue: 0.62)
    }

    // MARK: Type

    enum Face {
        static let regular = "Inter-Regular"
        static let medium = "Inter-Medium"
        static let semibold = "Inter-SemiBold"
    }

    enum Style {
        case title        // focus item title
        case body         // row title
        case bodyStrong
        case meta         // secondary line
        case label        // MONO UPPERCASE section label
        case numeral      // mono times, durations
        case numeralLarge // mono timers
        case key          // superscript key hints

        var font: Font {
            switch self {
            case .title: .custom(Face.semibold, fixedSize: 15)
            case .body: .custom(Face.medium, fixedSize: 13)
            case .bodyStrong: .custom(Face.semibold, fixedSize: 13)
            case .meta: .custom(Face.regular, fixedSize: 12)
            case .label: .system(size: 10, weight: .medium, design: .monospaced)
            case .numeral: .system(size: 12, weight: .regular, design: .monospaced)
            case .numeralLarge: .system(size: 20, weight: .medium, design: .monospaced)
            case .key: .system(size: 8.5, weight: .medium, design: .monospaced)
            }
        }

        var tracking: CGFloat {
            switch self {
            case .label: 1.1
            case .title: -0.2
            case .body, .bodyStrong: -0.1
            case .numeralLarge: -0.5
            default: 0
            }
        }
    }

    // MARK: Motion — one curve for everything that changes in place

    enum Motion {
        static let hover = Animation.easeOut(duration: 0.12)
        static let change = Animation.smooth(duration: 0.24)
        static let morph = Animation.spring(response: 0.4, dampingFraction: 0.92)
    }

    // MARK: Fonts

    private static var fontsRegistered = false

    /// Registers the bundled Inter faces with the process. Safe to call repeatedly.
    static func registerFonts(bundle: Bundle = .main) {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        for name in [Face.regular, Face.medium, Face.semibold] {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension View {
    func hud(_ style: Hud.Style, _ color: Color = Hud.Ink.text1) -> some View {
        font(style.font).tracking(style.tracking).foregroundStyle(color)
    }
}
