import SwiftUI

/// Crenel's icon set: bold pixel glyphs drawn by hand on a 9×9 grid. Every glyph is a
/// solid shape of square pixels, so it stays legible at notch sizes and shares one voice.
/// Render at multiples of 4.5 pt (9, 13.5, 18) for crisp pixels.
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
    case repeatGlyph
    case note

    static let gridSize = 9

    /// Rows of the bitmap, top to bottom; `#` is a lit pixel.
    var bitmap: [String] {
        switch self {
        case .logo: [
            ".........",
            "##.###.##",
            "##.###.##",
            "#########",
            "#########",
            "####.####",
            "###...###",
            "###...###",
            "........."]
        case .calendar: [
            ".#.....#.",
            "#########",
            "#########",
            "#.......#",
            "#.##.##.#",
            "#.......#",
            "#.##....#",
            "#.......#",
            "#########"]
        case .tasks: [
            "#########",
            "#.......#",
            "#......##",
            "#.....##.",
            "#.#..##.#",
            "#.####..#",
            "#..##...#",
            "#.......#",
            "#########"]
        case .waveform: [
            "....#....",
            "....#....",
            "..#.#.#..",
            "..#.#.#..",
            "#.#.#.#.#",
            "..#.#.#..",
            "..#.#.#..",
            "....#....",
            "....#...."]
        case .mic: [
            "...###...",
            "..#####..",
            "..#####..",
            "#.#####.#",
            "#.#####.#",
            "#..###..#",
            ".#.....#.",
            "..#####..",
            "....#...."]
        case .micOff: [
            "#..###...",
            ".#.####..",
            "..#.###..",
            "#.##.##.#",
            "#.###.#.#",
            "#..###..#",
            ".#....#..",
            "..######.",
            "....#...#"]
        case .speaker: [
            "...#.....",
            "..##..#..",
            "####...#.",
            "####.#.#.",
            "####.#.#.",
            "####...#.",
            "..##..#..",
            "...#.....",
            "........."]
        case .record: [
            ".........",
            "...###...",
            "..#####..",
            ".#######.",
            ".#######.",
            ".#######.",
            "..#####..",
            "...###...",
            "........."]
        case .stop: [
            ".........",
            ".........",
            "..#####..",
            "..#####..",
            "..#####..",
            "..#####..",
            "..#####..",
            ".........",
            "........."]
        case .pause: [
            ".........",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            "........."]
        case .play: [
            ".........",
            "..#......",
            "..###....",
            "..####...",
            "..######.",
            "..####...",
            "..###....",
            "..#......",
            "........."]
        case .plus: [
            ".........",
            "...###...",
            "...###...",
            "#########",
            "#########",
            "#########",
            "...###...",
            "...###...",
            "........."]
        case .check: [
            ".........",
            ".......##",
            "......###",
            ".....###.",
            "##..###..",
            "######...",
            ".####....",
            "..##.....",
            "........."]
        case .close: [
            ".........",
            ".##...##.",
            "..##.##..",
            "...###...",
            "....#....",
            "...###...",
            "..##.##..",
            ".##...##.",
            "........."]
        case .chevronRight: [
            ".........",
            ".##......",
            "..##.....",
            "...##....",
            "....##...",
            "...##....",
            "..##.....",
            ".##......",
            "........."]
        case .chevronLeft: [
            ".........",
            "......##.",
            ".....##..",
            "....##...",
            "...##....",
            "....##...",
            ".....##..",
            "......##.",
            "........."]
        case .chevronDown: [
            ".........",
            ".........",
            "#.......#",
            "##.....##",
            ".##...##.",
            "..##.##..",
            "...###...",
            "....#....",
            "........."]
        case .more: [
            ".........",
            ".........",
            ".........",
            "##..#..##",
            "##.###.##",
            "....#....",
            ".........",
            ".........",
            "........."]
        case .pin: [
            "..#####..",
            "...###...",
            "...###...",
            "..#####..",
            ".#######.",
            "....#....",
            "....#....",
            "....#....",
            "........."]
        case .window: [
            "#########",
            "#.#.#...#",
            "#########",
            "#..#....#",
            "#..#....#",
            "#..#....#",
            "#..#....#",
            "#########",
            "........."]
        case .sliders: [
            ".........",
            "..##.....",
            "#########",
            "..##.....",
            ".........",
            ".....##..",
            "#########",
            ".....##..",
            "........."]
        case .sparkle: [
            "....#....",
            "....#....",
            "...###...",
            "..#####..",
            "#########",
            "..#####..",
            "...###...",
            "....#....",
            "....#...."]
        case .video: [
            ".........",
            ".........",
            "######..#",
            "######.##",
            "#########",
            "######.##",
            "######..#",
            ".........",
            "........."]
        case .clock: [
            "..#####..",
            ".#.....#.",
            "#...#...#",
            "#...#...#",
            "#...###.#",
            "#.......#",
            "#.......#",
            ".#.....#.",
            "..#####.."]
        case .arrowUpRight: [
            ".........",
            "..######.",
            "......##.",
            ".....###.",
            "....##.#.",
            "...##..#.",
            "..##.....",
            ".##......",
            "........."]
        case .trash: [
            "...###...",
            "#########",
            ".........",
            ".#######.",
            ".#.#.#.#.",
            ".#.#.#.#.",
            ".#.#.#.#.",
            ".#######.",
            "........."]
        case .flag: [
            "##.......",
            "#######..",
            "########.",
            "#######..",
            "##.......",
            "##.......",
            "##.......",
            "##.......",
            "........."]
        case .archive: [
            "#########",
            "#########",
            ".........",
            ".#######.",
            ".##...##.",
            ".#######.",
            ".#######.",
            ".#######.",
            "........."]
        case .history: [
            "...####..",
            "..#....#.",
            ".#..#...#",
            "###.#...#",
            ".#..##..#",
            "........#",
            "..#....#.",
            "...####..",
            "........."]
        case .shield: [
            "#########",
            "#.......#",
            "#......##",
            "#.....#.#",
            "#.#..#..#",
            "#..##...#",
            ".#.....#.",
            "..#...#..",
            "...###..."]
        case .warning: [
            "....#....",
            "...###...",
            "...#.#...",
            "..##.##..",
            "..##.##..",
            ".#######.",
            ".###.###.",
            "#########",
            "........."]
        case .bell: [
            "....#....",
            "..#####..",
            ".#######.",
            ".#######.",
            ".#######.",
            ".#######.",
            "#########",
            ".........",
            "...###..."]
        case .people: [
            ".##...##.",
            ".##...##.",
            ".........",
            "####.####",
            "####.####",
            "####.####",
            ".........",
            ".........",
            "........."]
        case .keyboard: [
            ".........",
            "#########",
            "#.#.#.#.#",
            "#########",
            "##.#.#.##",
            "#########",
            "#..###..#",
            "#########",
            "........."]
        case .accessibility: [
            "...###...",
            "...###...",
            ".........",
            "#########",
            "...###...",
            "...###...",
            "..##.##..",
            "..#...#..",
            ".##...##."]
        case .copy: [
            "#####....",
            "#...#....",
            "#.#######",
            "#.#.....#",
            "###.....#",
            "..#.....#",
            "..#.....#",
            "..#######",
            "........."]
        case .sun: [
            "....#....",
            ".#.....#.",
            "...###...",
            "..#####..",
            "#.#####.#",
            "..#####..",
            "...###...",
            ".#.....#.",
            "....#...."]
        case .repeatGlyph: [
            ".........",
            ".######..",
            ".#....##.",
            ".#...####",
            ".........",
            "####...#.",
            ".##....#.",
            "..######.",
            "........."]
        case .note: [
            "#######..",
            "#.....##.",
            "#.###..##",
            "#.......#",
            "#.#####.#",
            "#.......#",
            "#.####..#",
            "#.......#",
            "#########"]
        }
    }

    /// Lit pixels as (column, row).
    var pixels: [(Int, Int)] {
        var result: [(Int, Int)] = []
        for (row, line) in bitmap.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                result.append((column, row))
            }
        }
        return result
    }

    func path(in rect: CGRect) -> Path {
        PixelBitmap.path(pixels: pixels, grid: Self.gridSize, in: rect)
    }
}

enum PixelBitmap {
    /// Square pixels laid out on a grid, centred in `rect`. Pixels slightly overlap so no
    /// hairline seams appear between neighbours.
    static func path(pixels: [(Int, Int)], grid: Int, in rect: CGRect) -> Path {
        let cell = min(rect.width, rect.height) / CGFloat(grid)
        let origin = CGPoint(x: rect.midX - cell * CGFloat(grid) / 2, y: rect.midY - cell * CGFloat(grid) / 2)
        var path = Path()
        for (column, row) in pixels {
            path.addRect(CGRect(
                x: origin.x + CGFloat(column) * cell,
                y: origin.y + CGFloat(row) * cell,
                width: cell + 0.01,
                height: cell + 0.01
            ))
        }
        return path
    }

    static func pixels(_ rows: [String]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                result.append((column, row))
            }
        }
        return result
    }
}

struct CrenelGlyphShape: Shape {
    let glyph: CrenelGlyph

    func path(in rect: CGRect) -> Path {
        glyph.path(in: rect)
    }
}

/// Renders a Crenel pixel glyph at a size, inheriting the foreground style.
struct CrenelIcon: View {
    let glyph: CrenelGlyph
    var size: CGFloat

    /// `weight` is accepted for call-site compatibility; pixel glyphs have one weight.
    init(_ glyph: CrenelGlyph, size: CGFloat = 13.5, weight: CGFloat = 0) {
        self.glyph = glyph
        self.size = Self.snapped(size)
    }

    var body: some View {
        CrenelGlyphShape(glyph: glyph)
            .fill()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Snaps to a multiple of 4.5 pt so pixels land on whole points on Retina screens.
    static func snapped(_ size: CGFloat) -> CGFloat {
        max(9, (size / 4.5).rounded() * 4.5)
    }
}
