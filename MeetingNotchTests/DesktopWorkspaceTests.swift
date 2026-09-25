import AppKit
import SwiftUI
import XCTest
@testable import MeetingNotch

final class DesktopWorkspaceTests: XCTestCase {
    func testMeetingSearchTrimsWhitespaceAndKeepsOrder() {
        let first = meeting("Ürün değerlendirmesi")
        let second = meeting("Tasarım görüşmesi")
        XCTAssertEqual(DesktopMeetingSearch.filter([first, second], query: "  ürün  ").map(\.id), [first.id])
        XCTAssertEqual(DesktopMeetingSearch.filter([first, second], query: "  ").map(\.id), [first.id, second.id])
        XCTAssertTrue(DesktopMeetingSearch.filter([first, second], query: "olmayan").isEmpty)
    }

    @MainActor
    func testWorkspaceIsNotVisibleUntilExplicitlyOpenedAndClosingDoesNotQuit() {
        let delegate = AppDelegate()
        let controller = DesktopWindowController(delegate: delegate)
        XCTAssertFalse(controller.window?.isVisible ?? true)
        XCTAssertFalse(controller.navigation.isVisible)
        XCTAssertEqual(controller.navigation.section, .meetings)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        XCTAssertEqual(controller.window?.contentMinSize.width, 960)
        XCTAssertEqual(controller.window?.contentMinSize.height, 540)
        guard let window = controller.window else { return XCTFail("Window missing") }
        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 1120, height: 680))
        window.setContentSize(NSSize(width: 960, height: 540))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 960, height: 540))
    }

    @MainActor
    func testDesktopAndEverySettingsCategoryRenderAtMinimumSize() throws {
        let delegate = AppDelegate()
        delegate.appState.replaceStoredMeetings([
            meeting("Ürün stratejisi ve gelecek adımlar"),
            meeting("Tasarım değerlendirmesi"),
            meeting("Haftalık ekip toplantısı")
        ])
        delegate.appState.replaceTasks([
            TaskItem(title: "Teklif dosyasını paylaş", status: .todo, assignee: "Ayşe"),
            TaskItem(title: "Yeni onboarding tasarımını tamamla", status: .inProgress, assignee: "Deniz")
        ])
        let navigation = DesktopNavigation()
        try render(AnyView(DesktopWorkspaceView(delegate: delegate, navigation: navigation)
            .environmentObject(delegate.appState)), name: "meetings", size: CGSize(width: 960, height: 540))
        navigation.section = .tasks
        try render(AnyView(DesktopWorkspaceView(delegate: delegate, navigation: navigation)
            .environmentObject(delegate.appState)), name: "tasks", size: CGSize(width: 960, height: 540))
        for category in SettingsCategory.allCases {
            try render(AnyView(SettingsView(initialCategory: category).environmentObject(AppState())),
                name: "settings-\(category.id)", size: CGSize(width: 754, height: 500))
        }
    }

    @MainActor
    private func render(_ view: AnyView, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view)
        // The audit owns the viewport; prevent hosting-view ideal sizing from resizing the window.
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertLessThanOrEqual(host.fittingSize.width, size.width + 1, "\(name) yatay taşmamalı")
        if FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit") {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let path = root.appending(path: "artifacts/ui-audit/desktop-\(name).png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
        }
    }

    private func meeting(_ title: String) -> StoredMeeting {
        StoredMeeting(id: UUID(), title: title, startedAt: Date(timeIntervalSince1970: 1789380000),
            endedAt: Date(timeIntervalSince1970: 1789383600), sourceMeeting: nil,
            audioFileName: "fixture.m4a", processingStatus: .completed)
    }
}
