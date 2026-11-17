import SwiftUI

/// One icon family, ported from the prototype's sprite: 16-unit grid, 1.5 stroke, square
/// ends, mitred joins, 45° chamfers instead of round corners. Every glyph has a line
/// form (`i-*`, at rest); the ones that can light also have a solid form (`f-*`) with
/// their details cut out — like a dashboard telltale.
enum HudGlyph: String, CaseIterable, Sendable {
    case calendar, queue, mic, micOff, speaker, video, window, pin, history, tape, repeats
    case record, stop, chevronRight, chevronLeft, chevronDown, arrowRight, plus, close
    case spark, link, bell, place, transcript, sliders, shield, warning, people, keyboard
    case edit, copy, trash, more, play, pause, waveform, search, archive, accessibility
    case sun, gauge, clock, globe, share

    /// True when the glyph has a lit, solid form (`f-*`).
    var hasSolid: Bool { HudGlyphArt.solid[self] != nil }
}

/// A corner badge in the bottom-right 6.75 slot of a glyph (`mod-bang`, `mod-x`). The
/// badge is cut from the glyph by a 1.5 gap in the surface colour.
enum HudGlyphBadge: Sendable {
    case bang, x
}

/// One drawing step of a glyph, in 16×16 unit space.
struct HudGlyphLayer {
    enum Paint { case ink, surface }
    enum Draw {
        case stroke(width: CGFloat, cap: CGLineCap)
        case fill
    }

    let path: Path
    let draw: Draw
    var paint: Paint = .ink
    var opacity: Double = 1
}

enum HudGlyphArt {
    private static func stroke(_ d: String, width: CGFloat = 1.5, cap: CGLineCap = .square, paint: HudGlyphLayer.Paint = .ink) -> HudGlyphLayer {
        HudGlyphLayer(path: HudSVGPath.path(d), draw: .stroke(width: width, cap: cap), paint: paint)
    }

    /// Even-odd fill: later subpaths cut holes.
    private static func fill(_ d: String) -> HudGlyphLayer {
        HudGlyphLayer(path: HudSVGPath.path(d), draw: .fill)
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, paint: HudGlyphLayer.Paint = .ink) -> HudGlyphLayer {
        HudGlyphLayer(path: HudSVGPath.rect(x, y, w, h), draw: .fill, paint: paint)
    }

    private static let micStand = "M3.25 7V8.5L5.75 11.5H10.25L12.75 8.5V7M8 11.5V14.25M5.75 14.25H10.25"
    private static let micBody = "M6.25 1.75H9.75L10.75 2.75V8.25L9.75 9.25H6.25L5.25 8.25V2.75Z"
    private static let micSolid = "M6 1H10L11.5 2.5V8.5L10 10H6L4.5 8.5V2.5ZM6.5 4H9.5V5H6.5ZM6.5 6H9.5V7H6.5Z"
    private static let speakerWaves = "M10.75 6L11.75 8L10.75 10M12.75 3.75L14.25 8L12.75 12.25"
    private static let slash: [HudGlyphLayer] = [
        stroke("M2 2L14 14", width: 3.5, cap: .butt, paint: .surface),
        stroke("M2.75 2.75L13.25 13.25")
    ]

    /// `i-*` — line forms.
    static let line: [HudGlyph: [HudGlyphLayer]] = [
        .calendar: [
            stroke("M4.25 3.25H11.75L13.25 4.75V11.75L11.75 13.25H4.25L2.75 11.75V4.75Z"),
            stroke("M2.75 6.75H13.25M5.25 1.75V3.25M10.75 1.75V3.25"),
            rect(9.25, 9.25, 2.25, 2.25)
        ],
        .queue: [rect(2, 2.75, 3.5, 3.5), stroke("M8.25 4.5H13.75M2.75 8.5H13.75M2.75 12.5H10.25")],
        .mic: [stroke(micBody), stroke(micStand)],
        .micOff: [stroke(micBody), stroke(micStand)] + slash,
        .speaker: [stroke("M1.75 5.75H4.5L8.25 2.5V13.5L4.5 10.25H1.75Z"), stroke(speakerWaves)],
        .video: [stroke("M3 4.25H9.25L10.25 5.25V10.75L9.25 11.75H3L2 10.75V5.25Z"), stroke("M10.25 7L14 4.75V11.25L10.25 9")],
        .window: [stroke("M1.75 2.75H14.25V13.25H1.75ZM1.75 6.25H14.25"), rect(3.5, 3.75, 1.5, 1.5)],
        .pin: [stroke("M5.75 2.25H10.25M6.75 2.25V5.75L4.5 8.75H11.5L9.25 5.75V2.25M8 8.75V13.75")],
        .history: [stroke("M3 11L2.25 8L3 5L6 2.5H10L13 5L13.75 8L13 11L10 13.5H6.5"), stroke("M2.25 2.25V5H5M8 5.25V8.25L10.25 9.75")],
        .tape: [
            stroke("M2.75 3.25H13.25L14.25 4.25V12.75H1.75V4.25Z"),
            stroke("M3.75 5.75H6.25V8.25H3.75ZM9.75 5.75H12.25V8.25H9.75ZM6.25 8.25H9.75M4.25 12.75L5.25 10.75H10.75L11.75 12.75")
        ],
        .repeats: [stroke("M2.75 7.25V4.25H13.25M11 2L13.25 4.25L11 6.5M13.25 8.75V11.75H2.75M5 14L2.75 11.75L5 9.5")],
        .record: [HudGlyphLayer(path: Path(ellipseIn: CGRect(x: 4, y: 4, width: 8, height: 8)), draw: .fill)],
        .stop: [rect(4.25, 4.25, 7.5, 7.5)],
        .chevronRight: [stroke("M6.25 3.5L10.75 8L6.25 12.5")],
        .chevronLeft: [stroke("M9.75 3.5L5.25 8L9.75 12.5")],
        .chevronDown: [stroke("M3.5 6.25L8 10.75L12.5 6.25")],
        .arrowRight: [stroke("M2.75 8H13M9 4L13 8L9 12")],
        .plus: [stroke("M8 3V13M3 8H13")],
        .close: [stroke("M4.25 4.25L11.75 11.75M11.75 4.25L4.25 11.75")],
        .spark: [stroke("M8 1.75L9.5 6.5L14.25 8L9.5 9.5L8 14.25L6.5 9.5L1.75 8L6.5 6.5Z")],
        .link: [stroke("M9.75 2.25H13.75V6.25M13.25 2.75L7.75 8.25M11.75 9.75V13.75H2.25V4.25H6.25")],
        .bell: [stroke("M3.75 11.25V6.5L6 3.25H10L12.25 6.5V11.25L13.5 12.5H2.5Z"), stroke("M6.75 14.25H9.25")],
        .place: [stroke("M8 14.25L3.25 9V5.25L5.75 2.25H10.25L12.75 5.25V9Z"), rect(7, 5.25, 2, 2)],
        .transcript: [stroke("M3.25 1.75H9.5L12.75 5V14.25H3.25Z"), stroke("M9.25 1.75V5.25H12.75M5.75 8.25H10.25M5.75 11H8.5")],
        .sliders: [stroke("M2 5H7M11.5 5H14M2 11H3.5M8 11H14M7 3.25H10.5V6.75H7ZM3.75 9.25H7.25V12.75H3.75Z")],
        .shield: [stroke("M8 1.75L13.25 3.75V8L8 14.25L2.75 8V3.75Z")],
        .warning: [stroke("M8 2.25L14.25 13.25H1.75Z"), stroke("M8 6.75V9"), rect(7.25, 10.5, 1.5, 1.5)],
        .people: [stroke("M4.75 2.5H7.25L8.25 3.5V6L7.25 7H4.75L3.75 6V3.5ZM1.75 13.75V11.75L3.75 9.75H8.25L10.25 11.75V13.75M10.75 2.5H11.75L12.75 3.5V6L11.75 7H10.75M12 9.75L14.25 11.75V13.75")],
        .keyboard: [
            stroke("M2.5 3.75H13.5L14.5 4.75V11.25L13.5 12.25H2.5L1.5 11.25V4.75Z"),
            stroke("M4.5 6.75H4.51M7 6.75H7.01M9.5 6.75H9.51M12 6.75H12.01M5.25 9.5H10.75")
        ],
        .edit: [stroke("M10.5 2.25L13.75 5.5L5.5 13.75H2.25V10.5ZM8.5 4.25L11.75 7.5")],
        .copy: [stroke("M5.25 5.25H13.75V13.75H5.25ZM10.75 5.25V2.25H2.25V10.75H5.25")],
        .trash: [stroke("M2.5 4.25H13.5M6.25 4.25V2.25H9.75V4.25M3.75 4.25L4.5 14H11.5L12.25 4.25M6.75 7V11M9.25 7V11")],
        .more: [rect(2.5, 7.25, 2, 2), rect(7, 7.25, 2, 2), rect(11.5, 7.25, 2, 2)],
        .play: [fill("M4.5 2.75V13.25L13 8Z")],
        .pause: [rect(4, 3, 2.75, 10), rect(9.25, 3, 2.75, 10)],
        .waveform: [stroke("M2.75 7V9M5.25 5V11M7.75 2.75V13.25M10.25 5.5V10.5M12.75 7V9")],
        .search: [stroke("M4.75 2.25H8.25L10.75 4.75V8.25L8.25 10.75H4.75L2.25 8.25V4.75ZM10.5 10.5L13.75 13.75")],
        .archive: [stroke("M1.75 2.75H14.25V6.25H1.75ZM2.75 6.25V13.25H13.25V6.25M6.5 9H9.5")],
        .accessibility: [rect(7.25, 1.5, 1.5, 1.5), stroke("M2.75 5.5H13.25M8 5.5V9.5M8 9.5L5.5 14.25M8 9.5L10.5 14.25")],
        .sun: [stroke("M5.75 5.75H10.25V10.25H5.75ZM8 1.75V3M8 13V14.25M1.75 8H3M13 8H14.25M3.6 3.6L4.3 4.3M11.7 11.7L12.4 12.4M3.6 12.4L4.3 11.7M11.7 4.3L12.4 3.6")],
        .gauge: [stroke("M3 12.5L2.25 9L3.5 5.25L6.25 3H9.75L12.5 5.25L13.75 9L13 12.5M8 9L10.75 6.25"), rect(7, 8, 2, 2)],
        .clock: [stroke("M5.5 1.75H10.5L14.25 5.5V10.5L10.5 14.25H5.5L1.75 10.5V5.5ZM8 4.75V8H10.5")],
        .globe: [stroke("M5.5 1.75H10.5L14.25 5.5V10.5L10.5 14.25H5.5L1.75 10.5V5.5ZM1.75 8H14.25M8 1.75L10.5 8L8 14.25L5.5 8Z")],
        .share: [stroke("M8 10V2.5M5.25 5.25L8 2.5L10.75 5.25M4.75 7.25H2.25V13.75H13.75V7.25H11.25")]
    ]

    /// `f-*` — solid, lit forms with their details cut out.
    static let solid: [HudGlyph: [HudGlyphLayer]] = [
        .calendar: [
            fill("M4 2.5H12L14 4.5V12L12 14H4L2 12V4.5ZM3.5 6H12.5V7.5H3.5ZM9 9H11.5V11.5H9Z"),
            rect(4.5, 0.75, 1.5, 2.5), rect(10, 0.75, 1.5, 2.5)
        ],
        .queue: [rect(1.5, 2, 4.5, 4.5), rect(7.5, 3.5, 6.75, 2), rect(1.5, 7.5, 12.75, 2), rect(1.5, 11.5, 9, 2)],
        .mic: [fill(micSolid), stroke(micStand)],
        .micOff: [fill(micSolid), stroke(micStand)] + slash,
        .speaker: [fill("M1 5H4.25L8.75 1.5V14.5L4.25 11H1Z"), stroke(speakerWaves)],
        .video: [fill("M2.5 3.75H9.75L11 5V11L9.75 12.25H2.5L1.25 11V5ZM11.75 6.75L14.75 4.75V11.25L11.75 9.25Z")],
        .tape: [fill("M2.5 2.5H13.5L15 4V13.5H1V4ZM3.5 5.5H6.5V8.5H3.5ZM9.5 5.5H12.5V8.5H9.5ZM5 13.5L5.75 11H10.25L11 13.5Z")],
        .transcript: [fill("M2.5 1H9.75L13.5 4.75V15H2.5ZM5 7.5H11V9H5ZM5 10.5H9V12H5Z")],
        .spark: [fill("M8 .75L9.9 6.1L15.25 8L9.9 9.9L8 15.25L6.1 9.9L.75 8L6.1 6.1Z")],
        .keyboard: [fill("M2 3H14L15 4V12L14 13H2L1 12V4ZM3.75 5.75H5.25V7.25H3.75ZM6.25 5.75H7.75V7.25H6.25ZM8.75 5.75H10.25V7.25H8.75ZM11.25 5.75H12.75V7.25H11.25ZM4.5 9H11.5V10.5H4.5Z")],
        .accessibility: [rect(6.75, 0.75, 2.5, 2.5), stroke("M2.5 5.5H13.5M8 5.5V9.5M8 9.5L5.25 14.5M8 9.5L10.75 14.5", width: 2.25)],
        .gauge: [fill("M2.25 12.75L1.25 8.75L2.75 4.5L6 1.75H10L13.25 4.5L14.75 8.75L13.75 12.75ZM7.25 9.5L10.6 5.4L11.4 6L8.6 10.5Z")],
        .waveform: [stroke("M2.75 7V9M5.25 5V11M7.75 2.75V13.25M10.25 5.5V10.5M12.75 7V9", width: 2.25)],
        .sliders: [stroke("M2 5H7M11.5 5H14M2 11H3.5M8 11H14"), rect(6.5, 2.75, 4.5, 4.5), rect(3.25, 8.75, 4.5, 4.5)],
        .sun: [rect(5, 5, 6, 6), stroke("M8 1.75V2.75M8 13.25V14.25M1.75 8H2.75M13.25 8H14.25M3.6 3.6L4.1 4.1M11.9 11.9L12.4 12.4M3.6 12.4L4.1 11.9M11.9 4.1L12.4 3.6")],
        .archive: [fill("M1 2H15V6H1ZM2 7H14V14H2ZM6 9H10V10.5H6Z")],
        .warning: [fill("M8 1L15.25 14H.75ZM7.25 5.75H8.75V9.5H7.25ZM7.25 10.75H8.75V12.25H7.25Z")],
        .bell: [fill("M3 11V6.25L5.75 2.5H10.25L13 6.25V11L14.5 12.5V13H1.5V12.5Z"), rect(6.25, 14, 3.5, 1.5)],
        .shield: [fill("M8 1L14 3.25V8.25L8 15L2 8.25V3.25Z")]
    ]

    /// `mod-*` — corner badges.
    static func badge(_ badge: HudGlyphBadge) -> [HudGlyphLayer] {
        let plate: [HudGlyphLayer] = [
            // The surface-coloured gap around the badge, then the badge itself.
            HudGlyphLayer(path: HudSVGPath.rect(8.5, 8.5, 8.25, 8.25), draw: .fill, paint: .surface),
            HudGlyphLayer(path: HudSVGPath.rect(10, 10, 5.25, 5.25), draw: .fill)
        ]
        switch badge {
        case .bang:
            return plate + [rect(12, 10.5, 1.25, 3, paint: .surface), rect(12, 14, 1.25, 1.1, paint: .surface)]
        case .x:
            return plate + [stroke("M11.1 11.1L14.15 14.15M14.15 11.1L11.1 14.15", width: 1.2, cap: .butt, paint: .surface)]
        }
    }

    /// `i-paren` — angled brackets on a 24×16 box: "system / permission fault".
    static let paren = HudSVGPath.path("M3.5 1.75L1.5 8L3.5 14.25M20.5 1.75L22.5 8L20.5 14.25")

    /// `i-logo` on a 24×24 box.
    static let logo = HudSVGPath.path("M8 6.5H7.5Q8.5 6.5 8.5 7.5V8.7Q8.5 9.7 9.5 9.7H14.5Q15.5 9.7 15.5 8.7V7.5Q15.5 6.5 16.5 6.5H16A5.5 5.5 0 0 1 21.5 12A5.5 5.5 0 0 1 16 17.5H8A5.5 5.5 0 0 1 2.5 12A5.5 5.5 0 0 1 8 6.5Z")

    /// `i-mark` — six lamps in a crenel, on a 472×296 box. The opacity per lamp is part
    /// of the mark.
    static let mark: [(rect: CGRect, opacity: Double)] = [
        (CGRect(x: 59, y: 0, width: 118, height: 119), 0.70),
        (CGRect(x: 0, y: 119, width: 118, height: 118), 0.76),
        (CGRect(x: 118, y: 178, width: 118, height: 118), 0.50),
        (CGRect(x: 236, y: 178, width: 118, height: 118), 0.65),
        (CGRect(x: 295, y: 0, width: 118, height: 119), 0.56),
        (CGRect(x: 354, y: 119, width: 118, height: 118), 1.0)
    ]

    static func draw(_ layers: [HudGlyphLayer], in context: inout GraphicsContext, scale: CGFloat,
                     ink: GraphicsContext.Shading, surface: Color) {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        for layer in layers {
            let shading: GraphicsContext.Shading = layer.paint == .ink ? ink : .color(surface)
            let path = layer.path.applying(transform)
            var layerContext = context
            layerContext.opacity = layer.opacity
            switch layer.draw {
            case let .stroke(width, cap):
                layerContext.stroke(path, with: shading,
                                    style: StrokeStyle(lineWidth: width * scale, lineCap: cap, lineJoin: .miter, miterLimit: 4))
            case .fill:
                layerContext.fill(path, with: shading, style: FillStyle(eoFill: true))
            }
        }
    }
}

/// A glyph at a size, in the foreground style of its row.
///
///     HudIcon(.mic)                          // line form, 14 pt
///     HudIcon(.mic, size: 16, solid: true)   // lit form
///     HudIcon(.speaker, solid: true, badge: .bang).foregroundStyle(Hud.Ink.live)
struct HudIcon: View {
    let glyph: HudGlyph
    var size: CGFloat = Hud.Size.icon
    /// Draws the solid (`f-*`) form when the glyph has one.
    var solid = false
    var badge: HudGlyphBadge?
    @Environment(\.hudSurface) private var surface

    init(_ glyph: HudGlyph, size: CGFloat = Hud.Size.icon, solid: Bool = false, badge: HudGlyphBadge? = nil) {
        self.glyph = glyph
        self.size = size
        self.solid = solid
        self.badge = badge
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 16
            let layers = (solid ? HudGlyphArt.solid[glyph] : nil) ?? HudGlyphArt.line[glyph] ?? []
            HudGlyphArt.draw(layers, in: &context, scale: scale, ink: .foreground, surface: surface)
            if let badge {
                HudGlyphArt.draw(HudGlyphArt.badge(badge), in: &context, scale: scale, ink: .foreground, surface: surface)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark: six lamps in a crenel (the app icon's glyph), lit in its own teal.
///
///     HudMark()                 // 15 × 9.4, as in the open notch band
///     HudMark(width: 46, glow: 6)
struct HudMark: View {
    var width: CGFloat = 15
    var color: Color = Hud.Ink.mark
    /// Glow radius (CSS drop-shadow blur): 2.5 in the band and tile, 6 on the onboarding gauge.
    var glow: CGFloat = 2.5

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 472
            for lamp in HudGlyphArt.mark {
                let rect = lamp.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
                context.fill(Path(rect), with: .color(color.opacity(lamp.opacity)))
            }
        }
        .frame(width: width, height: width * 296 / 472)
        .shadow(color: color.opacity(glow > 3 ? 0.55 : 0.6), radius: glow)
        .accessibilityHidden(true)
    }
}

/// The mark in its 26 pt black tile (`.app-tile`) — sidebar brand row.
struct HudAppTile: View {
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 7 / 26, style: .continuous)
        HudMark(width: size * 16 / 26)
            .frame(width: size, height: size)
            .background(
                shape.fill(
                    LinearGradient(colors: [Color(hud: 0x161616), Color(hud: 0x040404)],
                                   startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
                        .shadow(.inner(color: Color(white: 1, opacity: 0.06), radius: 0, x: 0, y: 1))
                )
            )
            .overlay(shape.strokeBorder(Color(white: 1, opacity: 0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
    }
}

/// The mark and the name, no tile (`.nb`) — the open notch band.
struct HudBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            HudMark()
            Text(verbatim: "Crenel").font(Hud.font(12.5, .semibold)).foregroundStyle(Hud.Ink.ink1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Crenel"))
    }
}

/// `i-logo` — the pill silhouette with a notch, on a 24-unit box.
struct HudLogo: View {
    var size: CGFloat = 24

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            context.fill(HudGlyphArt.logo.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
