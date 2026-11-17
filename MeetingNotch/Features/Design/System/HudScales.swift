import SwiftUI

// Printed scales: day ruler, ramp, tuner, waveform, and the onboarding schematic.

// MARK: - Day ruler

/// Day ruler (`.ruler`): the shape of the day. A tick every half hour, a longer one on
/// the hour, a label every two hours; events are lit 6 pt blocks above the scale; "now"
/// is an amber needle; the past is dimmed.
///
/// The wide ruler (desktop, 62 pt) prints event names under their blocks; past events
/// fade to 35 % instead of being masked.
///
///     HudDayRuler(now: 10.7, events: [.init(14.5, 15.25, .focus), .init(16, 17), .init(17.5, 18, .invite)])
///         .padding(.horizontal, 10)
///     HudDayRuler(now: 10.7, events: [.init(11.25, 12, .focus, title: "Design review")], wide: true)
struct HudDayRuler: View {
    struct Event: Equatable, Sendable {
        enum Kind: Sendable {
            /// Any other event: ink-3.
            case normal
            /// The focused (next) event: ink-1, lit.
            case focus
            /// Near or running: amber, lit.
            case amber
            /// An unanswered invite: amber outline.
            case invite
            /// Personal: ink-4.
            case dim
        }

        /// Hours as decimals (14.5 = 14:30).
        let start: Double
        let end: Double
        var kind: Kind = .normal
        /// Printed under the block on the wide ruler.
        var title: String?

        init(_ start: Double, _ end: Double, _ kind: Kind = .normal, title: String? = nil) {
            self.start = start
            self.end = end
            self.kind = kind
            self.title = title
        }
    }

    /// First and last hour on the scale.
    var span: ClosedRange<Double> = 8...20
    /// The current time in decimal hours.
    var now: Double
    var events: [Event] = []
    var wide = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(in: &context, width: width) }
                if wide {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        if let title = event.title {
                            let share = (event.end - event.start) / (span.upperBound - span.lowerBound)
                            Text(title)
                                .hud(.micro, labelColor(event.kind))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: width * max(share, 0.09), alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(event.end <= now ? 0.35 : 1)
                                .offset(x: x(event.start, width), y: 17)
                        }
                    }
                }
                ForEach(labelHours, id: \.self) { hour in
                    Text(verbatim: String(format: "%02d", hour))
                        .hud(.micro)
                        .fixedSize()
                        .frame(width: 30)
                        .offset(x: x(Double(hour), width) - 15, y: wide ? 47 : 31)
                }
            }
        }
        .frame(height: wide ? 62 : 46)
        .accessibilityHidden(true)
    }

    private var labelHours: [Int] {
        let first = Int(span.lowerBound.rounded(.up)), last = Int(span.upperBound.rounded(.down))
        return (first...max(first, last)).filter { $0 % 2 == 0 && Double($0) > span.lowerBound && Double($0) < span.upperBound }
    }

    private func x(_ hour: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((hour - span.lowerBound) / (span.upperBound - span.lowerBound)) * width
    }

    private func labelColor(_ kind: Event.Kind) -> Color {
        switch kind {
        case .focus: Hud.Ink.ink1
        case .amber, .invite: Hud.Ink.signal
        case .normal, .dim: Hud.Ink.ink3
        }
    }

    private func draw(in context: inout GraphicsContext, width: CGFloat) {
        // Event blocks.
        for event in events {
            let rect = CGRect(x: x(event.start, width), y: 6, width: max(0, x(event.end, width) - x(event.start, width) - 2), height: wide ? 7 : 6)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            var layer = context
            if wide, event.end <= now { layer.opacity = 0.35 }
            switch event.kind {
            case .normal:
                layer.fill(path, with: .color(Hud.Ink.ink3))
            case .dim:
                layer.fill(path, with: .color(Hud.Ink.ink4))
            case .invite:
                layer.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5), with: .color(Hud.Ink.signal), lineWidth: 1)
            case .focus, .amber:
                let color = event.kind == .focus ? Hud.Ink.ink1 : Hud.Ink.signal
                layer.drawLayer { glow in
                    glow.addFilter(.shadow(color: color.opacity(event.kind == .focus ? 0.45 : 0.5), radius: 3))
                    glow.fill(path, with: .color(color))
                }
            }
        }

        // Scale: a tick every half hour, a longer one on the hour.
        let tickTop: CGFloat = wide ? 36 : 20
        var t = span.lowerBound
        while t <= span.upperBound + 1e-6 {
            let isHour = t == t.rounded()
            let rect = CGRect(x: min(x(t, width), width - 1), y: tickTop, width: 1, height: isHour ? 6 : 3)
            context.fill(Path(rect), with: .color((isHour ? Hud.Ink.ink3 : Hud.Ink.ink4).opacity(t < now ? 0.45 : 1)))
            t += 0.5
        }

        let nowX = x(min(max(now, span.lowerBound), span.upperBound), width)

        // The past is dimmed (narrow ruler): a black veil over the event row.
        if !wide, nowX > 0 {
            context.fill(
                Path(CGRect(x: 0, y: 4, width: nowX, height: 10)),
                with: .linearGradient(Gradient(colors: [.black.opacity(0.72), .black.opacity(0.5)]),
                                      startPoint: .zero, endPoint: CGPoint(x: nowX, y: 0))
            )
        }

        // Now: an amber needle with a small flag.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Hud.Ink.signal.opacity(0.8), radius: 3))
            layer.fill(Path(CGRect(x: nowX, y: 1, width: 1, height: wide ? 42 : 26)), with: .color(Hud.Ink.signal))
            layer.fill(Path(roundedRect: CGRect(x: nowX - 2.5, y: 0, width: 6, height: 3), cornerRadius: 1), with: .color(Hud.Ink.signal))
        }
    }
}

// MARK: - Ramp

/// Ramp (`.ramp`): elapsed recording time against the planned length. The band thickens
/// as it rises (2 → 11 pt); under it a tick every 5 minutes, a longer one every 15.
/// Past the plan is a printed red zone; when the time runs into it the band lights red.
/// The scale is 1.25 × the plan. Beside it stands only "of 60 min".
///
///     HudRamp(elapsed: 768, plan: 3600)
struct HudRamp: View {
    /// Seconds recorded.
    var elapsed: TimeInterval
    /// Planned length in seconds.
    var plan: TimeInterval
    /// End of the scale in seconds; 1.25 × plan when nil.
    var scaleMax: TimeInterval?
    var width: CGFloat = 196

    var body: some View {
        Canvas { context, _ in
            let W = width, H: CGFloat = 11
            let maximum = max(1, scaleMax ?? plan * 1.25)
            func x(_ t: TimeInterval) -> CGFloat { min(W, CGFloat(t / maximum) * W) }
            func y(_ px: CGFloat) -> CGFloat { H - 1.5 - (px / W) * (H - 3.5) }
            func band(_ x0: CGFloat, _ x1: CGFloat) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: x0, y: H))
                path.addLine(to: CGPoint(x: x0, y: y(x0)))
                path.addLine(to: CGPoint(x: x1, y: y(x1)))
                path.addLine(to: CGPoint(x: x1, y: H))
                path.closeSubpath()
                return path
            }
            let xp = x(plan), xv = x(max(0, elapsed))
            context.fill(band(0, W), with: .color(Color(white: 1, opacity: 0.07)))
            context.fill(band(xp, W), with: .color(Hud.Ink.live.opacity(0.22)))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Hud.Ink.ink1.opacity(0.5), radius: 2))
                layer.fill(band(0, min(xv, xp)), with: .color(Hud.Ink.ink1))
            }
            if xv > xp {
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: Hud.Ink.live.opacity(0.7), radius: 3))
                    layer.fill(band(xp, xv), with: .color(Hud.Ink.live))
                }
            }
            context.fill(Path(CGRect(x: xp, y: H + 1, width: W - xp, height: 1)), with: .color(Hud.Ink.live.opacity(0.8)))
            var t: TimeInterval = 0
            while t <= maximum + 1 {
                let isMajor = t.truncatingRemainder(dividingBy: 900) == 0
                let color = t > plan ? Hud.Ink.live : (isMajor ? Hud.Ink.ink3 : Hud.Ink.ink4)
                context.fill(Path(CGRect(x: x(t) - 0.5, y: H + 2, width: 1, height: isMajor ? 4 : 2)), with: .color(color))
                t += 300
            }
        }
        .frame(width: width, height: 17)
        .accessibilityHidden(true)
    }
}

// MARK: - Tuner scale

/// Tuner scale (`.tuner`): under the notch player's waveform — a tick a minute, a
/// labelled longer tick every ten. The playhead needle reaches down into the scale.
///
///     HudTunerScale(minutes: 48)
struct HudTunerScale: View {
    var minutes: Int

    var body: some View {
        Canvas { context, size in
            guard minutes > 0 else { return }
            for minute in 0...minutes {
                let isMajor = minute % 10 == 0
                let x = min(size.width - 1, size.width * CGFloat(minute) / CGFloat(minutes))
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: isMajor ? 5 : 3)), with: .color(isMajor ? Hud.Ink.ink3 : Hud.Ink.ink4))
                if isMajor, minute > 0, minute < minutes - 3 {
                    context.draw(Text(verbatim: "\(minute)").font(Hud.Style.micro.font).foregroundStyle(Hud.Ink.ink4),
                                 at: CGPoint(x: x, y: 7), anchor: .top)
                }
            }
        }
        .frame(height: 17)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Waveform

/// The whole meeting as waveform bars. The played part is ink-1, the rest ink-4; an
/// amber needle marks the position; clicking or dragging jumps there.
///
///     HudWaveform(samples: peaks, progress: position) { position = $0 }
///     HudWaveform(samples: HudWaveform.demoSamples(), progress: 0.25, headOverhang: (4, 4))   // desktop player
struct HudWaveform: View {
    /// 0…1 per bar.
    let samples: [Double]
    /// 0…1 play position.
    var progress: Double
    /// How far the needle reaches past the bars: `(2, 9)` in the notch (down into the
    /// tuner scale), `(4, 4)` in the desktop player.
    var headOverhang: (top: CGFloat, bottom: CGFloat) = (2, 9)
    var height: CGFloat = 28
    var onScrub: ((Double) -> Void)?

    init(samples: [Double], progress: Double, headOverhang: (top: CGFloat, bottom: CGFloat) = (2, 9), height: CGFloat = 28,
         onScrub: ((Double) -> Void)? = nil) {
        self.samples = samples
        self.progress = progress
        self.headOverhang = headOverhang
        self.height = height
        self.onScrub = onScrub
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in
                let count = samples.count
                guard count > 0 else { return }
                let gap: CGFloat = 2
                let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                var played = Path(), rest = Path()
                for (index, sample) in samples.enumerated() {
                    let barHeight = min(size.height, 3 + CGFloat(min(1, max(0, sample))) * 22)
                    let rect = CGRect(x: CGFloat(index) * (barWidth + gap), y: (size.height - barHeight) / 2, width: barWidth, height: barHeight)
                    let corner = CGSize(width: barWidth / 2, height: barWidth / 2)
                    if Double(index) / Double(count) < progress { played.addRoundedRect(in: rect, cornerSize: corner) }
                    else { rest.addRoundedRect(in: rect, cornerSize: corner) }
                }
                context.fill(rest, with: .color(Hud.Ink.ink4))
                context.fill(played, with: .color(Hud.Ink.ink1))
            }
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Hud.Ink.signal)
                    .frame(width: 1, height: size.height + headOverhang.top + headOverhang.bottom)
                    .shadow(color: Hud.Ink.signal.opacity(0.8), radius: 3)
                    .offset(x: size.width * min(1, max(0, progress)), y: -headOverhang.top)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    guard size.width > 0 else { return }
                    onScrub?(min(1, max(0, value.location.x / size.width)))
                },
                including: onScrub == nil ? .none : .all
            )
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// The prototype's deterministic waveform, for previews and placeholders.
    static func demoSamples(count: Int = 110) -> [Double] {
        var seed = 7.0
        func random() -> Double {
            seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233_280)
            return seed / 233_280
        }
        return (0..<count).map { index in
            pow(random(), 1.6) * (0.55 + 0.45 * pow(sin(Double(index) / 9), 2))
        }
    }
}

// MARK: - Schematic

private struct HudPathShape: Shape {
    let source: Path
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        source.applying(CGAffineTransform(scaleX: rect.width / box.width, y: rect.height / box.height))
    }
}

/// System schematic (`.schem`): a 150×92 line drawing of the Mac. The notch and the
/// microphone are lit from the start; the notification, the speaker grilles, the `fn`
/// key and the text cursor light teal as their permission comes on. During "Turn on
/// all" a scanner sweeps over it and the parts light with their lamps, 0.42 s apart.
///
///     HudSchematic(lit: [.notifications, .speakers], scanning: isTurningOn)
struct HudSchematic: View {
    enum Part: Int, CaseIterable, Sendable {
        /// The notification banner (Notifications).
        case notifications
        /// The speaker grilles (System audio).
        case speakers
        /// The fn key (Input Monitoring).
        case fnKey
        /// The text cursor (Accessibility).
        case cursor

        fileprivate var path: Path {
            switch self {
            case .notifications: HudSVGPath.path("M98 16H122V23H98Z")
            case .speakers: HudSVGPath.path("M18 75.5H36M18 78.5H36M114 75.5H132M114 78.5H132")
            case .fnKey: HudSVGPath.path("M22 79.5H31V82H22Z")
            case .cursor: HudSVGPath.path("M72 34H78M75 34V46M72 46H78")
            }
        }
    }

    var lit: Set<Part> = []
    var scanning = false

    private static let box = CGSize(width: 150, height: 92)
    private static let body = HudSVGPath.path("M22 4H128V66H22ZM8 72H142L136 84H14ZM22 66H128")
    private static let notch = HudSVGPath.path("M62 4H88V9L86 11H64L62 9Z")
    private static let mic = HudSVGPath.path("M57.5 6.5H59M91 6.5H92.5")
    private static let line = StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter, miterLimit: 4)

    var body: some View {
        ZStack {
            HudPathShape(source: Self.body, box: Self.box).stroke(Hud.Ink.ink4, style: Self.line)
            Group {
                HudPathShape(source: Self.notch, box: Self.box).fill(Hud.Ink.ok)
                HudPathShape(source: Self.mic, box: Self.box).stroke(Hud.Ink.ok, style: Self.line)
            }
            .hudGlow(Hud.Ink.ok, tight: 2, tightOpacity: 0.8, wide: 6, wideOpacity: 0.3)
            ForEach(Part.allCases, id: \.self) { part in
                let on = lit.contains(part)
                HudPathShape(source: part.path, box: Self.box)
                    .stroke(on ? Hud.Ink.ok : Hud.Ink.ink5, style: Self.line)
                    .hudGlow(Hud.Ink.ok, tight: 2, tightOpacity: 0.8, wide: 6, wideOpacity: 0.3, enabled: on)
            }
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .animation(.easeOut(duration: 0.3), value: lit)
        .hudScanner(scanning, radius: 6)
        .accessibilityHidden(true)
    }
}
