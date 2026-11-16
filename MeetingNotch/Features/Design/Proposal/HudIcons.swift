import SwiftUI

/// One icon family: drawn on a 16-unit grid, 1.5-unit stroke, square caps, mitred
/// joins — technical, quiet, same weight everywhere. Icons are never placed inside a
/// circle or tile; they sit directly on the surface in the text colour of their row.
enum HudGlyph: String, CaseIterable, Sendable {
    case calendar, queue, mic, video, window, pin, history, record, stop
    case chevronRight, arrowRight, plus, close, spark, link, bell

    /// Strokes in 16×16 unit space.
    fileprivate func stroke(_ p: inout Path) {
        switch self {
        case .calendar:
            p.addRect(CGRect(x: 2, y: 3.5, width: 12, height: 10.5))
            p.move(to: CGPoint(x: 2, y: 7)); p.addLine(to: CGPoint(x: 14, y: 7))
            p.move(to: CGPoint(x: 5.5, y: 1.5)); p.addLine(to: CGPoint(x: 5.5, y: 4.5))
            p.move(to: CGPoint(x: 10.5, y: 1.5)); p.addLine(to: CGPoint(x: 10.5, y: 4.5))
        case .queue:
            // A short queue of work: one marker, three lines of decreasing length.
            p.addRect(CGRect(x: 2, y: 3, width: 3, height: 3))
            p.move(to: CGPoint(x: 8, y: 4.5)); p.addLine(to: CGPoint(x: 14, y: 4.5))
            p.move(to: CGPoint(x: 2, y: 9)); p.addLine(to: CGPoint(x: 12, y: 9))
            p.move(to: CGPoint(x: 2, y: 13)); p.addLine(to: CGPoint(x: 9, y: 13))
        case .mic:
            p.addRoundedRect(in: CGRect(x: 5.5, y: 1.5, width: 5, height: 8), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: CGPoint(x: 3, y: 7.5))
            p.addCurve(to: CGPoint(x: 13, y: 7.5), control1: CGPoint(x: 3, y: 13.5), control2: CGPoint(x: 13, y: 13.5))
            p.move(to: CGPoint(x: 8, y: 12)); p.addLine(to: CGPoint(x: 8, y: 14.5))
        case .video:
            p.addRect(CGRect(x: 1.5, y: 4, width: 9, height: 8))
            p.move(to: CGPoint(x: 10.5, y: 7))
            p.addLine(to: CGPoint(x: 14.5, y: 5)); p.addLine(to: CGPoint(x: 14.5, y: 11))
            p.addLine(to: CGPoint(x: 10.5, y: 9))
        case .window:
            p.addRect(CGRect(x: 2, y: 2.5, width: 12, height: 11))
            p.move(to: CGPoint(x: 2, y: 6)); p.addLine(to: CGPoint(x: 14, y: 6))
        case .pin:
            p.move(to: CGPoint(x: 5.5, y: 2)); p.addLine(to: CGPoint(x: 10.5, y: 2))
            p.move(to: CGPoint(x: 6.5, y: 2)); p.addLine(to: CGPoint(x: 6.5, y: 6.5))
            p.addLine(to: CGPoint(x: 4, y: 9.5)); p.addLine(to: CGPoint(x: 12, y: 9.5))
            p.addLine(to: CGPoint(x: 9.5, y: 6.5)); p.addLine(to: CGPoint(x: 9.5, y: 2))
            p.move(to: CGPoint(x: 8, y: 9.5)); p.addLine(to: CGPoint(x: 8, y: 14.5))
        case .history:
            p.addArc(center: CGPoint(x: 8, y: 8), radius: 6, startAngle: .degrees(200), endAngle: .degrees(160), clockwise: false)
            p.move(to: CGPoint(x: 1.6, y: 4.5)); p.addLine(to: CGPoint(x: 2.3, y: 6)); p.addLine(to: CGPoint(x: 4, y: 5.6))
            p.move(to: CGPoint(x: 8, y: 5)); p.addLine(to: CGPoint(x: 8, y: 8.5)); p.addLine(to: CGPoint(x: 10.5, y: 10))
        case .record, .stop:
            break
        case .chevronRight:
            p.move(to: CGPoint(x: 6, y: 3.5)); p.addLine(to: CGPoint(x: 10.5, y: 8)); p.addLine(to: CGPoint(x: 6, y: 12.5))
        case .arrowRight:
            p.move(to: CGPoint(x: 2.5, y: 8)); p.addLine(to: CGPoint(x: 13, y: 8))
            p.move(to: CGPoint(x: 9, y: 4)); p.addLine(to: CGPoint(x: 13, y: 8)); p.addLine(to: CGPoint(x: 9, y: 12))
        case .plus:
            p.move(to: CGPoint(x: 8, y: 2.5)); p.addLine(to: CGPoint(x: 8, y: 13.5))
            p.move(to: CGPoint(x: 2.5, y: 8)); p.addLine(to: CGPoint(x: 13.5, y: 8))
        case .close:
            p.move(to: CGPoint(x: 3.5, y: 3.5)); p.addLine(to: CGPoint(x: 12.5, y: 12.5))
            p.move(to: CGPoint(x: 12.5, y: 3.5)); p.addLine(to: CGPoint(x: 3.5, y: 12.5))
        case .spark:
            p.move(to: CGPoint(x: 8, y: 1.5)); p.addLine(to: CGPoint(x: 9.6, y: 6.4)); p.addLine(to: CGPoint(x: 14.5, y: 8))
            p.addLine(to: CGPoint(x: 9.6, y: 9.6)); p.addLine(to: CGPoint(x: 8, y: 14.5)); p.addLine(to: CGPoint(x: 6.4, y: 9.6))
            p.addLine(to: CGPoint(x: 1.5, y: 8)); p.addLine(to: CGPoint(x: 6.4, y: 6.4)); p.closeSubpath()
        case .link:
            p.move(to: CGPoint(x: 9, y: 2.5)); p.addLine(to: CGPoint(x: 13.5, y: 2.5)); p.addLine(to: CGPoint(x: 13.5, y: 7))
            p.move(to: CGPoint(x: 13.5, y: 2.5)); p.addLine(to: CGPoint(x: 7.5, y: 8.5))
            p.move(to: CGPoint(x: 11, y: 10)); p.addLine(to: CGPoint(x: 11, y: 13.5)); p.addLine(to: CGPoint(x: 2.5, y: 13.5))
            p.addLine(to: CGPoint(x: 2.5, y: 5)); p.addLine(to: CGPoint(x: 6, y: 5))
        case .bell:
            p.move(to: CGPoint(x: 2.5, y: 12)); p.addLine(to: CGPoint(x: 13.5, y: 12))
            p.move(to: CGPoint(x: 4, y: 12)); p.addLine(to: CGPoint(x: 4, y: 7))
            p.addCurve(to: CGPoint(x: 12, y: 7), control1: CGPoint(x: 4, y: 1.5), control2: CGPoint(x: 12, y: 1.5))
            p.addLine(to: CGPoint(x: 12, y: 12))
            p.move(to: CGPoint(x: 6.5, y: 14.5)); p.addLine(to: CGPoint(x: 9.5, y: 14.5))
        }
    }

    /// Solid parts (record dot, stop square).
    fileprivate func fill(_ p: inout Path) {
        switch self {
        case .record: p.addEllipse(in: CGRect(x: 4, y: 4, width: 8, height: 8))
        case .stop: p.addRect(CGRect(x: 4.5, y: 4.5, width: 7, height: 7))
        default: break
        }
    }
}

struct HudIcon: View {
    let glyph: HudGlyph
    var size: CGFloat = Hud.Size.icon

    init(_ glyph: HudGlyph, size: CGFloat = Hud.Size.icon) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 16
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            var strokes = Path()
            glyph.stroke(&strokes)
            var fills = Path()
            glyph.fill(&fills)
            let shading = GraphicsContext.Shading.foreground
            context.stroke(strokes.applying(transform), with: shading,
                           style: StrokeStyle(lineWidth: 1.5 * scale * 0.92, lineCap: .square, lineJoin: .miter))
            context.fill(fills.applying(transform), with: shading)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
