import SwiftUI

// MARK: - Loops (pulse, breathe, blink)

/// The three opacity loops of the language. All of them stop under Reduce Motion.
enum HudLoop: Equatable, Sendable {
    case steady
    /// Recording lamp: 1 ↔ 0.3 over 1.4 s (`.pulse`).
    case pulse
    /// Working icon: 0.45 ↔ 1 over 1.8 s (`.breathe`).
    case breathe
    /// Waiting lamp: on for 55 % of 1.1 s, then 18 % (`.blink`, stepped).
    case blink

    func opacity(at time: TimeInterval) -> Double {
        switch self {
        case .steady:
            return 1
        case .pulse:
            return 0.65 + 0.35 * cos(2 * .pi * time / Hud.Motion.pulsePeriod)
        case .breathe:
            return 0.725 - 0.275 * cos(2 * .pi * time / Hud.Motion.breathePeriod)
        case .blink:
            let phase = time.truncatingRemainder(dividingBy: Hud.Motion.blinkPeriod) / Hud.Motion.blinkPeriod
            return phase < 0.555 ? 1 : 0.18
        }
    }
}

private struct HudLoopModifier: ViewModifier {
    let loop: HudLoop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if loop == .steady || reduceMotion {
            content
        } else if loop == .blink {
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: Hud.Motion.blinkPeriod / 20)) { timeline in
                content.opacity(loop.opacity(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                content.opacity(loop.opacity(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}

extension View {
    /// Runs one of the opacity loops on this view: `.hudLoop(.pulse)`.
    func hudLoop(_ loop: HudLoop) -> some View {
        modifier(HudLoopModifier(loop: loop))
    }
}

// MARK: - Lamp

/// The one way to show a calm state: an 8×4 telltale (or a 7 pt dot for "live"). A lit
/// lamp has a hot core and two glow layers; an unlit one stays visible as a ghost.
///
///     HudLamp(.teal)
///     HudLamp(.red, shape: .dot, loop: .pulse)      // recording
///     HudLamp(.amber, loop: .blink)                 // waiting for you
struct HudLamp: View {
    enum Form: Sendable { case bar, dot }

    let color: Hud.LampColor
    var form: Form = .bar
    var loop: HudLoop = .steady
    /// Flash once when the lamp turns on (`.lamp.fire`, onboarding "Turn on all").
    var fires = false
    @State private var flash: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ color: Hud.LampColor, form: Form = .bar, loop: HudLoop = .steady, fires: Bool = false) {
        self.color = color
        self.form = form
        self.loop = loop
        self.fires = fires
    }

    var body: some View {
        let size = form == .bar ? CGSize(width: 8, height: 4) : CGSize(width: 7, height: 7)
        let shape = RoundedRectangle(cornerRadius: form == .bar ? 2 : 3.5, style: .circular)
        let glow = color.glow
        let isWhite = color == .white
        Group {
            if color.isLit {
                shape.fill(
                    EllipticalGradient(
                        stops: [.init(color: color.core, location: 0), .init(color: color.color, location: color.coreStop)],
                        center: UnitPoint(x: 0.5, y: 0.45), startRadiusFraction: 0, endRadiusFraction: 0.75
                    )
                )
                .shadow(color: color.color.opacity(glow.tight), radius: isWhite ? 2.5 : 3)
                .shadow(color: color.color.opacity(glow.wide), radius: isWhite ? 7 : 8)
            } else if color == .dim {
                shape.fill(color.color)
            } else {
                shape.fill(color.color)
                    .overlay(shape.strokeBorder(Color(white: 1, opacity: 0.05), lineWidth: 0.5))
            }
        }
        .frame(width: size.width, height: size.height)
        .brightness(flash)
        .hudLoop(color.isLit ? loop : .steady)
        .onChange(of: color.isLit) { _, lit in
            guard fires, lit, !reduceMotion else { return }
            flash = -0.6
            withAnimation(.easeOut(duration: 0.2)) { flash = 0.45 }
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) { flash = 0 }
        }
        .accessibilityHidden(true)
    }
}

/// Legacy name: a breathing live dot. Draws as a pulsing dot lamp in the nearest lamp
/// colour.
struct HudPulse: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        HudLamp(lamp, form: .dot, loop: .pulse)
            .scaleEffect(size / 7)
            .frame(width: max(size, Hud.Size.smallIcon), height: max(size, Hud.Size.smallIcon))
    }

    private var lamp: Hud.LampColor {
        if color == Hud.Ink.live { return .red }
        if color == Hud.Ink.signal { return .amber }
        if color == Hud.Ink.ok { return .teal }
        return .white
    }
}

// MARK: - Cells

/// A row of small cells (`.cells`): progress in whole things. 9×4, 3 pt apart.
///
///     HudCells(done: 1, total: 5)                           // today's tasks: lit / ghost
///     HudCells(states: [.done, .current, .off, .off])       // processing ear
struct HudCells: View {
    enum Cell: Sendable {
        case off
        /// Lit white.
        case on
        /// Passed: ink-3, no glow.
        case done
        /// Lit and blinking — the live station.
        case current
    }

    let states: [Cell]
    /// Cells stretch to fill the width (processing stations).
    var flexible = false

    init(states: [Cell], flexible: Bool = false) {
        self.states = states
        self.flexible = flexible
    }

    init(done: Int, total: Int) {
        states = (0..<max(0, total)).map { $0 < done ? .on : .off }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, cell in
                HudCell(cell: cell)
                    .frame(width: flexible ? nil : 9, height: 4)
                    .frame(maxWidth: flexible ? .infinity : nil)
            }
        }
        .animation(.easeOut(duration: 0.25), value: states.map { "\($0)" })
        .accessibilityHidden(true)
    }
}

struct HudCell: View {
    let cell: HudCells.Cell

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        switch cell {
        case .off:
            shape.fill(Color(white: 1, opacity: 0.09))
        case .on:
            shape.fill(Hud.Ink.ink1).shadow(color: Hud.Ink.ink1.opacity(0.45), radius: 3)
        case .done:
            shape.fill(Hud.Ink.ink3)
        case .current:
            shape.fill(Hud.Ink.ink1).shadow(color: Hud.Ink.ink1.opacity(0.5), radius: 3).hudLoop(.blink)
        }
    }
}

// MARK: - Priority bars

/// Priority as three rising bars, like a signal meter (`.pri`).
///
///     HudPriorityBars(level: 3, tint: Hud.Ink.signal)
struct HudPriorityBars: View {
    /// 0…3 lit bars.
    let level: Int
    var tint: Color = Hud.Ink.ink2

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < level ? tint : Hud.Ink.ink5)
                    .frame(width: 2, height: [4, 7, 10][index])
            }
        }
        .frame(height: 10, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Status shapes

/// The shape says what kind of state it is; colour only says how bad.
enum HudStatus: String, CaseIterable, Sendable {
    /// Triangle with a cut-out `!` — broken, failed. Red.
    case err
    /// Diamond with a cut-out `!` — waiting for you. Amber (red when overdue).
    case warn
    /// Octagon with a cut-out bar — a system permission is off. Amber; red when it
    /// blocks recording.
    case off
    /// Hourglass — queued. Ink-3.
    case wait
    /// Square — stopped. Ink-3.
    case stop
    /// Three cells with a light running through them — working. Amber.
    case busy

    var defaultTint: Color {
        switch self {
        case .err: Hud.Ink.live
        case .warn, .off, .busy: Hud.Ink.signal
        case .wait, .stop: Hud.Ink.ink3
        }
    }

    /// `s-*` paths on the 16-unit grid (even-odd).
    fileprivate var path: Path {
        switch self {
        case .err: HudStatusArt.err
        case .warn: HudStatusArt.warn
        case .off: HudStatusArt.off
        case .wait: HudStatusArt.wait
        case .stop, .busy: HudStatusArt.stop
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .err: "Failed"
        case .warn: "Needs you"
        case .off: "Access is off"
        case .wait: "Waiting"
        case .stop: "Stopped"
        case .busy: "Working"
        }
    }
}

private enum HudStatusArt {
    static let err = HudSVGPath.path("M8 1L15.25 14H.75ZM7.25 5.75H8.75V9.5H7.25ZM7.25 10.75H8.75V12.25H7.25Z")
    static let warn = HudSVGPath.path("M8 .5L15.5 8L8 15.5L.5 8ZM7.25 4.25H8.75V8.75H7.25ZM7.25 10H8.75V11.5H7.25Z")
    static let off = HudSVGPath.path("M5 1H11L15 5V11L11 15H5L1 11V5ZM3.75 7.1H12.25V8.9H3.75Z")
    static let wait = HudSVGPath.path("M3 1H13V3.25L9.5 8L13 12.75V15H3V12.75L6.5 8L3 3.25Z")
    static let stop = HudSVGPath.path("M3 3H13V13H3Z")
}

/// A status shape (`data-sg`). 12 pt in rows and text, 14 pt in the ear, 24 pt inside a
/// `HudStatusWell` or a resting gauge. Red and amber shapes glow.
///
///     HudStatusShape(.warn)
///     HudStatusShape(.off, size: HudStatusShape.ear, tint: Hud.Ink.live)
///     HudStatusShape(.busy)
struct HudStatusShape: View {
    static let row: CGFloat = 12
    static let ear: CGFloat = 14
    static let hero: CGFloat = 24

    let status: HudStatus
    var size: CGFloat = HudStatusShape.row
    var tint: Color?
    var loop: HudLoop = .steady

    init(_ status: HudStatus, size: CGFloat = HudStatusShape.row, tint: Color? = nil, loop: HudLoop = .steady) {
        self.status = status
        self.size = size
        self.tint = tint
        self.loop = loop
    }

    var body: some View {
        let color = tint ?? status.defaultTint
        Group {
            if status == .busy {
                HudBusy(tint: color).scaleEffect(size / 12)
                    .frame(width: 13 * size / 12, height: size)
            } else {
                let glows = color != Hud.Ink.ink3 && color != Hud.Ink.ink1
                Canvas { context, canvasSize in
                    let scale = canvasSize.width / 16
                    context.fill(status.path.applying(CGAffineTransform(scaleX: scale, y: scale)),
                                 with: .color(color), style: FillStyle(eoFill: true))
                }
                .frame(width: size, height: size)
                .hudGlow(color, tight: 2, tightOpacity: 0.6, wide: 8, wideOpacity: 0.22, enabled: glows)
                .hudLoop(loop)
            }
        }
        .accessibilityLabel(Text(status.accessibilityLabel))
    }
}

/// Busy: three cells, a light running through them once every 1.05 s. Motion, not
/// colour, says "working" (`.busy`).
struct HudBusy: View {
    var tint: Color = Hud.Ink.signal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            cells(lit: 1)
        } else {
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: Hud.Motion.busyPeriod / 3)) { timeline in
                let step = Int((timeline.date.timeIntervalSinceReferenceDate / (Hud.Motion.busyPeriod / 3)).rounded(.down)) % 3
                cells(lit: step)
            }
        }
    }

    private func cells(lit: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index == lit ? tint : tint.opacity(0.16))
                    .shadow(color: index == lit ? tint.opacity(0.7) : .clear, radius: 2.5)
                    .frame(width: 3, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The 44 pt lit well holding a 24 pt status shape (`.sg-hero`) — failure panels. The
/// well's floor glows faintly (16 %) in the shape's colour.
///
///     HudStatusWell(.err)
///     HudStatusWell(.off, tint: Hud.Ink.live)
struct HudStatusWell: View {
    let status: HudStatus
    var tint: Color?

    init(_ status: HudStatus, tint: Color? = nil) {
        self.status = status
        self.tint = tint
    }

    var body: some View {
        let color = tint ?? status.defaultTint
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HudStatusShape(status, size: HudStatusShape.hero, tint: color)
            .frame(width: 44, height: 44)
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(colors: [Hud.Layer.wellTop, Hud.Layer.wellBottom], startPoint: .top, endPoint: .bottom)
                            .shadow(.inner(color: .black.opacity(0.8), radius: 1, x: 0, y: 1))
                    )
                    shape.fill(
                        RadialGradient(colors: [color.opacity(0.16), color.opacity(0)], center: .center, startRadius: 0, endRadius: 44 * 0.7 * 0.7071)
                    )
                    shape.strokeBorder(Color(white: 1, opacity: 0.045), lineWidth: 1)
                }
            }
    }
}

/// A status word: its shape (or lamp) and a plain word — never coloured text
/// (`.ok-t`, `.dim-t`, `.warn-t`, `.err-t`, `.off-t`).
///
///     HudStatusWord(.ok, "Connected")
///     HudStatusWord(.off(blocking: true), "Mic off")
struct HudStatusWord: View {
    enum Kind: Equatable, Sendable {
        /// Teal lamp — fine.
        case ok
        /// Empty lamp — nothing there.
        case dim
        /// Amber diamond — needs you.
        case warn
        /// Red triangle — broken.
        case err
        /// Octagon — access is off; red when it blocks recording.
        case off(blocking: Bool = false)
    }

    let kind: Kind
    let title: Text
    var color: Color?

    init(_ kind: Kind, _ title: LocalizedStringKey, color: Color? = nil) {
        self.kind = kind
        self.title = Text(title)
        self.color = color
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ kind: Kind, _ title: S, color: Color? = nil) {
        self.kind = kind
        self.title = Text(title)
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .ok:
                RoundedRectangle(cornerRadius: 2).fill(Hud.Ink.ok).frame(width: 8, height: 4)
                    .shadow(color: Hud.Ink.ok.opacity(0.55), radius: 3.5)
            case .dim:
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color(white: 1, opacity: 0.22), lineWidth: 1)
                    .frame(width: 8, height: 4)
            case .warn:
                flat(.warn, Hud.Ink.signal)
            case .err:
                flat(.err, Hud.Ink.live)
            case let .off(blocking):
                flat(.off, blocking ? Hud.Ink.live : Hud.Ink.signal)
            }
            title.hud(.label, color ?? (kind == .dim ? Hud.Ink.ink3 : Hud.Ink.ink2)).lineLimit(1)
        }
    }

    /// Status words print their shape flat (a CSS mask in the prototype): no glow.
    private func flat(_ status: HudStatus, _ color: Color) -> some View {
        Canvas { context, size in
            let scale = size.width / 16
            context.fill(status.path.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(color), style: FillStyle(eoFill: true))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Telltales

/// An icon that lights (`.tt`). Unlit: the line glyph as a 20 % ghost. Lit: the solid
/// glyph in its colour with a two-layer glow. `paren` puts angled brackets either side —
/// "system / permission fault"; `badge` adds a corner `!` or `×`.
///
///     HudTelltale(.mic, .white)
///     HudTelltale(.mic, .amber, paren: true)          // mute state unknown
///     HudTelltale(.speaker, .red, badge: .bang)       // call audio dropped
///     HudTelltale(.calendar, .off)                    // unlit ghost
struct HudTelltale: View {
    let glyph: HudGlyph
    let state: Hud.LampColor
    var paren = false
    var badge: HudGlyphBadge?
    /// Glyph size: 16 in panels, 14 in the ears (bracketed telltales stay 16).
    var size: CGFloat = 16
    var loop: HudLoop = .steady
    @Environment(\.hudSurface) private var surface

    init(_ glyph: HudGlyph, _ state: Hud.LampColor, paren: Bool = false, badge: HudGlyphBadge? = nil,
         size: CGFloat = 16, loop: HudLoop = .steady) {
        self.glyph = glyph
        self.state = state
        self.paren = paren
        self.badge = badge
        self.size = size
        self.loop = loop
    }

    var body: some View {
        let lit = state.isLit
        let color = lit ? state.color : Color(white: 1, opacity: 0.2)
        let glyphSize = paren ? 16 : size
        Canvas { context, canvasSize in
            let origin = CGPoint(x: (canvasSize.width - glyphSize) / 2, y: (canvasSize.height - glyphSize) / 2)
            if paren {
                let scale = canvasSize.height / 16
                context.stroke(HudGlyphArt.paren.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(color),
                               style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .square, lineJoin: .miter, miterLimit: 4))
            }
            var glyphContext = context
            glyphContext.translateBy(x: origin.x, y: origin.y)
            let layers = (lit ? HudGlyphArt.solid[glyph] : nil) ?? HudGlyphArt.line[glyph] ?? []
            HudGlyphArt.draw(layers, in: &glyphContext, scale: glyphSize / 16, ink: .color(color), surface: surface)
            if let badge {
                HudGlyphArt.draw(HudGlyphArt.badge(badge), in: &glyphContext, scale: glyphSize / 16, ink: .color(color), surface: surface)
            }
        }
        .frame(width: paren ? 24 : size, height: paren ? 16 : size)
        .hudGlow(state.color, tight: 2, tightOpacity: 0.65, wide: 7, wideOpacity: 0.22, enabled: lit)
        .hudLoop(lit ? loop : .steady)
        .accessibilityHidden(true)
    }
}

/// A lit square with the glyph cut out (`.ttile`) — only for what must not be missed
/// (the processing-failure ear). 18 pt in panels, 16 pt in the ears.
///
///     HudTelltaleTile(.warning, .red)
struct HudTelltaleTile: View {
    let glyph: HudGlyph
    let color: Hud.LampColor
    var size: CGFloat = 18

    init(_ glyph: HudGlyph, _ color: Hud.LampColor = .red, size: CGFloat = 18) {
        self.glyph = glyph
        self.color = color
        self.size = size
    }

    var body: some View {
        let amber = color == .amber
        HudIcon(glyph, size: size >= 18 ? 12 : 11, solid: true)
            .foregroundStyle(.black)
            .hudSurface(color.color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.color))
            .shadow(color: color.color.opacity(amber ? 0.5 : 0.55), radius: 4)
            .shadow(color: color.color.opacity(amber ? 0.16 : 0.18), radius: 9)
            .accessibilityHidden(true)
    }
}

// MARK: - Task state mark

/// Task state as a chamfered square whose fill level says the state — empty frame, amber
/// half, red bar, dark full. Never a tick (`m-open`, `m-progress`, `m-blocked`, `m-done`).
struct HudStateMark: View {
    let state: TaskStatus
    var size: CGFloat = 16

    private static let frame = HudSVGPath.path("M4.75 2.25H11.25L13.75 4.75V11.25L11.25 13.75H4.75L2.25 11.25V4.75Z")
    private static let half = HudSVGPath.path("M8 5H10L11 6V10L10 11H8Z")
    private static let full = HudSVGPath.path("M6 5H10L11 6V10L10 11H6L5 10V6Z")

    var body: some View {
        Canvas { context, canvas in
            let transform = CGAffineTransform(scaleX: canvas.width / 16, y: canvas.width / 16)
            let color: Color = switch state {
            case .open: Hud.Ink.ink3
            case .inProgress: Hud.Ink.signal
            case .blocked: Hud.Ink.live
            case .completed: Hud.Ink.ink4
            }
            context.stroke(Self.frame.applying(transform), with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5 * canvas.width / 16, lineJoin: .miter, miterLimit: 4))
            switch state {
            case .open: break
            case .inProgress: context.fill(Self.half.applying(transform), with: .color(color))
            case .blocked: context.fill(HudSVGPath.rect(5, 7.25, 6, 1.5).applying(transform), with: .color(color))
            case .completed: context.fill(Self.full.applying(transform), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
