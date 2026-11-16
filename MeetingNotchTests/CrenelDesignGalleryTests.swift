import AppKit
import SwiftUI
import XCTest
@testable import MeetingNotch

/// Renders the notch surfaces inside the real notch shape. Always checks that each scene
/// lays out without overflow; writes PNGs to `artifacts/ui-audit/crenel/` when
/// `/tmp/MeetingNotchExportUIAudit` exists, for design review.
@MainActor
final class CrenelDesignGalleryTests: XCTestCase {
    private let metrics = CrenelNotchMetrics(hardware: CGSize(width: 190, height: 32), hasPhysicalNotch: true)

    func testGalleryRendersEverySurface() throws {
        let now = Date()

        let today = sampleState(now: now)
        try render(expanded: AnyView(NotchPanelView().environmentObject(today)), name: "expanded-today")

        let tasks = sampleState(now: now)
        tasks.selectedTab = .tasks
        try render(expanded: AnyView(NotchPanelView().environmentObject(tasks)), name: "expanded-tasks")

        let recording = sampleState(now: now, flow: .recording(startedAt: now.addingTimeInterval(-754)))
        try render(expanded: AnyView(NotchPanelView().environmentObject(recording)), name: "expanded-recording")

        let compactCases: [(String, AppState)] = [
            ("agenda", sampleState(now: now)),
            ("recording", sampleState(now: now, flow: .recording(startedAt: now.addingTimeInterval(-83)))),
            ("dictation", {
                let state = sampleState(now: now)
                state.updateDictationState(.listening(startedAt: now, level: 0.6))
                state.updateDictationLevel(0.6)
                return state
            }()),
            ("idle", AppState())
        ]
        for (name, state) in compactCases {
            try render(compact: AnyView(CrenelCompactView().environmentObject(state)), name: "compact-\(name)")
        }

        try renderPlain(AnyView(OnboardingView(setup: .preview(), onComplete: {}, initialStep: .setup)),
                        name: "onboarding-setup", size: CGSize(width: 560, height: 680))

        try renderPlain(AnyView(
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ForEach(CrenelGlyph.allCases, id: \.self) { glyph in
                        CrenelIcon(glyph, size: 18).foregroundStyle(Crenel.Palette.textPrimary)
                    }
                }
                HStack(spacing: 18) {
                    ForEach(TaskStatus.allCases) { status in
                        TaskStateGlyph(status: status, size: 22)
                    }
                    TaskStatePicker(current: .inProgress) { _ in }
                }
                HStack(spacing: 10) {
                    Button("Birincil") {}.buttonStyle(CrenelButtonStyle(kind: .primary))
                    Button("İkincil") {}.buttonStyle(CrenelButtonStyle(kind: .secondary))
                    Button("Katıl") {}.buttonStyle(CrenelButtonStyle(kind: .accent(Crenel.Palette.calendar)))
                    Button("Kaydet") {}.buttonStyle(CrenelButtonStyle(kind: .tinted(Crenel.Palette.record)))
                    CrenelChip(title: "12 dk", glyph: .clock, tint: Crenel.Palette.calendar)
                    CrenelKeyCap(label: "⌥ Space")
                    CrenelProgressRing(progress: 0.62, tint: Crenel.Palette.calendar).frame(width: 28, height: 28)
                }
            }
            .padding(24)
            .background(Color.black)
        ), name: "system", size: CGSize(width: 900, height: 160))
    }

    /// Shaders only run through SwiftUI's own renderer, so living visuals are captured
    /// with ImageRenderer.
    func testShaderVisualsRender() throws {
        let view = HStack(spacing: 24) {
            CrenelOrb(top: .white, bottom: Crenel.Palette.record, level: 0.3, density: 16).frame(width: 160, height: 160)
            CrenelOrb(top: .white, bottom: Crenel.Palette.dictation, level: 0.8, density: 9).frame(width: 60, height: 60)
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Crenel.Palette.layer1)
                CrenelAura(tint: Crenel.Palette.calendar, intensity: 0.75).clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .frame(width: 250, height: 200)
            Text("Yazıya çevriliyor").font(.system(size: 22, weight: .semibold)).foregroundStyle(Crenel.Palette.dictation).crenelShimmer()
        }
        .padding(24)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        if FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit"),
           let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let path = root.appending(path: "artifacts/ui-audit/crenel/shaders.png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: path)
        }
    }

    // MARK: Fixtures

    private func sampleState(now: Date, flow: MeetingFlowState = .idle) -> AppState {
        let state = AppState(initialFlow: flow)
        state.updateNotchPanelAvailableSize(CGSize(width: 812, height: 640))
        state.updateCalendarAccessState(.authorized)
        state.updateUpcomingMeetings([
            Meeting(title: "Ürün haftalık senkron", startDate: now.addingTimeInterval(12 * 60),
                    endDate: now.addingTimeInterval(57 * 60), meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                    kind: .onlineMeeting, calendarTitle: "İş", calendarColorHex: "#8F80FF"),
            Meeting(title: "Tasarım incelemesi", startDate: now.addingTimeInterval(2 * 3_600),
                    endDate: now.addingTimeInterval(3 * 3_600), kind: .meeting, location: "Toplantı odası 2"),
            Meeting(title: "Spor salonu", startDate: now.addingTimeInterval(5 * 3_600),
                    endDate: now.addingTimeInterval(6 * 3_600), kind: .event, calendarTitle: "Kişisel")
        ])
        let start = Calendar.current.startOfDay(for: now)
        var done = TaskItem(title: "Sprint notlarını paylaş", createdAt: now)
        done.setStatus(.completed, at: now)
        state.replaceTasks([
            TaskItem(title: "Onboarding akışını bitir", createdAt: now, status: .inProgress, startedAt: now.addingTimeInterval(-1_800), priority: .high),
            TaskItem(title: "Hukuk onayı bekleniyor", createdAt: now, status: .blocked, dueDate: start),
            TaskItem(title: "Haftalık raporu yaz", createdAt: now, dueDate: now.addingTimeInterval(3 * 3_600), dueHasTime: true, priority: .medium),
            TaskItem(title: "Annemi ara", createdAt: now, dueDate: start),
            TaskItem(title: "Kitap listesi", createdAt: now),
            done
        ])
        state.updateTaskStorageStatus(.reminders(listTitle: "Crenel"))
        return state
    }

    // MARK: Rendering

    private func render(expanded content: AnyView, name: String) throws {
        let model = CrenelNotchModel()
        model.metrics = metrics
        model.presentation = .expanded
        try renderRoot(model: model, expanded: content, compact: AnyView(EmptyView()), name: name, size: CGSize(width: 860, height: 760))
    }

    private func render(compact content: AnyView, name: String) throws {
        let model = CrenelNotchModel()
        model.metrics = metrics
        model.presentation = .compact
        try renderRoot(model: model, expanded: AnyView(EmptyView()), compact: content, name: name, size: CGSize(width: 560, height: 60))
    }

    private func renderRoot(model: CrenelNotchModel, expanded: AnyView, compact: AnyView, name: String, size: CGSize) throws {
        let root = CrenelNotchRootView(model: model, expanded: { expanded }, compact: { compact }, onShapeFrameChange: { _ in })
            .background(Color(white: 0.32))
        try renderPlain(AnyView(root), name: name, size: size)
    }

    private func renderPlain(_ view: AnyView, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view.environment(\.crenelNotchMetrics, metrics))
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit") {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let path = root.appending(path: "artifacts/ui-audit/crenel/\(name).png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
        }
    }
}
