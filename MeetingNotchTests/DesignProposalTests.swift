import AppKit
import SwiftUI
import XCTest
@testable import MeetingNotch

/// Renders the design proposal (open panel and closed-notch states) for review.
/// PNGs go to `artifacts/ui-audit/proposal/` when `/tmp/MeetingNotchExportUIAudit` exists.
@MainActor
final class DesignProposalTests: XCTestCase {
    private let hardware = CGSize(width: 190, height: 32)

    override func setUp() {
        super.setUp()
        Hud.registerFonts()
    }

    func testProposalRenders() throws {
        let now = date(hour: 14, minute: 52)

        let near = ProposalNotchModel.sample(now: now, isOpen: true)
        near.forcedHover = near.events[1].id
        try export(scene(near), name: "today-near")

        let live = ProposalNotchModel.sample(now: now, isOpen: true)
        live.now = now.addingTimeInterval(20 * 60)
        try export(scene(live), name: "today-live")

        let quiet = ProposalNotchModel.sample(now: date(hour: 18, minute: 53), isOpen: true)
        quiet.events = [
            ProposalEvent(title: "Edda Dev. Sync", start: date(hour: 18, minute: 0, day: 1), end: date(hour: 18, minute: 30, day: 1), venue: .online("Google Meet")),
            ProposalEvent(title: "BB Dev. Sync", start: date(hour: 18, minute: 30, day: 1), end: date(hour: 19, minute: 0, day: 1), venue: .online("Zoom")),
            ProposalEvent(title: "Selin ile 1:1", start: date(hour: 10, minute: 0, day: 2), end: date(hour: 10, minute: 30, day: 2))
        ]
        try export(scene(quiet), name: "today-quiet")

        let tasks = ProposalNotchModel.sample(now: now, isOpen: true)
        tasks.tab = .tasks
        tasks.staticInput = ""
        try export(scene(tasks), name: "tasks")

        let typing = ProposalNotchModel.sample(now: now, isOpen: true)
        typing.tab = .tasks
        typing.staticInput = "Tasarım dosyalarını gönder yarın 10:00 !!"
        try export(scene(typing), name: "tasks-typing")

        let completing = ProposalNotchModel.sample(now: now, isOpen: true)
        completing.tab = .tasks
        completing.staticInput = "Fat"
        try export(scene(completing), name: "tasks-completion")

        let states: [ProposalCompact] = [
            .nextMeeting, .recording(started: now.addingTimeInterval(-754)), .dictation, .processing(step: 2), .tasks
        ]
        let models = states.map { state -> ProposalNotchModel in
            let model = ProposalNotchModel.sample(now: now)
            model.compact = state
            return model
        }
        let hardware = self.hardware
        let menuBar = self.menuBar
        let strip = VStack(spacing: 20) {
            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                ZStack(alignment: .top) {
                    menuBar
                    ProposalNotchView(model: model, hardware: hardware)
                }
                .frame(width: 600, height: hardware.height)
            }
        }
        .padding(.vertical, 28)
        .background(backdrop)
        try export(AnyView(strip), name: "compact-states")
    }

    // MARK: Scene

    private func scene(_ model: ProposalNotchModel) -> AnyView {
        AnyView(
            ZStack(alignment: .top) {
                menuBar
                ProposalNotchView(model: model, hardware: hardware)
            }
            .frame(width: 680, alignment: .top)
            .padding(.bottom, 56)
            .background(backdrop)
        )
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color(white: 0.42), Color(white: 0.26)], startPoint: .top, endPoint: .bottom)
    }

    private var menuBar: some View {
        Rectangle().fill(Color(white: 0, opacity: 0.22)).frame(height: hardware.height)
    }

    // MARK: Helpers

    private func date(hour: Int, minute: Int, day: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_794_700_000))
        let shifted = calendar.date(byAdding: .day, value: day, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted)!
    }

    private func export(_ view: AnyView, name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        guard FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit"),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/proposal/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: path)
    }
}
