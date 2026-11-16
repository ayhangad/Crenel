import AppKit
import SwiftUI

/// Runs the design proposal live in the real notch position, so motion and hover can
/// be judged on the hardware. Launch with `-CrenelProposal YES`; the regular notch is
/// not shown in this mode.
///
/// Hover opens the panel. While closed, the notch cycles through its states every few
/// seconds (next meeting → recording → dictation → processing → tasks).
@MainActor
final class ProposalPreviewController {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "CrenelProposal") }

    private let panel = CrenelNotchPanel()
    private let model = ProposalNotchModel.sample()
    private var shapeFrame: CGRect = .zero
    private var monitors: [Any] = []
    private var clock: Timer?
    private var meter: Timer?
    private var closeWork: DispatchWorkItem?
    private var cycleIndex = 0
    private var lastCycle = Date()
    private let hardware: CGSize

    init(screen: NSScreen) {
        Hud.registerFonts()
        let metrics = CrenelNotchController.metrics(for: screen)
        hardware = CGSize(width: max(metrics.hardware.width, 190), height: metrics.hardware.height)
        let size = CGSize(width: 720, height: 640)
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: false)
        let root = ProposalNotchView(model: model, hardware: hardware)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [weak self] frame in
                self?.shapeFrame = frame
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
    }

    func show() {
        panel.orderFrontRegardless()
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.trackPointer() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event); return event
        }) {
            monitors.append(local)
        }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        meter = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.animateLevels() }
        }
    }

    private func trackPointer() {
        let point = NSEvent.mouseLocation
        let frame = panel.frame
        // SwiftUI global frames are top-left based inside the window.
        let rect = CGRect(x: frame.minX + shapeFrame.minX, y: frame.maxY - shapeFrame.maxY,
                          width: shapeFrame.width, height: shapeFrame.height).insetBy(dx: -4, dy: -4)
        let inside = rect.contains(point)
        panel.ignoresMouseEvents = !inside
        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !model.isOpen { model.isOpen = true }
        } else if model.isOpen, closeWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.model.isOpen = false
                self?.closeWork = nil
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func tick() {
        model.now = Date()
        guard !model.isOpen, Date().timeIntervalSince(lastCycle) >= 4 else { return }
        lastCycle = Date()
        cycleIndex = (cycleIndex + 1) % 6
        let states: [ProposalCompact] = [
            .nextMeeting, .recording(started: Date().addingTimeInterval(-754)), .dictation,
            .processing(step: 1), .processing(step: 2), .tasks
        ]
        model.compact = states[cycleIndex]
    }

    private func animateLevels() {
        guard !model.isOpen else { return }
        switch model.compact {
        case .recording, .dictation:
            let t = Date().timeIntervalSinceReferenceDate
            model.levels = (0..<5).map { index in
                let wave = (sin(t * 7 + Double(index) * 1.3) + 1) / 2
                return min(1, 0.15 + wave * Double.random(in: 0.4...1.0))
            }
        default:
            break
        }
    }
}
