import SwiftUI

/// Segment numerals (`.segd`): the one hero number of a surface. A 10×18 cell with 2-unit
/// hexagonal segments (0.55 gap), 7° italic, digit pitch 13, colon pitch 5. Every digit
/// sits on a ghost "8" at 7.5 %; leading empty cells (`cells`) are ghosts, not blanks, so
/// the layout never shifts when the value changes. Lit segments bloom in two layers:
/// a 1.5 px 60 % core and a 7 px 24 % spill.
///
/// Sizes: 13 in the ears, 24 for the open-panel hero, 34 for the recording clock
/// (also 10 in task rows, 14–20 in readouts).
///
///     HudSegmentDigits("12:48", height: 34)
///     HudSegmentDigits("8", height: 24, cells: 2, color: Hud.Ink.signal)
///     HudSegmentDigits("--:--", height: 15)
///     HudSegmentDigits(HudFormat.remaining(minutes: 157))   // "2h 37m"
struct HudSegmentDigits: View {
    let text: String
    var height: CGFloat = 13
    /// Minimum number of cells; the value is right-aligned and padded with ghost 8s.
    var cells = 0
    var color: Color = Hud.Ink.ink1
    var glows = true

    init(_ text: String, height: CGFloat = 13, cells: Int = 0, color: Color = Hud.Ink.ink1, glows: Bool = true) {
        self.text = text
        self.height = height
        self.cells = cells
        self.color = color
        self.glows = glows
    }

    var body: some View {
        let art = HudSegmentArt(text: text, cells: cells)
        Canvas { context, size in
            let scale = size.height / 18
            // translate(2.2 0) skewX(-7), then scale to the height.
            let skew = CGAffineTransform(a: 1, b: 0, c: -tan(7 * .pi / 180), d: 1, tx: 2.2, ty: 0)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            context.fill(art.ghost.applying(skew), with: .color(color.opacity(0.075)))
            context.fill(art.lit.applying(skew), with: .color(color))
        }
        .frame(width: art.width / 18 * height, height: height)
        .hudGlow(color, tight: 1.5, tightOpacity: 0.6, wide: 7, wideOpacity: 0.24, enabled: glows)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// Segment geometry in unit space (before the italic skew).
struct HudSegmentArt {
    let ghost: Path
    let lit: Path
    /// Width of the unit box (height is 18).
    let width: CGFloat

    private static let gap: CGFloat = 0.55

    private static func horizontal(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat) -> [CGPoint] {
        [CGPoint(x: x1, y: y), CGPoint(x: x1 + 1, y: y - 1), CGPoint(x: x2 - 1, y: y - 1),
         CGPoint(x: x2, y: y), CGPoint(x: x2 - 1, y: y + 1), CGPoint(x: x1 + 1, y: y + 1)]
    }

    private static func vertical(_ x: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> [CGPoint] {
        [CGPoint(x: x, y: y1), CGPoint(x: x + 1, y: y1 + 1), CGPoint(x: x + 1, y: y2 - 1),
         CGPoint(x: x, y: y2), CGPoint(x: x - 1, y: y2 - 1), CGPoint(x: x - 1, y: y1 + 1)]
    }

    /// The seven segments a…g.
    static let segments: [(name: Character, points: [CGPoint])] = [
        ("a", horizontal(1 + gap, 9 - gap, 1)),
        ("b", vertical(9, 1 + gap, 9 - gap)),
        ("c", vertical(9, 9 + gap, 17 - gap)),
        ("d", horizontal(1 + gap, 9 - gap, 17)),
        ("e", vertical(1, 9 + gap, 17 - gap)),
        ("f", vertical(1, 1 + gap, 9 - gap)),
        ("g", horizontal(1 + gap, 9 - gap, 9))
    ]

    static let map: [Character: String] = [
        "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
        "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "",
        // Unit letters for durations ("2h 37m"). "m" also lights a middle leg (see `init`).
        "h": "fgec", "m": "gec"
    ]

    /// A gap between groups ("2h 37m"): narrower than a cell and without a ghost.
    static let thinSpace: Character = "\u{2009}"

    init(text: String, cells: Int) {
        var characters = Array(text)
        if cells > characters.count {
            characters = Array(repeating: " ", count: cells - characters.count) + characters
        }
        var ghost = Path()
        var lit = Path()
        var x: CGFloat = 0
        for character in characters {
            if character == ":" || character == "." {
                for y in character == ":" ? [5.5, 12.5] : [16.5] {
                    lit.addRoundedRect(in: CGRect(x: x + 1, y: y - 1, width: 2, height: 2), cornerSize: CGSize(width: 0.4, height: 0.4))
                }
                x += 5
                continue
            }
            if character == Self.thinSpace {
                x += 5
                continue
            }
            let on = Self.map[character] ?? ""
            if character == "m" {
                var leg = Path()
                leg.addLines(Self.vertical(5, 9 + Self.gap, 17 - Self.gap).map { CGPoint(x: $0.x + x, y: $0.y) })
                leg.closeSubpath()
                lit.addPath(leg)
            }
            for segment in Self.segments {
                var polygon = Path()
                polygon.addLines(segment.points.map { CGPoint(x: $0.x + x, y: $0.y) })
                polygon.closeSubpath()
                if on.contains(segment.name) { lit.addPath(polygon) } else { ghost.addPath(polygon) }
            }
            x += 13
        }
        self.ghost = ghost
        self.lit = lit
        width = max(0, x - 3 + 2.6)
    }
}

/// A segment number with its unit ("33 min", "18 left", "42 %"), baseline-aligned.
///
///     HudReadout("33", unit: "min", cells: 2)
///     HudReadout("8", unit: "min", cells: 2, color: Hud.Ink.signal)
struct HudReadout: View {
    let value: String
    let unit: Text
    var height: CGFloat = 13
    var cells = 0
    var color: Color = Hud.Ink.ink1

    init(_ value: String, unit: LocalizedStringKey, height: CGFloat = 13, cells: Int = 0, color: Color = Hud.Ink.ink1) {
        self.value = value
        self.unit = Text(unit)
        self.height = height
        self.cells = cells
        self.color = color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            HudSegmentDigits(value, height: height, cells: cells, color: color)
            // Tinted readouts print their unit at 70 % of the tint; neutral ones in ink-3.
            unit.hud(.unit, color == Hud.Ink.ink1 || color == Hud.Ink.ink2 ? Hud.Ink.ink3 : color.opacity(0.7))
                .fixedSize()
        }
    }
}
