import SwiftUI

// Meters made of cells: VU, ladder, chart recorder, LED stack, dot matrix, capsules,
// capacity scale, stations, fuse, scanner. Scales (ruler, ramp, tuner, waveform) are in
// `HudScales.swift`.

// MARK: - Fuse

/// The fuse: a 2 pt lit line along the closed notch's bottom edge, between its corner
/// radii. Its length is what is left — minutes/60 under an hour (white), minutes/10 at
/// 10 minutes and under (amber), the 12 s auto-stop countdown (red). It shortens
/// linearly.
///
///     notchShape.overlay(alignment: .bottom) { HudFuse(fraction: 0.55) }
///     HudFuse(fraction: 0.8, color: Hud.Ink.signal)
struct HudFuse: View {
    /// 0…1 of the straight part of the bottom edge.
    var fraction: Double
    var color: Color = Hud.Ink.ink1
    /// The notch's bottom corner radius; the fuse stays between the corners.
    var cornerInset: CGFloat = Hud.Notch.bottomRadius.compact

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - 2 * cornerInset) * min(1, max(0, fraction))
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: width, height: 2)
                .shadow(color: color, radius: 1)
                .shadow(color: color, radius: 4)
                .frame(maxWidth: .infinity)
                .opacity(fraction > 0 ? 1 : 0)
        }
        .frame(height: 2)
        .animation(.linear(duration: 1), value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - VU meter

/// VU meter (`.vu`): 24–30 cells; the last 14 % is the red zone. The peak cell hangs for
/// 0.7 s and then falls (peak hold). A closed source shows every cell as a ghost.
///
///     HudVUMeter(level: micLevel)                 // 30 cells, fills the width
///     HudVUMeter(level: 0, isOff: true)           // mic off
///     HudVUMeter(level: level, cells: 24, ignite: true)
struct HudVUMeter: View {
    /// 0…1.
    var level: Double
    var cells = 30
    var isOff = false
    /// Fixed peak (0…1) instead of the built-in peak hold — for previews and tests.
    var peak: Double?
    /// Ignition: start full and fall to the level when the panel opens.
    var ignite = false

    @State private var heldPeak = 0
    @State private var heldAt = Date.distantPast
    @State private var boost: Double
    @State private var litNow = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(level: Double, cells: Int = 30, isOff: Bool = false, peak: Double? = nil, ignite: Bool = false) {
        self.level = level
        self.cells = cells
        self.isOff = isOff
        self.peak = peak
        self.ignite = ignite
        _boost = State(initialValue: ignite ? 1 : 0)
    }

    private var lit: Int {
        isOff ? 0 : Int((min(1, max(0, max(level, reduceMotion ? 0 : boost))) * Double(cells)).rounded())
    }

    var body: some View {
        let lit = lit
        let peakCell = isOff ? 0 : (peak.map { Int(($0 * Double(cells)).rounded()) } ?? heldPeak)
        Canvas { context, size in
            let gap: CGFloat = 2
            let width = (size.width - gap * CGFloat(cells - 1)) / CGFloat(cells)
            let redFrom = cells - Int((Double(cells) * 0.14).rounded())
            func cell(_ index: Int) -> Path {
                Path(roundedRect: CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height), cornerRadius: 1.5)
            }
            var white = Path(), red = Path()
            for index in 0..<cells {
                let isRed = index >= redFrom
                if index < lit {
                    if isRed { red.addPath(cell(index)) } else { white.addPath(cell(index)) }
                } else if index != peakCell - 1 {
                    let ghost: Color = isOff ? Color(white: 1, opacity: 0.05)
                        : (isRed ? Hud.Ink.live.opacity(0.12) : Color(white: 1, opacity: 0.07))
                    context.fill(cell(index), with: .color(ghost))
                }
            }
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Hud.Ink.ink1.opacity(0.3), radius: 2))
                layer.fill(white, with: .color(Hud.Ink.ink1))
            }
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Hud.Ink.live.opacity(0.6), radius: 3))
                layer.fill(red, with: .color(Hud.Ink.live))
            }
            if peakCell - 1 >= lit, peakCell >= 1 {
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: Hud.Ink.ink1.opacity(0.7), radius: 3))
                    layer.fill(cell(peakCell - 1), with: .color(Hud.Ink.ink1))
                }
            }
        }
        .frame(height: 7)
        .frame(maxWidth: .infinity)
        .onChange(of: lit, initial: true) { _, new in
            litNow = new
            if new >= heldPeak {
                heldPeak = new
                heldAt = Date()
            }
        }
        .task {
            // The brightest cell lingers, then falls a cell at a time.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(110))
                if boost > 0 { boost = boost > 0.08 ? boost * 0.72 : 0 }
                if heldPeak > litNow, Date().timeIntervalSince(heldAt) > Hud.Motion.peakHold {
                    heldPeak = max(litNow, heldPeak - 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ladder

/// Ladder (`.ladder`): the ear's level meter — 6 columns × 4 cells (3×2 pt, 2 pt apart,
/// 14 pt tall).
///
///     HudLadder(level: micLevel)                    // shaped across the 6 columns
///     HudLadder(levels: [0.5, 0.8, 1, 0.9, 0.7, 0.45])
struct HudLadder: View {
    /// One 0…1 level per column.
    let levels: [Double]
    var tint: Color = Hud.Ink.ink1

    /// The prototype's column shape.
    static let shape: [Double] = [0.5, 0.8, 1, 0.9, 0.7, 0.45]

    init(levels: [Double], tint: Color = Hud.Ink.ink1) {
        self.levels = levels
        self.tint = tint
    }

    /// One level spread over the columns; `quiet` holds every column at its lowest cell.
    init(level: Double, columns: Int = 6, quiet: Bool = false, tint: Color = Hud.Ink.ink1) {
        levels = (0..<columns).map { quiet ? 0.15 : Self.shape[$0 % Self.shape.count] * min(1, max(0, level)) }
        self.tint = tint
    }

    var body: some View {
        Canvas { context, _ in
            var ghost = Path(), lit = Path()
            for (column, level) in levels.enumerated() {
                let on = Int((min(1, max(0, level)) * 4).rounded())
                for row in 0..<4 {
                    let rect = CGRect(x: CGFloat(column) * 5, y: CGFloat(3 - row) * 4, width: 3, height: 2)
                    if row < on { lit.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
                    else { ghost.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
                }
            }
            context.fill(ghost, with: .color(Color(white: 1, opacity: 0.1)))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint.opacity(0.5), radius: 2))
                layer.fill(lit, with: .color(tint))
            }
        }
        .frame(width: CGFloat(levels.count) * 5 - 2, height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Chart recorder

/// Chart recorder (`.chart`): the last two minutes of sound as thin bars flowing left.
/// The newest bar is white; the left edge fades out. 36 pt tall; bars are 2 pt wide,
/// 2 pt apart, and as many of the most recent samples as fit are shown.
///
///     HudChartRecorder(samples: recentLevels)     // append ~4–5 samples a second
struct HudChartRecorder: View {
    /// 0…1 per bar, oldest first.
    let samples: [Double]
    var height: CGFloat = 36

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 4
            let visible = min(samples.count, Int(size.width / pitch))
            guard visible > 0 else { return }
            let recent = samples.suffix(visible)
            var bars = Path()
            var last = Path()
            for (offset, sample) in recent.enumerated() {
                let barHeight = max(1, min(size.height, CGFloat(sample) * 32))
                let x = size.width - CGFloat(visible - offset) * pitch + 2
                let rect = CGRect(x: x, y: (size.height - barHeight) / 2, width: 2, height: barHeight)
                if offset == visible - 1 { last.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
                else { bars.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
            }
            context.fill(bars, with: .color(Hud.Ink.ink3))
            context.fill(last, with: .color(Hud.Ink.ink1))
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18)],
                             startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}

// MARK: - Scanner

/// Scanner (`.scanner`): for work of unknown length, a band of light sweeps back and
/// forth over the text or field (1.6 s each way). When the length is known, show the
/// number instead.
struct HudScanner: View {
    /// A fixed 0…1 position instead of the sweep — for previews and tests.
    var fixedPhase: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let band = proxy.size.width * 0.22
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let period = Hud.Motion.scanPeriod
                let raw = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period * 2) / period
                let phase = raw > 1 ? 2 - raw : raw
                // cubic-bezier(.45,0,.55,1) ≈ smoothstep.
                let eased = fixedPhase ?? (reduceMotion ? 0.5 : phase * phase * (3 - 2 * phase))
                LinearGradient(colors: [.clear, Hud.Ink.ink1.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: band * (-1.2 + 6.4 * eased))
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Sweeps the scanner over this view while `active`, clipped to `radius`.
    func hudScanner(_ active: Bool = true, radius: CGFloat = Hud.Radius.row, fixedPhase: Double? = nil) -> some View {
        overlay {
            if active {
                HudScanner(fixedPhase: fixedPhase).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
    }
}

// MARK: - LED stack

/// LED stack (`.stack`): a bar graph made of cells — the week meter. 8 cells of 18×3 on
/// the desktop, 6 cells of 10×2 in the notch (`small`). Today is white and glows, past
/// days are ink-3, future days are all ghosts (lit: 0).
///
///     HudLEDStack(lit: 5, tone: .past)
///     HudLEDStack(lit: 6, cells: 6, small: true)
struct HudLEDStack: View {
    enum Tone: Sendable { case today, past }

    /// Lit cells, counted from the bottom.
    var lit: Int
    var cells = 8
    var tone: Tone = .today
    var small = false

    var body: some View {
        let size = small ? CGSize(width: 10, height: 2) : CGSize(width: 18, height: 3)
        VStack(spacing: small ? 2 : 3) {
            ForEach(0..<cells, id: \.self) { index in
                let on = index >= cells - lit
                RoundedRectangle(cornerRadius: 1)
                    .fill(on ? (tone == .today ? Hud.Ink.ink1 : Hud.Ink.ink3) : Color(white: 1, opacity: 0.07))
                    .shadow(color: on && tone == .today ? Hud.Ink.ink1.opacity(0.45) : .clear, radius: 2.5)
                    .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Dot matrix

/// Dot matrix (`.dots`): 3 rows of 4 pt lamps, 3 pt apart, filled column by column up
/// to the value; a small triangle under the field marks "your usual". Desktop Dictation
/// tile only.
///
///     HudDotMatrix(value: 0.64, count: 78, mark: 0.46)
struct HudDotMatrix: View {
    /// 0…1.
    var value: Double
    var count = 72
    /// 0…1 position of the "usual" marker.
    var mark: Double?

    var body: some View {
        let columns = Int((Double(count) / 3).rounded(.up))
        let width = CGFloat(columns) * 7 - 3
        Canvas { context, size in
            let lit = Int((min(1, max(0, value)) * Double(count)).rounded())
            var ghost = Path(), on = Path()
            for index in 0..<count {
                let rect = CGRect(x: CGFloat(index / 3) * 7, y: CGFloat(index % 3) * 7, width: 4, height: 4)
                if index < lit { on.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
                else { ghost.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
            }
            context.fill(ghost, with: .color(Color(white: 1, opacity: 0.08)))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Hud.Ink.ink1.opacity(0.5), radius: 2))
                layer.fill(on, with: .color(Hud.Ink.ink1))
            }
            if let mark {
                let x = size.width * mark
                var triangle = Path()
                triangle.move(to: CGPoint(x: x, y: 21))
                triangle.addLine(to: CGPoint(x: x + 3, y: 25))
                triangle.addLine(to: CGPoint(x: x - 3, y: 25))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(Hud.Ink.ink3))
            }
        }
        .frame(width: width, height: 25)
        .frame(height: 18, alignment: .top)
        .accessibilityHidden(true)
    }
}

// MARK: - Capsules

/// Capsules (`.caps`): whole things — 12×6; done is white, under way is half amber,
/// queued is a ghost. Desktop Tasks tile only.
///
///     HudCapsules(done: 1, underWay: 1, total: 5)
struct HudCapsules: View {
    var done: Int
    var underWay: Int = 0
    var total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(0, total), id: \.self) { index in
                if index < done {
                    Capsule().fill(Hud.Ink.ink1).shadow(color: Hud.Ink.ink1.opacity(0.45), radius: 2.5)
                        .frame(width: 12, height: 6)
                } else if index < done + underWay {
                    Capsule()
                        .fill(LinearGradient(stops: [.init(color: Hud.Ink.signal, location: 0.5), .init(color: Hud.Ink.signal.opacity(0.14), location: 0.5)],
                                             startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Hud.Ink.signal.opacity(0.35), radius: 2.5)
                        .frame(width: 12, height: 6)
                } else {
                    Capsule().fill(Color(white: 1, opacity: 0.08)).frame(width: 12, height: 6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Capacity scale

/// Capacity scale (`.cap`): an end-labelled scale (−60 … 0 dB) with its glyph printed in
/// the middle, the cells, and a white / amber / red zone strip under them. Settings ›
/// Recording › Level only.
///
///     HudCapacityScale(level: inputLevel).frame(width: 232)
struct HudCapacityScale: View {
    var level: Double
    var cells = 24
    var minLabel = "−60"
    var maxLabel = "0 dB"
    var glyph: HudGlyph = .mic
    var peak: Double?

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(verbatim: minLabel).hud(.micro)
                Spacer(minLength: 0)
                HudIcon(glyph, size: Hud.Size.smallIcon).foregroundStyle(Hud.Ink.ink3)
                Spacer(minLength: 0)
                Text(verbatim: maxLabel).hud(.micro)
            }
            HudVUMeter(level: level, cells: cells, peak: peak)
            GeometryReader { proxy in
                // flex 17 : 4 : 3 with 2 pt gaps.
                let unit = (proxy.size.width - 4) / 24
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(Hud.Ink.ink4).frame(width: unit * 17)
                    RoundedRectangle(cornerRadius: 1).fill(Hud.Ink.signal.opacity(0.7)).frame(width: unit * 4)
                    RoundedRectangle(cornerRadius: 1).fill(Hud.Ink.live.opacity(0.8)).frame(width: unit * 3)
                }
            }
            .frame(height: 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Stations

/// The processing rail: four stations on one track — Saved, Uploaded, Transcribing,
/// Notes. Passed stations are ink-3, the live one is lit and blinks, the rest are
/// ghosts. Give the word for each station in its current tense.
///
///     HudStations(titles: ["Saved", "Uploading", "Transcript", "Notes"], current: 1)
struct HudStations: View {
    let titles: [String]
    /// Index of the live station; `titles.count` when all are done.
    let current: Int

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                VStack(alignment: .leading, spacing: 8) {
                    HudCell(cell: index < current ? .done : (index == current ? .current : .off))
                        .frame(height: 4)
                    Text(title)
                        .hud(.label, index < current ? Hud.Ink.ink3 : (index == current ? Hud.Ink.ink1 : Hud.Ink.ink4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Talk time

/// Talk-time bar (notch detail): one 4 pt bar split by speaker share — ink-1, ink-2,
/// ink-4.
///
///     HudTalkBar(shares: [0.46, 0.38, 0.16])
struct HudTalkBar: View {
    let shares: [Double]
    var height: CGFloat = 4

    static let inks: [Color] = [Hud.Ink.ink1, Hud.Ink.ink2, Hud.Ink.ink4]

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.0001, shares.reduce(0, +))
            let usable = proxy.size.width - 2 * CGFloat(max(0, shares.count - 1))
            HStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                    Rectangle().fill(Self.inks[min(index, Self.inks.count - 1)])
                        .frame(width: max(0, usable * share / total))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// A speaker's dot for the talk-time legend (6 pt).
struct HudSpeakerDot: View {
    /// 0 = you, 1, 2 …
    let index: Int

    var body: some View {
        Circle().fill(HudTalkBar.inks[min(index, HudTalkBar.inks.count - 1)]).frame(width: 6, height: 6)
    }
}

/// Track (`.track`): a 4 pt progress bar; the lit part glows. Desktop "Talk time" rows.
///
///     HudTrack(value: 0.46)
///     HudTrack(value: 0.38, tint: Hud.Ink.ink2, glows: false)
struct HudTrack: View {
    var value: Double
    var tint: Color = Hud.Ink.ink1
    var glows = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Hud.Ink.track)
                Capsule().fill(tint)
                    .shadow(color: glows ? tint.opacity(0.5) : .clear, radius: 3)
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Lane (`.lane`): who spoke when, as 3 pt blocks under the desktop player's waveform.
///
///     HudLane(segments: [(0.09, 0), (0.14, 1), (0.06, 0), (0.08, 2)])
struct HudLane: View {
    /// Share of the width and speaker index, in time order.
    let segments: [(share: Double, speaker: Int)]

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.0001, segments.map(\.share).reduce(0, +))
            let usable = proxy.size.width - 2 * CGFloat(max(0, segments.count - 1))
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(HudTalkBar.inks[min(segment.speaker, HudTalkBar.inks.count - 1)])
                        .frame(width: max(0, usable * segment.share / total))
                }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
