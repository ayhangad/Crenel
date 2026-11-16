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
}

private struct CrenelNotchMetricsKey: EnvironmentKey {
    static let defaultValue = CrenelNotchMetrics()
}

extension EnvironmentValues {
    var crenelNotchMetrics: CrenelNotchMetrics {
        get { self[CrenelNotchMetricsKey.self] }
        set { self[CrenelNotchMetricsKey.self] = newValue }
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
}

/// Crenel's notch. One borderless panel at the top of the screen hosts a single shape
/// that morphs between the hardware notch, the closed notch with status, and the open
/// panel. Replaces DynamicNotchKit so shape, motion and hit-testing are ours.
@MainActor
final class CrenelNotchController: ObservableObject {
    @Published private(set) var isHovering = false

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
        guard let screen else { return CGSize(width: 600, height: 560) }
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
        withAnimation(Crenel.Motion.resolve(Crenel.Motion.morph, reduceMotion: reduceMotion)) {
            model.presentation = presentation
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
        panel.ignoresMouseEvents = !insideShape

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
struct CrenelNotchRootView: View {
    @ObservedObject var model: CrenelNotchModel
    let expanded: () -> AnyView
    let compact: () -> AnyView
    let onShapeFrameChange: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactSize: CGSize = .zero
    @State private var expandedSize: CGSize = CGSize(width: 600, height: 420)
    @State private var bounce = false

    var body: some View {
        let metrics = model.metrics
        let size = shapeSize(metrics: metrics)
        let radii = shapeRadii(metrics: metrics)

        VStack(spacing: 0) {
            CrenelNotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        switch model.presentation {
                        case .expanded:
                            expanded()
                                .fixedSize()
                                .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                                    expandedSize = newSize
                                }
                                .transition(.crenelMorph(anchor: .top))
                        case .compact:
                            compact()
                                .fixedSize()
                                .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                                    withAnimation(motion(Crenel.Motion.bouncy)) {
                                        compactSize = newSize
                                    }
                                }
                                .transition(.crenelMorph(anchor: .top))
                        case .hidden:
                            EmptyView()
                        }
                    }
                }
                .clipShape(CrenelNotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
                .shadow(
                    color: .black.opacity(model.presentation == .expanded ? 0.55 : 0),
                    radius: 24,
                    y: 10
                )
                .opacity(model.presentation == .hidden && !metrics.hasPhysicalNotch ? 0 : 1)
                .scaleEffect(bounce ? 1.06 : 1, anchor: .top)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("notchWindow")) }) { frame in
                    onShapeFrameChange(frame)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named("notchWindow"))
        .environment(\.crenelNotchMetrics, metrics)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.pulse) { _, _ in
            guard !reduceMotion, model.presentation == .compact else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bounce = true }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.7).delay(0.16)) { bounce = false }
        }
    }

    private func shapeSize(metrics: CrenelNotchMetrics) -> CGSize {
        let notch = CGSize(width: max(metrics.hardware.width, metrics.hasPhysicalNotch ? 0 : 120), height: metrics.hardware.height)
        switch model.presentation {
        case .hidden:
            return notch
        case .compact:
            guard compactSize.width > 0 else { return notch }
            return CGSize(width: max(compactSize.width, metrics.hardware.width), height: max(compactSize.height, notch.height))
        case .expanded:
            return expandedSize
        }
    }

    private func shapeRadii(metrics: CrenelNotchMetrics) -> (top: CGFloat, bottom: CGFloat) {
        switch model.presentation {
        case .hidden, .compact:
            (6, max(8, metrics.hardware.height * 0.36))
        case .expanded:
            (12, Crenel.Radius.notch)
        }
    }

    private func motion(_ animation: Animation) -> Animation {
        Crenel.Motion.resolve(animation, reduceMotion: reduceMotion)
    }
}
