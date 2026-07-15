import AppKit
import DynamicNotchKit
import SwiftUI
import XCTest

@MainActor
final class FloatingPanelIntegrationTests: XCTestCase {
    func testForcedFloatingPanelExpandsAndCompactHidesIt() async throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw XCTSkip("Floating panel testi için kullanılabilir ekran yok.")
        }

        let panel = DynamicNotch(style: .floating) {
            Text("MeetingNotch floating panel doğrulaması")
                .frame(width: 320, height: 180)
        }

        XCTAssertNil(panel.windowController)

        await panel.expand(on: screen)

        let expandedWindow = try XCTUnwrap(panel.windowController?.window)
        XCTAssertTrue(expandedWindow.isVisible)
        XCTAssertEqual(expandedWindow.screen, screen)
        XCTAssertEqual(expandedWindow.frame.midX, screen.frame.midX, accuracy: 1)
        XCTAssertEqual(expandedWindow.frame.maxY, screen.frame.maxY, accuracy: 1)

        await panel.compact(on: screen)

        XCTAssertNil(panel.windowController)
        XCTAssertFalse(expandedWindow.isVisible)
    }

    func testForcedFloatingPanelCanBePresentedAgainAfterItIsHidden() async throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw XCTSkip("Floating panel testi için kullanılabilir ekran yok.")
        }

        let panel = DynamicNotch(style: .floating) {
            Color.clear.frame(width: 320, height: 180)
        }

        await panel.expand(on: screen)
        let firstWindow = try XCTUnwrap(panel.windowController?.window)
        await panel.hide()

        await panel.expand(on: screen)
        let secondWindow = try XCTUnwrap(panel.windowController?.window)

        XCTAssertTrue(secondWindow.isVisible)
        XCTAssertFalse(firstWindow === secondWindow)

        await panel.hide()
        XCTAssertNil(panel.windowController)
    }
}
