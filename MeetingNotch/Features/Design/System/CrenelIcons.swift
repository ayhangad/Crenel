import SwiftUI

/// Crenel's own icon set, drawn on a 24 pt grid with one stroke weight and round caps so
/// every glyph shares the same voice. SF Symbols are not used for product iconography.
enum CrenelGlyph: String, CaseIterable, Sendable {
    case logo
    case calendar
    case tasks
    case waveform
    case mic
    case micOff
    case speaker
    case record
    case stop
    case pause
    case play
    case plus
    case check
    case close
    case chevronRight
    case chevronDown
    case chevronLeft
    case more
    case pin
    case window
    case sliders
    case sparkle
    case video
    case clock
    case arrowUpRight
    case trash
    case flag
    case archive
    case history
    case shield
    case warning
    case bell
    case people
    case keyboard
    case accessibility
    case copy
    case sun

    /// Glyphs that read as solid shapes rather than outlines.
    var isFilled: Bool {
        switch self {
        case .logo, .record, .stop, .pause, .play, .sparkle, .more: true
        default: false
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
        }

        var path = Path()
        switch self {
        case .logo:
            // A pill with a notch bitten out of its top edge: the crenel.
            let left: CGFloat = 2.5, right: CGFloat = 21.5, top: CGFloat = 6.5, bottom: CGFloat = 17.5
            let radius: CGFloat = 5.5
            let notchLeft: CGFloat = 8.5, notchRight: CGFloat = 15.5, notchDepth: CGFloat = 3.2
            path.move(to: p(left + radius, top))
            path.addLine(to: p(notchLeft - 1, top))
            path.addQuadCurve(to: p(notchLeft, top + 1), control: p(notchLeft, top))
            path.addLine(to: p(notchLeft, top + notchDepth - 1))
            path.addQuadCurve(to: p(notchLeft + 1, top + notchDepth), control: p(notchLeft, top + notchDepth))
            path.addLine(to: p(notchRight - 1, top + notchDepth))
            path.addQuadCurve(to: p(notchRight, top + notchDepth - 1), control: p(notchRight, top + notchDepth))
            path.addLine(to: p(notchRight, top + 1))
            path.addQuadCurve(to: p(notchRight + 1, top), control: p(notchRight, top))
            path.addLine(to: p(right - radius, top))
            path.addArc(center: p(right - radius, top + radius), radius: radius * s,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: p(right, bottom - radius))
            path.addArc(center: p(right - radius, bottom - radius), radius: radius * s,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: p(left + radius, bottom))
            path.addArc(center: p(left + radius, bottom - radius), radius: radius * s,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: p(left, top + radius))
            path.addArc(center: p(left + radius, top + radius), radius: radius * s,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()

        case .calendar:
            path.addRoundedRect(in: r(3.75, 5.25, 16.5, 15), cornerSize: CGSize(width: 4 * s, height: 4 * s), style: .continuous)
            path.move(to: p(3.75, 10)); path.addLine(to: p(20.25, 10))
            path.move(to: p(8.25, 3.25)); path.addLine(to: p(8.25, 6.75))
            path.move(to: p(15.75, 3.25)); path.addLine(to: p(15.75, 6.75))
            path.addEllipse(in: r(7.4, 13.4, 1.2, 1.2))
            path.addEllipse(in: r(11.4, 13.4, 1.2, 1.2))

        case .tasks:
            path.addRoundedRect(in: r(4, 4, 16, 16), cornerSize: CGSize(width: 5.5 * s, height: 5.5 * s), style: .continuous)
            path.move(to: p(8.4, 12.2)); path.addLine(to: p(10.9, 14.6)); path.addLine(to: p(15.6, 9.6))

        case .waveform:
            for (x, h) in [(4.5, 3.0), (8.25, 8.0), (12.0, 14.0), (15.75, 7.0), (19.5, 3.5)] as [(CGFloat, CGFloat)] {
                path.move(to: p(x, 12 - h / 2)); path.addLine(to: p(x, 12 + h / 2))
            }

        case .mic, .micOff:
            path.addRoundedRect(in: r(9, 3.25, 6, 11), cornerSize: CGSize(width: 3 * s, height: 3 * s))
            path.move(to: p(5.75, 11.25))
            path.addCurve(to: p(18.25, 11.25), control1: p(5.75, 19.5), control2: p(18.25, 19.5))
            path.move(to: p(12, 17.5)); path.addLine(to: p(12, 20.75))
            if self == .micOff {
                path.move(to: p(4.5, 4.5)); path.addLine(to: p(19.5, 19.5))
            }

        case .speaker:
            path.move(to: p(4, 9.5)); path.addLine(to: p(7.5, 9.5)); path.addLine(to: p(12, 5.5))
            path.addLine(to: p(12, 18.5)); path.addLine(to: p(7.5, 14.5)); path.addLine(to: p(4, 14.5)); path.closeSubpath()
            path.move(to: p(15.5, 9)); path.addQuadCurve(to: p(15.5, 15), control: p(17.6, 12))
            path.move(to: p(18, 6.5)); path.addQuadCurve(to: p(18, 17.5), control: p(22, 12))

        case .record:
            path.addEllipse(in: r(5.5, 5.5, 13, 13))

        case .stop:
            path.addRoundedRect(in: r(6.5, 6.5, 11, 11), cornerSize: CGSize(width: 3 * s, height: 3 * s), style: .continuous)

        case .pause:
            path.addRoundedRect(in: r(6.5, 5.5, 4, 13), cornerSize: CGSize(width: 1.6 * s, height: 1.6 * s))
            path.addRoundedRect(in: r(13.5, 5.5, 4, 13), cornerSize: CGSize(width: 1.6 * s, height: 1.6 * s))

        case .play:
            path.move(to: p(8, 5.6))
            path.addQuadCurve(to: p(9.6, 4.8), control: p(8.4, 4.6))
            path.addLine(to: p(18.6, 10.6))
            path.addQuadCurve(to: p(18.6, 13.4), control: p(20.2, 12))
            path.addLine(to: p(9.6, 19.2))
            path.addQuadCurve(to: p(8, 18.4), control: p(8.4, 19.4))
            path.closeSubpath()

        case .plus:
            path.move(to: p(12, 5)); path.addLine(to: p(12, 19))
            path.move(to: p(5, 12)); path.addLine(to: p(19, 12))

        case .check:
            path.move(to: p(5.5, 12.5)); path.addLine(to: p(10, 17)); path.addLine(to: p(18.5, 7.5))

        case .close:
            path.move(to: p(6.5, 6.5)); path.addLine(to: p(17.5, 17.5))
            path.move(to: p(17.5, 6.5)); path.addLine(to: p(6.5, 17.5))

        case .chevronRight:
            path.move(to: p(9.5, 6)); path.addLine(to: p(15.5, 12)); path.addLine(to: p(9.5, 18))
        case .chevronLeft:
            path.move(to: p(14.5, 6)); path.addLine(to: p(8.5, 12)); path.addLine(to: p(14.5, 18))
        case .chevronDown:
            path.move(to: p(6, 9.5)); path.addLine(to: p(12, 15.5)); path.addLine(to: p(18, 9.5))

        case .more:
            for x in [5.5, 12.0, 18.5] as [CGFloat] { path.addEllipse(in: r(x - 1.7, 10.3, 3.4, 3.4)) }

        case .pin:
            path.move(to: p(9, 3.75)); path.addLine(to: p(15, 3.75)); path.addLine(to: p(14.2, 9))
            path.addLine(to: p(17.5, 12.5)); path.addLine(to: p(17.5, 14)); path.addLine(to: p(6.5, 14))
            path.addLine(to: p(6.5, 12.5)); path.addLine(to: p(9.8, 9)); path.closeSubpath()
            path.move(to: p(12, 14)); path.addLine(to: p(12, 20.5))

        case .window:
            path.addRoundedRect(in: r(3.25, 4.75, 17.5, 14.5), cornerSize: CGSize(width: 3.5 * s, height: 3.5 * s), style: .continuous)
            path.move(to: p(3.25, 9)); path.addLine(to: p(20.75, 9))
            path.move(to: p(9.5, 9)); path.addLine(to: p(9.5, 19.25))

        case .sliders:
            path.move(to: p(4, 8)); path.addLine(to: p(12.5, 8))
            path.move(to: p(17.5, 8)); path.addLine(to: p(20, 8))
            path.addEllipse(in: r(12.5, 5.5, 5, 5))
            path.move(to: p(4, 16)); path.addLine(to: p(6.5, 16))
            path.move(to: p(11.5, 16)); path.addLine(to: p(20, 16))
            path.addEllipse(in: r(6.5, 13.5, 5, 5))

        case .sparkle:
            path.move(to: p(12, 2.5))
            path.addCurve(to: p(21.5, 12), control1: p(12.6, 8.2), control2: p(15.8, 11.4))
            path.addCurve(to: p(12, 21.5), control1: p(15.8, 12.6), control2: p(12.6, 15.8))
            path.addCurve(to: p(2.5, 12), control1: p(11.4, 15.8), control2: p(8.2, 12.6))
            path.addCurve(to: p(12, 2.5), control1: p(8.2, 11.4), control2: p(11.4, 8.2))
            path.closeSubpath()

        case .video:
            path.addRoundedRect(in: r(2.75, 6.5, 12.5, 11), cornerSize: CGSize(width: 3.5 * s, height: 3.5 * s), style: .continuous)
            path.move(to: p(15.25, 10.5)); path.addLine(to: p(20.5, 7.5)); path.addLine(to: p(20.5, 16.5))
            path.addLine(to: p(15.25, 13.5))

        case .clock:
            path.addEllipse(in: r(3.5, 3.5, 17, 17))
            path.move(to: p(12, 7.5)); path.addLine(to: p(12, 12)); path.addLine(to: p(15, 14))

        case .arrowUpRight:
            path.move(to: p(7.5, 16.5)); path.addLine(to: p(16.5, 7.5))
            path.move(to: p(9, 7.5)); path.addLine(to: p(16.5, 7.5)); path.addLine(to: p(16.5, 15))

        case .trash:
            path.move(to: p(4.5, 7)); path.addLine(to: p(19.5, 7))
            path.move(to: p(9.5, 7)); path.addLine(to: p(10, 4.5)); path.addLine(to: p(14, 4.5)); path.addLine(to: p(14.5, 7))
            path.move(to: p(6.5, 7)); path.addLine(to: p(7.4, 19.25)); path.addLine(to: p(16.6, 19.25)); path.addLine(to: p(17.5, 7))

        case .flag:
            path.move(to: p(6, 20.5)); path.addLine(to: p(6, 4))
            path.move(to: p(6, 4.5)); path.addLine(to: p(17.5, 4.5)); path.addLine(to: p(15, 8.75))
            path.addLine(to: p(17.5, 13)); path.addLine(to: p(6, 13))

        case .archive:
            path.addRoundedRect(in: r(3.5, 4.5, 17, 4.5), cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
            path.move(to: p(5, 9)); path.addLine(to: p(5, 18)); path.addQuadCurve(to: p(7, 19.5), control: p(5, 19.5))
            path.addLine(to: p(17, 19.5)); path.addQuadCurve(to: p(19, 18), control: p(19, 19.5)); path.addLine(to: p(19, 9))
            path.move(to: p(10, 12.5)); path.addLine(to: p(14, 12.5))

        case .history:
            path.move(to: p(4.2, 9))
            path.addArc(center: p(12, 12), radius: 8.25 * s, startAngle: .degrees(200), endAngle: .degrees(560), clockwise: false)
            path.move(to: p(3.75, 5.5)); path.addLine(to: p(4.2, 9.2)); path.addLine(to: p(7.8, 8.6))
            path.move(to: p(12, 8)); path.addLine(to: p(12, 12)); path.addLine(to: p(14.75, 13.75))

        case .shield:
            path.move(to: p(12, 3)); path.addLine(to: p(19, 5.75)); path.addLine(to: p(19, 11.5))
            path.addCurve(to: p(12, 21), control1: p(19, 15.9), control2: p(16, 19.4))
            path.addCurve(to: p(5, 11.5), control1: p(8, 19.4), control2: p(5, 15.9))
            path.addLine(to: p(5, 5.75)); path.closeSubpath()
            path.move(to: p(9, 12)); path.addLine(to: p(11.25, 14.25)); path.addLine(to: p(15.25, 9.75))

        case .warning:
            path.move(to: p(10.4, 4.6))
            path.addQuadCurve(to: p(13.6, 4.6), control: p(12, 2.4))
            path.addLine(to: p(20.6, 17.2))
            path.addQuadCurve(to: p(19, 20), control: p(21.6, 20))
            path.addLine(to: p(5, 20))
            path.addQuadCurve(to: p(3.4, 17.2), control: p(2.4, 20))
            path.closeSubpath()
            path.move(to: p(12, 9.5)); path.addLine(to: p(12, 13.5))
            path.addEllipse(in: r(11.2, 15.8, 1.6, 1.6))

        case .bell:
            path.move(to: p(6, 16.5)); path.addLine(to: p(6, 11))
            path.addCurve(to: p(18, 11), control1: p(6, 4), control2: p(18, 4))
            path.addLine(to: p(18, 16.5)); path.addLine(to: p(19.5, 17.75)); path.addLine(to: p(4.5, 17.75)); path.closeSubpath()
            path.move(to: p(10, 20.25)); path.addQuadCurve(to: p(14, 20.25), control: p(12, 21.75))

        case .people:
            path.addEllipse(in: r(5.5, 4.5, 6.5, 6.5))
            path.move(to: p(3, 19.5)); path.addCurve(to: p(14.5, 19.5), control1: p(3.5, 12.5), control2: p(14, 12.5))
            path.move(to: p(15, 5)); path.addCurve(to: p(15.5, 11), control1: p(19, 5.5), control2: p(19, 10.5))
            path.move(to: p(17.5, 13.75)); path.addCurve(to: p(21, 19.5), control1: p(20, 14.5), control2: p(21, 17))

        case .keyboard:
            path.addRoundedRect(in: r(2.75, 6, 18.5, 12), cornerSize: CGSize(width: 3 * s, height: 3 * s), style: .continuous)
            for x in [7.0, 10.33, 13.66, 17.0] as [CGFloat] { path.addEllipse(in: r(x - 0.7, 9.6, 1.4, 1.4)) }
            path.move(to: p(8, 14.5)); path.addLine(to: p(16, 14.5))

        case .accessibility:
            path.addEllipse(in: r(10.5, 3.25, 3, 3))
            path.move(to: p(5, 8.5)); path.addLine(to: p(19, 8.5))
            path.move(to: p(12, 8.5)); path.addLine(to: p(12, 13.5))
            path.move(to: p(8.5, 20.5)); path.addLine(to: p(12, 13.5)); path.addLine(to: p(15.5, 20.5))

        case .copy:
            path.addRoundedRect(in: r(8, 8, 12, 12), cornerSize: CGSize(width: 3 * s, height: 3 * s), style: .continuous)
            path.move(to: p(16, 8)); path.addLine(to: p(16, 6.5)); path.addQuadCurve(to: p(13.5, 4), control: p(16, 4))
            path.addLine(to: p(6.5, 4)); path.addQuadCurve(to: p(4, 6.5), control: p(4, 4))
            path.addLine(to: p(4, 13.5)); path.addQuadCurve(to: p(6.5, 16), control: p(4, 16)); path.addLine(to: p(8, 16))

        case .sun:
            path.addEllipse(in: r(8, 8, 8, 8))
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                let inner: CGFloat = 6.25, outer: CGFloat = 8.75
                path.move(to: p(12 + inner * CGFloat(cos(angle)), 12 + inner * CGFloat(sin(angle))))
                path.addLine(to: p(12 + outer * CGFloat(cos(angle)), 12 + outer * CGFloat(sin(angle))))
            }
        }
        return path
    }
}

struct CrenelGlyphShape: Shape {
    let glyph: CrenelGlyph

    func path(in rect: CGRect) -> Path {
        glyph.path(in: rect)
    }
}

/// Renders a Crenel glyph at a size, inheriting the foreground style. Glyphs that exist
/// in the Hud family draw as Hud icons; the rest use the same stroke language (square
/// caps, mitred joins, Hud weight), so the app has one icon set.
struct CrenelIcon: View {
    let glyph: CrenelGlyph
    var size: CGFloat = 16
    /// Kept for call-site compatibility; every icon draws at the Hud weight.
    var weight: CGFloat = 2

    init(_ glyph: CrenelGlyph, size: CGFloat = 16, weight: CGFloat = 2) {
        self.glyph = glyph
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Group {
            if let hud = glyph.hud {
                HudIcon(hud, size: size)
            } else if glyph.isFilled {
                CrenelGlyphShape(glyph: glyph).fill(style: FillStyle(eoFill: false))
                    .frame(width: size, height: size)
            } else {
                CrenelGlyphShape(glyph: glyph)
                    .stroke(style: StrokeStyle(lineWidth: 2.07 * size / 24, lineCap: .square, lineJoin: .miter))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

extension CrenelGlyph {
    /// The Hud icon drawing the same idea, when there is one.
    var hud: HudGlyph? {
        switch self {
        case .calendar, .sun: .calendar
        case .tasks: .queue
        case .mic: .mic
        case .video: .video
        case .window: .window
        case .pin: .pin
        case .history: .history
        case .record: .record
        case .stop: .stop
        case .chevronRight: .chevronRight
        case .plus: .plus
        case .close: .close
        case .sparkle: .spark
        case .arrowUpRight: .link
        case .bell: .bell
        default: nil
        }
    }
}
