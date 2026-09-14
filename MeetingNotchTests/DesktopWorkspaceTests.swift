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
        XCTAssertGreaterThanOrEqual(controller.window?.minSize.width ?? 0, 1000)
        XCTAssertGreaterThanOrEqual(controller.window?.minSize.height ?? 0, 620)
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
            .environmentObject(delegate.appState)), name: "meetings", size: CGSize(width: 1180, height: 740))
        navigation.section = .tasks
        try render(AnyView(DesktopWorkspaceView(delegate: delegate, navigation: navigation)
            .environmentObject(delegate.appState)), name: "tasks", size: CGSize(width: 1180, height: 740))
        for category in SettingsCategory.allCases {
            try render(AnyView(SettingsView(initialCategory: category).environmentObject(AppState())),
                name: "settings-\(category.id)", size: CGSize(width: 786, height: 580))
        }
    }

    @MainActor
    private func render(_ view: AnyView, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view)
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
