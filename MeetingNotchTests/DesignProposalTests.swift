import AppKit
import SwiftUI
import XCTest
@testable import MeetingNotch

/// Renders the design proposal (Today surface and closed-notch states) for review.
/// PNGs go to `artifacts/ui-audit/proposal/` when `/tmp/MeetingNotchExportUIAudit` exists.
@MainActor
final class DesignProposalTests: XCTestCase {
    private let hardware = CGSize(width: 190, height: 32)
    private let panelWidth: CGFloat = 480

    override func setUp() {
        super.setUp()
        Hud.registerFonts()
    }

    func testTodayProposalRenders() throws {
        let base = date(hour: 14, minute: 52)
        let near = TodayProposalModel(
            now: base,
            events: [
                .init(title: "Ürün haftalık senkron", start: date(hour: 15, minute: 0), end: date(hour: 15, minute: 45), hasLink: true),
                .init(title: "Tasarım incelemesi", start: date(hour: 16, minute: 30), end: date(hour: 17, minute: 30), place: "Oda 2"),
                .init(title: "Edda Dev. Sync", start: date(hour: 18, minute: 0, dayOffset: 1), end: date(hour: 18, minute: 30, dayOffset: 1), hasLink: true),
                .init(title: "BB Dev. Sync", start: date(hour: 18, minute: 30, dayOffset: 1), end: date(hour: 19, minute: 0, dayOffset: 1), hasLink: true),
                .init(title: "Selin ile 1:1", start: date(hour: 10, minute: 0, dayOffset: 2), end: date(hour: 10, minute: 30, dayOffset: 2), hasLink: true)
            ],
            taskCount: 3,
            hoveredTitle: "Tasarım incelemesi"
        )
        try export(panel(near), name: "today-near")

        let quiet = TodayProposalModel(
            now: date(hour: 18, minute: 53),
            events: [
                .init(title: "Edda Dev. Sync", start: date(hour: 18, minute: 0, dayOffset: 1), end: date(hour: 18, minute: 30, dayOffset: 1), hasLink: true),
                .init(title: "BB Dev. Sync", start: date(hour: 18, minute: 30, dayOffset: 1), end: date(hour: 19, minute: 0, dayOffset: 1), hasLink: true),
                .init(title: "Selin ile 1:1", start: date(hour: 10, minute: 0, dayOffset: 2), end: date(hour: 10, minute: 30, dayOffset: 2), hasLink: true)
            ],
            taskCount: 3
        )
        try export(panel(quiet), name: "today-quiet")

        let live = TodayProposalModel(
            now: date(hour: 15, minute: 12),
            events: near.events,
            taskCount: 3
        )
        try export(panel(live), name: "today-live")

        let states: [CompactProposalView.State] = [
            .nextMeeting(time: "15:00", minutes: 8),
            .recording(elapsed: "12:34", levels: [0.4, 0.9, 0.6, 0.3, 0.7]),
            .dictation(levels: [0.2, 0.6, 1.0, 0.5, 0.25]),
            .processing(step: "özet", lit: 3),
            .tasks(count: 3)
        ]
        let hardware = self.hardware
        let menuBar = self.menuBar
        let cameraHint = self.cameraHint
        let strip = VStack(spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                ZStack(alignment: .top) {
                    menuBar
                    CompactProposalView(state: state, hardware: hardware)
                                                .background(CrenelNotchShape(topRadius: 6, bottomRadius: 12).fill(Color.black))
                        .overlay(alignment: .top) { cameraHint }
                }
                .frame(width: 560, height: hardware.height)
            }
        }
        .padding(.vertical, 24)
        .background(backdrop)
        try export(AnyView(strip), name: "compact-states")
    }

    // MARK: Scene

    private func panel(_ model: TodayProposalModel) -> AnyView {
        AnyView(
            ZStack(alignment: .top) {
                menuBar
                TodayProposalView(model: model, hardware: hardware)
                    .frame(width: panelWidth)
                    .background(CrenelNotchShape(topRadius: 10, bottomRadius: 24).fill(Color.black))
                    .overlay(alignment: .top) { cameraHint }
            }
            .frame(width: 640, alignment: .top)
            .padding(.bottom, 48)
            .background(backdrop)
        )
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color(red: 0.36, green: 0.38, blue: 0.44), Color(red: 0.22, green: 0.23, blue: 0.28)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var menuBar: some View {
        Rectangle().fill(Color(white: 0, opacity: 0.22)).frame(height: hardware.height)
    }

    /// Faint outline of where the camera housing sits, for review only.
    private var cameraHint: some View {
        RoundedRectangle(cornerRadius: 8).stroke(Color(white: 1, opacity: 0.06), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .frame(width: hardware.width, height: hardware.height - 2)
    }

    // MARK: Helpers

    private func date(hour: Int, minute: Int, dayOffset: Int = 0) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: 1_794_700_000))
        components.hour = hour
        components.minute = minute
        let day = calendar.date(from: components)!
        return calendar.date(byAdding: .day, value: dayOffset, to: day)!
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
