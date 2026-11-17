import AppKit
import Combine
import SwiftUI

/// Geometry of the notch on the current screen, shared with every notch view.
struct CrenelNotchMetrics: Equatable {
    /// Hardware notch size; width is zero on screens without a notch.
    var hardware: CGSize = CGSize(width: 0, height: 32)
    var hasPhysicalNotch = false

    /// Height of the band the notch shares with the menu bar.
    var topInset: CGFloat { hardware.height }

    /// The space between the two ears: the camera housing, or a small gap on a screen
    /// without a notch (the floating panel).
    var earGap: CGFloat { hasPhysicalNotch ? hardware.width : Hud.Space.x3 }
}

private struct CrenelNotchMetricsKey: EnvironmentKey {
    static let defaultValue = CrenelNotchMetrics()
}

private struct CrenelNotchOpenedAtKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var crenelNotchMetrics: CrenelNotchMetrics {
        get { self[CrenelNotchMetricsKey.self] }
        set { self[CrenelNotchMetricsKey.self] = newValue }
    }

    /// When the hosting notch last opened its panel from closed; nil outside a live notch.
    var crenelNotchOpenedAt: Date? {
        get { self[CrenelNotchOpenedAtKey.self] }
        set { self[CrenelNotchOpenedAtKey.self] = newValue }
    }
}

/// The three sizes of the notch (`#nwrap`, `#nwrap.peek`, `#nwrap.open`).
enum CrenelNotchSize: Equatable {
    case compact
    case strip
    case open

    /// Outward flare radius where the notch meets the menu bar.
    var topRadius: CGFloat {
        switch self {
        case .compact: Hud.Notch.topRadius.compact
        case .strip: Hud.Notch.topRadius.strip
        case .open: Hud.Notch.topRadius.open
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .compact: Hud.Notch.bottomRadius.compact
        case .strip: Hud.Notch.bottomRadius.strip
        case .open: Hud.Notch.bottomRadius.open
        }
    }
}

/// The bottom edge of the closed notch as a fuse: how much is left, and how urgent.
struct CrenelNotchFuse: Equatable {
    enum Tone: Equatable {
        case white
        case amber
        case red
        case teal

        var color: Color {
            switch self {
            case .white: Hud.Ink.ink1
            case .amber: Hud.Ink.signal
            case .red: Hud.Ink.live
            case .teal: Hud.Ink.ok
            }
        }
    }

    var fraction: Double
    var tone: Tone = .white
}

/// Reported by the closed content to the shape that hosts it.
struct CrenelNotchClosedTraits: Equatable {
    /// Ears plus one line with buttons. A strip never opens the panel on hover.
    var isStrip = false
    var fuse: CrenelNotchFuse?
}

struct CrenelNotchClosedTraitsKey: PreferenceKey {
    static let defaultValue = CrenelNotchClosedTraits()

    static func reduce(value: inout CrenelNotchClosedTraits, nextValue: () -> CrenelNotchClosedTraits) {
        let next = nextValue()
        if next != defaultValue { value = next }
    }
}

extension View {
    /// Tells the notch shape what the closed content is: a strip, and its fuse.
    func crenelNotchClosedTraits(_ traits: CrenelNotchClosedTraits) -> some View {
        preference(key: CrenelNotchClosedTraitsKey.self, value: traits)
    }
}

@MainActor
final class CrenelNotchModel: ObservableObject {
    enum Presentation: Equatable {
        case hidden
        case compact
        case expanded
    }

    @Published var presentation: Presentation = .hidden
    @Published var metrics = CrenelNotchMetrics()
    /// Bumped to make the compact notch give a small bounce (new information arrived).
    @Published var pulse = 0
    /// The pointer is on the compact notch: it leans in (14×4 pt) before it opens.
    @Published var isApproaching = false
    /// What the closed content last reported: a strip (ears + one line) and a fuse.
    @Published var closedTraits = CrenelNotchClosedTraits()
    /// When the panel last opened from closed. Gauges inside sweep once per open.
    @Published var openedAt: Date?
}

/// Crenel's notch. One borderless panel at the top of the screen hosts a single shape
/// that morphs between the hardware notch, the closed notch with status, and the open
/// panel. Replaces DynamicNotchKit so shape, motion and hit-testing are ours.
@MainActor
final class CrenelNotchController: ObservableObject {
    /// The pointer is on the notch (or its trigger zone).
    @Published private(set) var isHovering = false
    /// Hover that should open the panel or keep it open. A strip holds buttons, so
    /// hovering it never opens the panel; clicking its ears does.
    @Published private(set) var hoverIntent = false
    /// The closed notch was clicked on its ears.
    var onRequestExpand: (() -> Void)?

    let model = CrenelNotchModel()
    private var panel: CrenelNotchPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var shapeFrameInWindow: CGRect = .zero
    private var mouseMonitors: [Any] = []
    private var screen: NSScreen?
    private let expanded: () -> AnyView
    private let compact: () -> AnyView

    /// Maximum panel size. Content smaller than this sizes the shape; the rest of the
    /// window is transparent and lets clicks through.
    static let windowSize = CGSize(width: 860, height: 760)

    init(expanded: @escaping () -> AnyView, compact: @escaping () -> AnyView) {
        self.expanded = expanded
        self.compact = compact
    }

    var availableContentSize: CGSize {
        guard let screen else { return CGSize(width: Hud.Notch.openWidth + 40, height: 560) }
        let frame = windowFrame(on: screen)
        return CGSize(width: frame.width - 48, height: frame.height - model.metrics.topInset - 24)
    }

    // MARK: Presentation

    func expand(on screen: NSScreen) async {
        prepare(on: screen)
        set(.expanded)
    }

    func compact(on screen: NSScreen) async {
        prepare(on: screen)
        set(.compact)
        resignInput()
    }

    func hide() async {
        set(.hidden)
        resignInput()
    }

    /// A small bounce when the closed notch shows something new.
    func pulse() {
        model.pulse &+= 1
    }

    private func set(_ presentation: CrenelNotchModel.Presentation) {
        guard model.presentation != presentation else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if presentation == .expanded { model.openedAt = Date() }
        withAnimation(Crenel.Motion.resolve(Hud.Motion.shape, reduceMotion: reduceMotion)) {
            model.presentation = presentation
            if presentation != .compact {
                model.isApproaching = false
                model.closedTraits = CrenelNotchClosedTraits()
            }
        }
        updateMouseHandling()
    }

    private func resignInput() {
        guard let panel, panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        panel.resignKey()
    }

    // MARK: Window

    private func prepare(on screen: NSScreen) {
        let panel = self.panel ?? makePanel()
        let screenChanged = self.screen.map { !$0.isSame(as: screen) } ?? true
        self.screen = screen
        model.metrics = Self.metrics(for: screen)
        let frame = windowFrame(on: screen)
        if screenChanged || panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        startMouseTracking()
    }

    private func windowFrame(on screen: NSScreen) -> CGRect {
        let size = CGSize(
            width: min(Self.windowSize.width, screen.frame.width),
            height: min(Self.windowSize.height, screen.frame.height * 0.85)
        )
        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func makePanel() -> CrenelNotchPanel {
        let panel = CrenelNotchPanel()
        let root = CrenelNotchRootView(
            model: model,
            expanded: expanded,
            compact: compact,
            onShapeFrameChange: { [weak self] frame in
                self?.shapeFrameInWindow = frame
                self?.updateMouseHandling()
            },
            onClosedTraitsChange: { [weak self] traits in
                guard let self, self.model.closedTraits != traits else { return }
                self.model.closedTraits = traits
                self.updateMouseHandling()
            },
            onRequestExpand: { [weak self] in
                self?.onRequestExpand?()
            }
        )
        let hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    static func metrics(for screen: NSScreen) -> CrenelNotchMetrics {
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = max(0, screen.frame.width - left.width - right.width)
            let height = max(screen.safeAreaInsets.top, menuBarHeight)
            return CrenelNotchMetrics(hardware: CGSize(width: width, height: height), hasPhysicalNotch: true)
        }
        return CrenelNotchMetrics(hardware: CGSize(width: 0, height: menuBarHeight), hasPhysicalNotch: false)
    }

    // MARK: Hover and hit-testing

    private func startMouseTracking() {
        guard mouseMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in self?.updateMouseHandling() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.updateMouseHandling() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    /// The window only takes the mouse inside the visible shape; elsewhere clicks fall
    /// through to the apps below. Hover uses a slightly larger zone so the notch opens
    /// when the pointer reaches the camera housing.
    private func updateMouseHandling() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let shape = screenRect(fromWindowRect: shapeFrameInWindow, in: panel)
        let insideShape = model.presentation != .hidden && shape.contains(mouse)
        // Only on a change: re-setting it on every move makes the window server rebuild
        // the panel's mouse handling and delays SwiftUI's hover inside it.
        if panel.ignoresMouseEvents == insideShape {
            panel.ignoresMouseEvents = !insideShape
        }

        let hoverZone: CGRect
        switch model.presentation {
        case .expanded:
            hoverZone = shape.insetBy(dx: -10, dy: -10)
        case .compact, .hidden:
            hoverZone = shape.union(idleTriggerRect(in: panel)).insetBy(dx: -6, dy: -4)
        }
        let hovering = hoverZone.contains(mouse)
        if hovering != isHovering {
            isHovering = hovering
        }

        let intent = Self.hoverIntent(
            isHovering: hovering,
            presentation: model.presentation,
            isStrip: model.closedTraits.isStrip
        )
        if intent != hoverIntent {
            hoverIntent = intent
        }

        // Approach: the compact notch leans in while the pointer waits on it.
        let approaching = intent && model.presentation == .compact
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if approaching != model.isApproaching {
            withAnimation(Hud.Motion.shape) { model.isApproaching = approaching }
        }
    }

    /// Hovering opens the compact notch and keeps the open panel open. A strip stays a
    /// strip: its buttons need the pointer, so only a click on its ears opens the panel.
    static func hoverIntent(
        isHovering: Bool,
        presentation: CrenelNotchModel.Presentation,
        isStrip: Bool
    ) -> Bool {
        guard isHovering else { return false }
        switch presentation {
        case .expanded, .hidden: return true
        case .compact: return !isStrip
        }
    }

    /// Where the pointer opens the notch even when nothing is shown: the camera housing,
    /// or a band at the top centre on screens without a notch.
    private func idleTriggerRect(in panel: NSWindow) -> CGRect {
        let metrics = model.metrics
        let width = metrics.hasPhysicalNotch ? metrics.hardware.width : 200
        return CGRect(
            x: panel.frame.midX - width / 2,
            y: panel.frame.maxY - metrics.hardware.height,
            width: width,
            height: metrics.hardware.height
        )
    }

    private func screenRect(fromWindowRect rect: CGRect, in window: NSWindow) -> CGRect {
        CGRect(
            x: window.frame.minX + rect.minX,
            y: window.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

/// Borderless, non-activating panel above the menu bar on every Space. It can become key
/// so the task field accepts typing without activating Crenel.
final class CrenelNotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: CrenelNotchController.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    func isSame(as other: NSScreen) -> Bool {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber) == (other.deviceDescription[key] as? NSNumber)
    }
}

// MARK: - Root view

/// Draws the one notch shape and places the current content inside it. The shape's size
/// follows the content: content appears at its final size and the shape grows around it,
/// clipping, which is what makes the transition read as the notch itself changing shape.
///
/// Three sizes: compact (ears), strip (ears + one line) and open (the panel). Width and
/// height spring (0.52 s); content appears after the shape (0.18 s, delayed 0.115 s).
struct CrenelNotchRootView: View {
    @ObservedObject var model: CrenelNotchModel
    let expanded: () -> AnyView
    let compact: () -> AnyView
    let onShapeFrameChange: (CGRect) -> Void
    var onClosedTraitsChange: (CrenelNotchClosedTraits) -> Void = { _ in }
    var onRequestExpand: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactSize: CGSize = .zero
    @State private var expandedSize: CGSize = CGSize(width: Hud.Notch.openWidth, height: 360)
    @State private var closedTraits = CrenelNotchClosedTraits()
    @State private var bounce = false

    var body: some View {
        let metrics = model.metrics
        let notchSize = self.notchSize
        let size = shapeSize(metrics: metrics, notchSize: notchSize)
        let top = notchSize.topRadius
        let bottom = notchSize.bottomRadius

        VStack(spacing: 0) {
            // The flares sit outside the body, so the shape is wider than its content by
            // one top radius on each side (`#nwrap::before`, `::after`).
            CrenelNotchShape(topRadius: top, bottomRadius: bottom)
                .fill(Color.black)
                .frame(width: size.width + 2 * top, height: size.height)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        switch model.presentation {
                        case .expanded:
                            expanded()
                                .fixedSize()
                                .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                                    withAnimation(motion(Hud.Motion.shape)) {
                                        expandedSize = newSize
                                    }
                                }
                                // The shape grows first; content fades in once there is
                                // room for it and leaves quickly so it never outruns the shape.
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(contentAnimation),
                                    removal: .opacity.animation(.easeOut(duration: 0.08))
                                ))
                        case .compact:
                            compact()
                                .fixedSize()
                                .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                                    withAnimation(motion(Hud.Motion.shape)) {
                                        compactSize = newSize
                                    }
                                }
                                .onPreferenceChange(CrenelNotchClosedTraitsKey.self) { traits in
                                    withAnimation(motion(Hud.Motion.shape)) { closedTraits = traits }
                                    onClosedTraitsChange(traits)
                                }
                                // The ears open the panel on click; a strip's buttons sit
                                // below them and keep their own clicks.
                                .overlay(alignment: .top) {
                                    Color.clear
                                        .frame(height: max(metrics.hardware.height, 1))
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onRequestExpand)
                                        .accessibilityElement()
                                        .accessibilityLabel("Open Crenel")
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction(.default, onRequestExpand)
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(contentAnimation),
                                    removal: .opacity.animation(.easeOut(duration: 0.06))
                                ))
                        case .hidden:
                            EmptyView()
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    // The bottom edge as a fuse, between the corner radii.
                    if model.presentation == .compact, let fuse = closedTraits.fuse {
                        HudFuse(fraction: fuse.fraction, color: fuse.tone.color, cornerInset: bottom)
                            .frame(width: size.width)
                            .transition(.opacity.animation(
                                .easeOut(duration: reduceMotion ? 0.01 : 0.4).delay(reduceMotion ? 0 : 0.25)
                            ))
                    }
                }
                .clipShape(CrenelNotchShape(topRadius: top, bottomRadius: bottom))
                .shadow(
                    color: .black.opacity(model.presentation == .expanded ? 0.55 : 0),
                    radius: 24,
                    y: 10
                )
                .opacity(model.presentation == .hidden && !metrics.hasPhysicalNotch ? 0 : 1)
                .scaleEffect(bounce ? 1.04 : 1, anchor: .top)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("notchWindow")) }) { frame in
                    onShapeFrameChange(frame)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named("notchWindow"))
        .environment(\.crenelNotchMetrics, metrics)
        .environment(\.crenelNotchOpenedAt, model.openedAt)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.presentation) { _, presentation in
            guard presentation != .compact, closedTraits != CrenelNotchClosedTraits() else { return }
            closedTraits = CrenelNotchClosedTraits()
        }
        .onChange(of: model.pulse) { _, _ in
            guard !reduceMotion, model.presentation == .compact else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bounce = true }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.7).delay(0.16)) { bounce = false }
        }
    }

    private var notchSize: CrenelNotchSize {
        switch model.presentation {
        case .expanded: .open
        case .compact: closedTraits.isStrip ? .strip : .compact
        case .hidden: .compact
        }
    }

    /// Size of the notch body, without the flares.
    private func shapeSize(metrics: CrenelNotchMetrics, notchSize: CrenelNotchSize) -> CGSize {
        let notch = CGSize(width: max(metrics.hardware.width, metrics.hasPhysicalNotch ? 0 : 120), height: metrics.hardware.height)
        switch model.presentation {
        case .hidden:
            return notch
        case .compact:
            guard compactSize.width > 0 else { return notch }
            // Approach: the compact notch leans in before it opens. A strip never does.
            let lean = model.isApproaching && notchSize == .compact ? Hud.Notch.lean : .zero
            return CGSize(
                width: max(compactSize.width, metrics.hardware.width) + lean.width,
                height: max(compactSize.height, notch.height) + lean.height
            )
        case .expanded:
            return expandedSize
        }
    }

    private var contentAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : Hud.Motion.content
    }

    private func motion(_ animation: Animation) -> Animation {
        Crenel.Motion.resolve(animation, reduceMotion: reduceMotion)
    }
}
