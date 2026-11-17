import SwiftUI

/// A small SVG path-data parser, so the icon and shape geometry can be ported from the
/// prototype's sprite verbatim. Supports M L H V C S Q T A Z in absolute and relative
/// form, with implicit command repetition.
enum HudSVGPath {
    static func path(_ d: String) -> Path {
        var path = Path()
        var scanner = Scanner(d)
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = " "

        while let next = scanner.nextCommandOrNumber() {
            if case let .command(c) = next {
                command = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    lastCommand = c
                    lastControl = nil
                    continue
                }
            } else {
                scanner.unread()
            }
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch command.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                // Further pairs after a moveto are implicit linetos.
                command = relative ? "l" : "L"
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastControl = c2
                current = p
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = "CS".contains(lastCommand.uppercased()) ? reflect(lastControl, around: current) : current
                path.addCurve(to: p, control1: c1, control2: c2)
                lastControl = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                lastControl = c
                current = p
            case "T":
                guard let p = point() else { return path }
                let c = "QT".contains(lastCommand.uppercased()) ? reflect(lastControl, around: current) : current
                path.addQuadCurve(to: p, control: c)
                lastControl = c
                current = p
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = point() else { return path }
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry, rotation: rotation, largeArc: large, sweep: sweep)
                current = p
            default:
                return path
            }
            if !"CSQT".contains(command.uppercased()) { lastControl = nil }
            lastCommand = command
        }
        return path
    }

    /// `<rect x y width height>` as a path.
    static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
        Path(CGRect(x: x, y: y, width: width, height: height))
    }

    private static func reflect(_ control: CGPoint?, around point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// Endpoint-parameterised elliptical arc → cubic Béziers (SVG 1.1, F.6.5).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat,
                               rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = sqrt(max(0, numerator / denominator))
        if largeArc == sweep { factor = -factor }
        let cxp = factor * rx * y1 / ry
        let cyp = -factor * ry * x1 / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        var a = theta
        for _ in 0..<segments {
            let cosA = cos(a), sinA = sin(a)
            let cosB = cos(a + step), sinB = sin(a + step)
            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cosPhi * rx * x - sinPhi * ry * y + cx, y: sinPhi * rx * x + cosPhi * ry * y + cy)
            }
            path.addCurve(
                to: map(cosB, sinB),
                control1: map(cosA - t * sinA, sinA + t * cosA),
                control2: map(cosB + t * sinB, sinB - t * cosB)
            )
            a += step
        }
    }

    private enum Token {
        case command(Character)
        case number
    }

    private struct Scanner {
        private let chars: [Character]
        private var index = 0
        private var mark = 0

        init(_ string: String) {
            chars = Array(string)
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline || chars[index] == "\t" {
                index += 1
            }
        }

        /// Peeks the next token: a command letter (consumed) or a number (not consumed
        /// until `number()`).
        mutating func nextCommandOrNumber() -> Token? {
            skipSeparators()
            guard index < chars.count else { return nil }
            mark = index
            let c = chars[index]
            if c.isLetter, c != "e", c != "E" {
                index += 1
                return .command(c)
            }
            return .number
        }

        mutating func unread() {
            index = mark
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            guard index < chars.count else { return nil }
            var text = ""
            if chars[index] == "-" || chars[index] == "+" {
                text.append(chars[index])
                index += 1
            }
            var seenDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    text.append(c)
                } else if c == ".", !seenDot {
                    seenDot = true
                    text.append(c)
                } else if c == "e" || c == "E", index + 1 < chars.count,
                          chars[index + 1].isNumber || chars[index + 1] == "-" {
                    text.append(c)
                    index += 1
                    text.append(chars[index])
                } else {
                    break
                }
                index += 1
            }
            guard let value = Double(text) else { return nil }
            return CGFloat(value)
        }

        /// Arc flags are single digits and may be packed without separators.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < chars.count, chars[index] == "0" || chars[index] == "1" else { return nil }
            defer { index += 1 }
            return chars[index] == "1"
        }
    }
}
