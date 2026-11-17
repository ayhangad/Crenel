import SwiftUI

/// A printed zone on a gauge (`data-zones`), in ticks from the start. The zone is always
/// printed as a thin arc inside the ticks; a lit tick inside it takes the zone's colour,
/// an unlit one is a 26 % coloured ghost. Later zones win (red over amber).
struct HudGaugeZone: Equatable, Sendable {
    let ticks: Range<Int>
    let color: Color

    static func amber(_ ticks: Range<Int>) -> HudGaugeZone { HudGaugeZone(ticks: ticks, color: Hud.Ink.signal) }
    static func red(_ ticks: Range<Int>) -> HudGaugeZone { HudGaugeZone(ticks: ticks, color: Hud.Ink.live) }

    /// The countdown dial: last 10 minutes amber, last 2 red.
    static let countdown: [HudGaugeZone] = [.amber(0..<10), .red(0..<2)]
    /// The amber (≤ 10 min) dial keeps only its red line.
    static let redline: [HudGaugeZone] = [.red(0..<2)]
}

/// The tick sweep gauge's face (`.gauge`): 270° sweep, one tick per unit, every
/// `major`-th tick longer and thicker. Lit ticks count from the start (lower left).
///
/// Light model, as in the prototype:
/// - ghost — every unlit tick at 13 %
/// - lit — ticks below the value, 1.6 px core glow
/// - head — the last lit tick: 45 % white mixed in, 1.2 pt longer, double glow (2 + 6 px)
/// - tail — the 3 ticks after the head keep 42 / 27 / 17 % (phosphor afterglow)
/// - halo — a blurred arc behind the lit range, 10 % of the size thick, 20 %
/// - dots — inner ring, one per major tick (gauges ≥ 96 pt); 90 % when passed, else 22 %;
///   replaced by scale numbers when `labels` is set (gauges ≥ 140 pt)
struct HudGaugeFace: View, Animatable {
    /// 0…1.
    var value: Double
    var ticks = 60
    var major = 15
    var size: CGFloat = 104
    var tint: Color = Hud.Ink.ink1
    var zones: [HudGaugeZone] = []
    var labels: [String]?

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            draw(in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func angle(_ index: Int) -> Double {
        (-135 + 270 * Double(index) / Double(max(1, ticks - 1))) * .pi / 180
    }

    private func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: size / 2 + sin(angle) * radius, y: size / 2 - cos(angle) * radius)
    }

    private func arc(_ from: Int, _ to: Int, radius: CGFloat) -> Path {
        var path = Path()
        // Angles are measured clockwise from 12 o'clock; SwiftUI's from 3 o'clock.
        path.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: radius,
                    startAngle: .radians(angle(from) - .pi / 2), endAngle: .radians(angle(to) - .pi / 2), clockwise: false)
        return path
    }

    private func zone(at index: Int) -> HudGaugeZone? {
        zones.last { $0.ticks.contains(index) }
    }

    private func draw(in context: inout GraphicsContext) {
        let r = size / 2 - 1.5
        let lit = Int((min(1, max(0, value)) * Double(ticks)).rounded())
        let round = { (width: CGFloat) in StrokeStyle(lineWidth: width, lineCap: .round) }

        // Halo: light spilling on the face behind the lit range.
        if lit > 1 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: size * 0.045))
                layer.opacity = 0.2
                layer.stroke(arc(0, lit - 1, radius: r - size * 0.04), with: .color(tint), style: round(size * 0.1))
            }
        }

        // Printed zones.
        for zone in zones where !zone.ticks.isEmpty {
            let path = arc(zone.ticks.lowerBound, max(zone.ticks.lowerBound, zone.ticks.upperBound - 1), radius: r - size * 0.085 - size * 0.03)
            context.stroke(path, with: .color(zone.color.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
        }

        var ghost: [(Path, Color, CGFloat)] = []
        var on: [(Path, Color, CGFloat)] = []
        var head: (Path, Color, CGFloat)?

        for index in 0..<ticks {
            let a = angle(index)
            let isMajor = major > 0 && index % major == 0
            let isHead = index == lit - 1 && lit < ticks
            let length = (isMajor ? size * 0.085 : size * 0.05) + (isHead ? 1.2 : 0)
            var line = Path()
            line.move(to: point(a, r - length))
            line.addLine(to: point(a, r))
            let width: CGFloat = isMajor || isHead ? 1.7 : 1.25
            let zone = zone(at: index)
            let base = zone?.color ?? tint
            let tail = index - lit

            if isHead {
                head = (line, zone?.color ?? tint.hudMixedWithWhite(0.45), width)
            } else if index < lit {
                on.append((line, base, width))
            } else if lit > 0, (0..<3).contains(tail) {
                ghost.append((line, base.opacity([0.42, 0.27, 0.17][tail]), width))
            } else {
                ghost.append((line, base.opacity(zone == nil ? 0.13 : 0.26), width))
            }

            // Inner ring: a dot (or a scale number) per major tick.
            if isMajor, size >= 96 {
                let passed = index < lit
                let center = point(a, r - size * 0.085 - size * (labels == nil ? 0.055 : 0.1))
                if let labels {
                    let slot = index / major
                    if slot < labels.count {
                        context.draw(
                            Text(verbatim: labels[slot]).font(Hud.font(size * 0.066, .medium))
                                .foregroundColor(tint.opacity(passed ? 0.85 : 0.32)),
                            at: center, anchor: .center
                        )
                    }
                } else {
                    let radius: CGFloat = size >= 140 ? 1.1 : 0.85
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(tint.opacity(passed ? 0.9 : 0.22)))
                }
            }
        }

        for (path, color, width) in ghost {
            context.stroke(path, with: .color(color), style: round(width))
        }
        if !on.isEmpty {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint.opacity(0.7), radius: 1.6))
                for (path, color, width) in on {
                    layer.stroke(path, with: .color(color), style: round(width))
                }
            }
        }
        if let head {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: tint, radius: 2))
                layer.addFilter(.shadow(color: tint.opacity(0.6), radius: 6))
                layer.stroke(head.0, with: .color(head.1), style: round(head.2))
            }
        }
    }
}

/// The tick sweep gauge with its centre content and light bleed (`.gauge-box.bleed`).
///
/// Meeting countdown: the last 60 minutes, one tick per minute; while the meeting runs
/// it shows the share that is left.
///
///     HudGauge(value: 0.55, zones: HudGaugeZone.countdown) {
///         HudSegmentDigits("33", height: 24, cells: 2)
///         Text("min").hud(.micro, Hud.Ink.ink3)
///     }
///     HudGauge(value: 0.55, size: 148, zones: HudGaugeZone.countdown, labels: ["0", "15", "30", "45", "60"], ignite: true) { … }
struct HudGauge<Center: View>: View {
    /// 0…1.
    var value: Double
    var ticks = 60
    var major = 15
    var size: CGFloat = 104
    var tint: Color = Hud.Ink.ink1
    var zones: [HudGaugeZone] = []
    /// Scale numbers on the major ticks; only for gauges ≥ 140 pt.
    var labels: [String]?
    /// Radial light behind the gauge in its colour (10 % centre, 3 % at 60 %).
    var bleed = true
    /// Ignition: sweep to full (0.42 s) and settle to the value (0.52 s) when the view
    /// appears. Use it when a panel opens from closed or a desktop page changes — not on
    /// tab or state changes within the same surface.
    var ignite = false
    /// Change this to run the ignition sweep again without recreating the view.
    var igniteTrigger: AnyHashable?
    @ViewBuilder var center: () -> Center

    @State private var sweep: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double, ticks: Int = 60, major: Int = 15, size: CGFloat = 104, tint: Color = Hud.Ink.ink1,
         zones: [HudGaugeZone] = [], labels: [String]? = nil, bleed: Bool = true, ignite: Bool = false,
         igniteTrigger: AnyHashable? = nil, @ViewBuilder center: @escaping () -> Center) {
        self.value = value
        self.ticks = ticks
        self.major = major
        self.size = size
        self.tint = tint
        self.zones = zones
        self.labels = labels
        self.bleed = bleed
        self.ignite = ignite
        self.igniteTrigger = igniteTrigger
        self.center = center
        _sweep = State(initialValue: ignite ? 0 : nil)
    }

    var body: some View {
        HudGaugeFace(value: sweep ?? value, ticks: ticks, major: major, size: size, tint: tint, zones: zones, labels: labels)
            .background {
                if bleed {
                    Circle()
                        .fill(RadialGradient(
                            stops: [.init(color: tint.opacity(0.10), location: 0), .init(color: tint.opacity(0.03), location: 0.6),
                                    .init(color: tint.opacity(0), location: 1)],
                            center: .center, startRadius: 0, endRadius: size / 2 + 30
                        ))
                        .frame(width: size + 60, height: size + 60)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                VStack(spacing: 5) { center() }.padding(.top, 4)
            }
            .onAppear { if ignite { runIgnition() } }
            .onChange(of: igniteTrigger) { _, _ in runIgnition() }
    }

    private func runIgnition() {
        guard !reduceMotion else {
            sweep = nil
            return
        }
        sweep = 0
        withAnimation(Hud.Motion.igniteUp) { sweep = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Hud.Motion.igniteUpDuration) {
            withAnimation(Hud.Motion.igniteDown) { sweep = nil }
        }
    }
}

extension HudGauge where Center == EmptyView {
    /// A gauge with nothing in its centre.
    init(value: Double, ticks: Int = 60, major: Int = 15, size: CGFloat = 104, tint: Color = Hud.Ink.ink1,
         zones: [HudGaugeZone] = [], labels: [String]? = nil, bleed: Bool = true, ignite: Bool = false,
         igniteTrigger: AnyHashable? = nil) {
        self.init(value: value, ticks: ticks, major: major, size: size, tint: tint, zones: zones, labels: labels,
                  bleed: bleed, ignite: ignite, igniteTrigger: igniteTrigger) { EmptyView() }
    }
}

/// The gauge at rest (empty states): all ghosts, `--:--` in the middle — or, when
/// something is wrong, the status shape instead (failed refresh: triangle; access off:
/// octagon).
///
///     HudRestingGauge()
///     HudRestingGauge(status: .off)
struct HudRestingGauge: View {
    var status: HudStatus?
    var size: CGFloat = 104

    var body: some View {
        HudGauge(value: 0, size: size, bleed: false) {
            if let status {
                HudStatusShape(status, size: HudStatusShape.hero)
            } else {
                HudSegmentDigits("--:--", height: 15)
            }
        }
    }
}
