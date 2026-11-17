import CoreText
import SwiftUI

/// Crenel's design language — "gece sürüşü" (night drive). Spec: `docs/DESIGN.md`;
/// source of truth: `docs/design/crenel-prototype.html`. API reference: `README.md`
/// next to this file.
///
/// A modern macOS product skeleton — one typeface, sentence case, generous space, one
/// primary action — with retro dashboard-instrument details: lit segment numerals, tick
/// gauges, telltale lamps, printed scales. Information is lit, not drawn; unlit parts
/// stay visible as ghosts. A state's shape says what kind it is; colour only says how
/// bad. Nothing jumps: rows keep their size, highlights slide, shapes spring.
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
        /// Legacy two-line list row. New screens use `Hud.Row`.
        static let row: CGFloat = 48
        /// `.ico-s` — icons in ears, rows and buttons.
        static let icon: CGFloat = 14
        /// `.ico-xs` — icons inside small buttons and meta lines.
        static let smallIcon: CGFloat = 12
        /// `.ico` — the icon grid itself: band buttons, telltales, task marks.
        static let glyph: CGFloat = 16
        /// Legacy open-panel width; the night-drive panel is `Hud.Notch.openWidth`.
        static let panelWidth: CGFloat = 490
        /// Distance from the panel frame to text (includes the top-corner flare of the
        /// open notch). Hover fills bleed `rowInset` beyond the text.
        static let panelInset: CGFloat = 30
        /// Row padding: text sits 10 pt inside its hover slab.
        static let rowInset: CGFloat = 10
        /// Row and hover-slab radius.
        static let corner: CGFloat = 10
        /// Normal button height.
        static let control: CGFloat = 28
    }

    /// Row geometry (`.row`, `.row-1`, `.trow`, `.group-h`, `.tcol`).
    enum Row {
        /// Two-line row: 50 pt, content top-aligned 9 pt down.
        static let twoLine: CGFloat = 50
        static let twoLineTop: CGFloat = 9
        /// One-line row, vertically centred.
        static let oneLine: CGFloat = 48
        /// Task row.
        static let task: CGFloat = 38
        /// Settings row (minimum).
        static let setting: CGFloat = 50
        static let gap: CGFloat = 12
        static let inset: CGFloat = 10
        static let radius: CGFloat = 10
        static let groupHeader: CGFloat = 28
        /// Time column on the left of timetable rows.
        static let timeColumn: CGFloat = 42
    }

    /// Notch geometry (`#notch`, `.ears`, `.peek`, `.strip`, `.band`, `.console`).
    enum Notch {
        static let cameraGap: CGFloat = 186
        static let compactHeight: CGFloat = 32
        static let earPadding: CGFloat = 14
        static let earInnerPadding: CGFloat = 8
        static let earGap: CGFloat = 7
        static let earTitleMax: CGFloat = 118
        static let stripWidth: CGFloat = 440
        static let stripHeight: CGFloat = 38
        static let stripRadius: CGFloat = 12
        static let stripInset: CGFloat = 8
        static let stripBottom: CGFloat = 10
        static let openWidth: CGFloat = 560
        static let openInset: CGFloat = 14
        static let openBottom: CGFloat = 16
        static let bandHeight: CGFloat = 32
        static let consoleHeight: CGFloat = 44
        /// Top (outward flare) radius: compact, strip, open.
        static let topRadius: (compact: CGFloat, strip: CGFloat, open: CGFloat) = (6, 9, 14)
        /// Bottom radius: compact, strip, open.
        static let bottomRadius: (compact: CGFloat, strip: CGFloat, open: CGFloat) = (10, 18, 24)
        /// The compact notch leans in by this much when the pointer enters.
        static let lean = CGSize(width: 14, height: 4)
    }

    /// Desktop window geometry.
    enum Window {
        static let size = CGSize(width: 1240, height: 760)
        static let radius: CGFloat = 12
        static let sidebarWidth: CGFloat = 224
        static let toolbarHeight: CGFloat = 60
        static let settingsRailWidth: CGFloat = 200
        static let meetingListWidth: CGFloat = 300
        static let detailRailWidth: CGFloat = 232
        static let railItem: CGFloat = 34
    }

    // MARK: Radius

    enum Radius {
        /// Lamps, ruler blocks.
        static let lamp: CGFloat = 2
        /// Keycaps.
        static let key: CGFloat = 4
        /// xs buttons, chips.
        static let xs: CGFloat = 6
        /// Pills, segmented items, small chips.
        static let s: CGFloat = 7
        /// Buttons, selects, fields.
        static let control: CGFloat = 8
        /// Large buttons, rail items, search.
        static let l: CGFloat = 9
        /// Rows, hover slab, frames.
        static let row: CGFloat = 10
        /// Wells, strip, task input.
        static let well: CGFloat = 12
        /// Console.
        static let console: CGFloat = 13
        /// Sheets, settings groups, task card.
        static let sheet: CGFloat = 14
        /// Panels and tiles.
        static let panel: CGFloat = 16
    }

    // MARK: Colour — warm backlit ink; colour means state

    enum Ink {
        static let canvas = Color.black

        // Backlit ink: a hair warm, like a lit instrument face. Never pure grey.
        static let ink1 = Color(hud: 0xF3F1EC)
        static let ink2 = Color(hud: 0xAAA7A1)
        static let ink3 = Color(hud: 0x76736E)
        static let ink4 = Color(hud: 0x4C4A47)
        static let ink5 = Color(hud: 0x2E2D2B)
        /// Unlit annunciator words.
        static let ghostWord = Color(hud: 0x3A3936)
        /// Text on the lit (primary) key.
        static let onKey = Color(hud: 0x0B0B0A)
        /// Danger ink on a secondary key.
        static let danger = Color(hud: 0xFF6B59)

        // Legacy names for the same scale.
        static let text1 = ink1
        static let text2 = ink2
        static let text3 = ink3
        static let text4 = ink4

        // Surfaces on black: white at low opacity.
        /// Hover slab under a row.
        static let hover = Color(white: 1, opacity: 0.055)
        /// Field well (text field, select, strip).
        static let field = Color(white: 1, opacity: 0.055)
        /// Focused field.
        static let fieldFocus = Color(white: 1, opacity: 0.09)
        /// Quiet button / chip.
        static let quiet = Color(white: 1, opacity: 0.07)
        /// Selected segment, pill, tray state.
        static let selected = Color(white: 1, opacity: 0.10)
        static let press = Color(white: 1, opacity: 0.10)
        /// Unlit meter track.
        static let track = Color(white: 1, opacity: 0.08)
        /// Ghost for unlit instrument parts (6–13 % by instrument).
        static func ghost(_ opacity: Double = 0.09) -> Color { Color(white: 1, opacity: opacity) }

        /// Amber — waiting for you.
        static let signal = Color(hud: 0xFFAD33)
        /// Red — live capture, error, blocked.
        static let live = Color(hud: 0xFF5A47)
        /// Phosphor teal — ready, connected, inserted (the app icon's colour).
        static let ok = Color(hud: 0x34E6CB)
        /// The mark's own teal (`i-mark` in the band and the app tile).
        static let mark = Color(hud: 0x14F0D4)
    }

    /// Lamp colours with their hot cores and the two glow layers (tight, wide).
    enum LampColor: Equatable, Sendable {
        case amber, red, teal, white
        /// Lit but quiet: flat ink-3, no glow (`on-d`).
        case dim
        case off

        var color: Color {
            switch self {
            case .amber: Ink.signal
            case .red: Ink.live
            case .teal: Ink.ok
            case .white: Ink.ink1
            case .dim: Ink.ink3
            case .off: Color(white: 1, opacity: 0.09)
            }
        }

        /// The centre of a lit lamp.
        var core: Color {
            switch self {
            case .amber: Color(hud: 0xFFE2B3)
            case .red: Color(hud: 0xFFC2B8)
            case .teal: Color(hud: 0xB9FFF3)
            case .white: .white
            case .dim, .off: color
            }
        }

        /// Where the core has fully become the lamp colour (radial stop).
        var coreStop: Double { self == .white ? 0.70 : 0.72 }

        /// Tight glow (CSS 5–6 px) and wide spill (CSS 14–16 px) opacities.
        var glow: (tight: Double, wide: Double) {
            switch self {
            case .amber: (0.70, 0.22)
            case .red: (0.75, 0.24)
            case .teal: (0.65, 0.20)
            case .white: (0.60, 0.16)
            case .dim, .off: (0, 0)
            }
        }

        var isLit: Bool { self != .off && self != .dim }
    }

    /// Window layers and raised surfaces.
    enum Layer {
        static let sidebar = Color(hud: 0x080807)
        static let window = Color(hud: 0x0E0E0D)
        static let sheet = Color(hud: 0x121211)
        static let wellTop = Color(hud: 0x050505)
        static let wellBottom = Color(hud: 0x0A0A09)
        /// 1 px hairline rings.
        static let ring = Color(white: 1, opacity: 0.05)
    }

    // MARK: Type — Geist only, sentence case; large sizes tighten, never widen

    enum Face {
        static let regular = "Geist-Regular"
        static let medium = "Geist-Medium"
        static let semibold = "Geist-SemiBold"
    }

    enum Style {
        /// 17 / 600, −0.012 em — the focused event, detail title.
        case hero
        /// 15 / 600, −0.006 em — card and result titles.
        case title
        /// 13 / 500 — row title.
        case body
        /// 12.5 / 500 — tabs, buttons, group headers.
        case label
        /// 11.5 / 400, ink-3 — second line.
        case meta
        /// 10 / 500, ink-4 — scale labels, under-unit.
        case micro
        /// 11 / 500, ink-3 — the unit beside a segment number ("min", "left", "%").
        case unit
        /// 13 / 400, line 1.6 — summary, transcript.
        case read
        /// 22 / 600, −0.02 em — desktop page heroes ("Next meeting" title).
        case page
        /// Legacy: emphasised value on the right of a row. Same as `body`.
        case value
        /// Legacy: large live value. New screens use `HudSegmentDigits`.
        case display

        var size: CGFloat {
            switch self {
            case .hero: 17
            case .title: 15
            case .body, .read, .value: 13
            case .label: 12.5
            case .meta: 11.5
            case .micro: 10
            case .unit: 11
            case .page, .display: 22
            }
        }

        var weight: Weight {
            switch self {
            case .hero, .title, .page, .display: .semibold
            case .body, .label, .micro, .unit, .value: .medium
            case .meta, .read: .regular
            }
        }

        var font: Font { Hud.font(size, weight) }

        /// Tracking in points (CSS em × size).
        var tracking: CGFloat {
            switch self {
            case .hero: -0.012 * 17
            case .title: -0.006 * 15
            case .page, .display: -0.02 * 22
            default: 0
            }
        }

        /// Extra space between lines so the line box matches the prototype's
        /// line-height (Geist's natural line is ≈ 1.3).
        var lineSpacing: CGFloat { self == .read ? 13 * 0.3 : 0 }

        var defaultColor: Color {
            switch self {
            case .meta, .unit: Ink.ink3
            case .micro: Ink.ink4
            default: Ink.ink1
            }
        }
    }

    enum Weight { case regular, medium, semibold }

    /// Geist at any size, for the few places the named styles don't fit.
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
        /// The notch changing shape: 0.52 s `cubic-bezier(.3,1.16,.4,1)`.
        static let shape = Animation.timingCurve(0.3, 1.16, 0.4, 1, duration: 0.52)
        /// Content appears after the shape: 0.18 s, delayed 0.11–0.12 s.
        static let content = Animation.easeOut(duration: 0.18).delay(0.115)
        /// The hover slab sliding between rows: 0.18 s `cubic-bezier(.2,.8,.2,1)`.
        static let slab = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
        /// The tab lamp: 0.32 s `cubic-bezier(.3,1.25,.4,1)`.
        static let tabLamp = Animation.timingCurve(0.3, 1.25, 0.4, 1, duration: 0.32)
        /// The rail lamp: 0.34 s `cubic-bezier(.3,1.2,.4,1)`.
        static let railLamp = Animation.timingCurve(0.3, 1.2, 0.4, 1, duration: 0.34)
        /// A task row sliding to reveal its actions: 0.38 s `cubic-bezier(.3,1.08,.4,1)`.
        static let rowSlide = Animation.timingCurve(0.3, 1.08, 0.4, 1, duration: 0.38)
        /// Sections entering: 0.32 s `cubic-bezier(.2,.8,.2,1)`, 5 pt from above.
        static let enter = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
        static let enterOffset: CGFloat = -5
        /// Stagger: first section after 40 ms, each next one 28 ms later.
        static let staggerBase: Double = 0.040
        static let staggerStep: Double = 0.028
        /// Ignition: gauges sweep to full (0.42 s) and settle to their value (0.52 s),
        /// both ease-out cubic.
        static let igniteUp = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.42)
        static let igniteDown = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.52)
        static let igniteUpDuration: Double = 0.42
        static let igniteDownDuration: Double = 0.52
        /// Pointer enters the compact notch: lean, then open after this delay.
        static let leanDelay: Double = 0.18
        /// Buttons, chips: colour and fill changes.
        static let hover = Animation.easeOut(duration: 0.15)
        /// Toggle knob, annunciator words.
        static let toggle = Animation.easeInOut(duration: 0.2)
        /// A card opening in place of its row.
        static let card = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
        /// Onboarding lamps light this far apart.
        static let lampSequence: Double = 0.42
        /// Result strips close after 8 s; the "inserted" strip after 3 s.
        static let stripDismiss: Double = 8
        static let insertedDismiss: Double = 3

        // Loop periods.
        static let pulsePeriod: Double = 1.4
        static let breathePeriod: Double = 1.8
        static let blinkPeriod: Double = 1.1
        static let busyPeriod: Double = 1.05
        static let caretPeriod: Double = 1.0
        static let scanPeriod: Double = 1.6
        /// VU peak cell holds this long before it falls.
        static let peakHold: Double = 0.7

        // Legacy names.
        /// Highlights and indicators gliding between items.
        static let glide = slab
        /// Content swaps inside a surface.
        static let change = Animation.smooth(duration: 0.28)
        /// The notch changing shape.
        static let morph = shape
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

extension Color {
    /// `Color(hud: 0xF3F1EC)` — an sRGB hex colour.
    init(hud hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// `color-mix(in srgb, self p%, white)`.
    func hudMixedWithWhite(_ whiteFraction: Double) -> Color {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let f = whiteFraction
        return Color(
            .sRGB,
            red: Double(c.redComponent) * (1 - f) + f,
            green: Double(c.greenComponent) * (1 - f) + f,
            blue: Double(c.blueComponent) * (1 - f) + f,
            opacity: Double(c.alphaComponent)
        )
    }
}

// MARK: - Environment

private struct HudSurfaceKey: EnvironmentKey {
    static let defaultValue: Color = .black
}

extension EnvironmentValues {
    /// The colour behind the content (CSS `--surface`): icon cut-outs — the mic-off
    /// slash, corner badges — are drawn in it. Black in the notch; set it to
    /// `Hud.Layer.sidebar` / `.window` / `.sheet` on desktop layers.
    var hudSurface: Color {
        get { self[HudSurfaceKey.self] }
        set { self[HudSurfaceKey.self] = newValue }
    }
}

extension View {
    /// Applies a type style: font, tracking, line height and colour (the style's own
    /// ink when `color` is nil). Digits are tabular so times never shift.
    func hud(_ style: Hud.Style, _ color: Color? = nil) -> some View {
        font(style.font)
            .monospacedDigit()
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .foregroundStyle(color ?? style.defaultColor)
    }

    /// Declares the surface colour for icon cut-outs below this view.
    func hudSurface(_ color: Color) -> some View {
        environment(\.hudSurface, color)
    }

    /// Two-layer bloom, as a lit part behind glass: a tight core glow and a wide faint
    /// spill. Radii are the prototype's `drop-shadow(0 0 Npx …)` values, whose blur is a
    /// standard deviation — the same unit as SwiftUI's shadow radius. (`box-shadow` and
    /// `text-shadow` blurs are twice their deviation, so those are halved where used.)
    func hudGlow(_ color: Color, tight: CGFloat = 2, tightOpacity: Double = 0.6,
                 wide: CGFloat = 7, wideOpacity: Double = 0.22, enabled: Bool = true) -> some View {
        self
            .shadow(color: enabled ? color.opacity(tightOpacity) : .clear, radius: tight)
            .shadow(color: enabled ? color.opacity(wideOpacity) : .clear, radius: wide)
    }

    /// Light bleed (`.bleed`): a radial spill of the readout's colour behind it — 10 % at
    /// the centre, 3 % at 60 %, gone at the edge — reaching `inset` points past the view.
    /// Gauges have it built in; use this behind the recording clock (red).
    func hudBleed(_ color: Color, inset: CGFloat = 30) -> some View {
        background {
            EllipticalGradient(
                stops: [.init(color: color.opacity(0.10), location: 0), .init(color: color.opacity(0.03), location: 0.6),
                        .init(color: color.opacity(0), location: 1)],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
            )
            .padding(-inset)
            .allowsHitTesting(false)
        }
    }

    /// Sections of a surface float in from 5 pt above, 28 ms apart. Give each section
    /// its index; flip `shown` when the surface appears.
    func hudStagger(_ index: Int, shown: Bool, reduceMotion: Bool = false) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Hud.Motion.enterOffset)
            .animation(
                reduceMotion ? .linear(duration: 0.01)
                    : Hud.Motion.enter.delay(Hud.Motion.staggerBase + Double(index) * Hud.Motion.staggerStep),
                value: shown
            )
    }
}
