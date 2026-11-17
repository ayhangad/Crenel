import AppKit
import SwiftUI
import XCTest
@testable import Crenel

@MainActor
final class CrenelNotchEngineTests: XCTestCase {
    func testNotchShapeStaysFlushWithTopEdgeAndInsideItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 120)
        let path = CrenelNotchShape(topRadius: 12, bottomRadius: 32).path(in: rect)

        XCTAssertEqual(path.boundingRect.minY, 0, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.minX, 0, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.maxX, 400, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.maxY, 120, accuracy: 0.01)
        // The top corners flare outward: the very top row is full width, the wall below
        // it is inset by the flare radius.
        XCTAssertTrue(path.contains(CGPoint(x: 200, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 40)))
        XCTAssertTrue(path.contains(CGPoint(x: 20, y: 40)))
        // Bottom corners are rounded.
        XCTAssertFalse(path.contains(CGPoint(x: 13, y: 119)))
    }

    func testNotchShapeClampsRadiiForTinyFrames() {
        let path = CrenelNotchShape(topRadius: 40, bottomRadius: 80).path(in: CGRect(x: 0, y: 0, width: 60, height: 20))
        XCTAssertFalse(path.isEmpty)
        XCTAssertLessThanOrEqual(path.boundingRect.width, 60.01)
        XCTAssertLessThanOrEqual(path.boundingRect.height, 20.01)
    }

    func testFlankLayoutKeepsGapCentredWhenSidesDiffer() {
        let view = NotchFlankLayout(gap: 180) {
            Color.red.frame(width: 90, height: 20)
            Color.blue.frame(width: 30, height: 20)
        }
        let host = NSHostingView(rootView: view)
        // Both flanks take the wider flank's width.
        XCTAssertEqual(host.fittingSize.width, 90 * 2 + 180, accuracy: 0.5)
        XCTAssertEqual(host.fittingSize.height, 20, accuracy: 0.5)
    }

    func testViewportReservesMenuBarBandAndMargins() {
        let viewport = NotchHostViewport(windowSize: CGSize(width: 860, height: 760), topInset: 38)
        XCTAssertEqual(viewport.availableSize.width, 860 - NotchHostViewport.horizontalMargin)
        XCTAssertEqual(viewport.availableSize.height, 760 - 38 - NotchHostViewport.bottomMargin)
    }

    func testControllerPlacesPanelAtTopCentreAndKeepsItAcrossStates() async throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw XCTSkip("Notch penceresi testi için kullanılabilir ekran yok.")
        }
        let controller = CrenelNotchController(
            expanded: { AnyView(Color.clear.frame(width: 400, height: 200)) },
            compact: { AnyView(Color.clear.frame(width: 200, height: 30)) }
        )

        await controller.compact(on: screen)
        XCTAssertEqual(controller.model.presentation, .compact)
        let window = try XCTUnwrap(NSApp.windows.first { $0 is CrenelNotchPanel && $0.isVisible })
        XCTAssertEqual(window.frame.midX, screen.frame.midX, accuracy: 1)
        XCTAssertEqual(window.frame.maxY, screen.frame.maxY, accuracy: 1)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))

        await controller.expand(on: screen)
        XCTAssertEqual(controller.model.presentation, .expanded)
        XCTAssertTrue(window.isVisible)

        await controller.hide()
        XCTAssertEqual(controller.model.presentation, .hidden)
        window.orderOut(nil)
    }

    func testCompactStatusIdentityIgnoresCountdownTicks() {
        let meeting = Meeting(
            id: UUID(),
            title: "Standup",
            startDate: Date().addingTimeInterval(600),
            endDate: Date().addingTimeInterval(1_800)
        )
        let first = NotchCompactStatus.agenda(NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: 600)))
        let later = NotchCompactStatus.agenda(NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: 540)))
        XCTAssertEqual(first.identity, later.identity)
        XCTAssertNotEqual(first.identity, NotchCompactStatus.idle.identity)
    }

    func testAgendaRingFillsAsEventProgresses() {
        let start = Date()
        let meeting = Meeting(id: UUID(), title: "Plan", startDate: start, endDate: start.addingTimeInterval(3_600))
        let status = NotchAgendaStatus(item: meeting, phase: .ongoing(remaining: 1_800))
        XCTAssertEqual(status.ringProgress(now: start.addingTimeInterval(1_800)), 0.5, accuracy: 0.001)
        let upcoming = NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: 900))
        XCTAssertEqual(upcoming.ringProgress(now: start), 0.75, accuracy: 0.001)
    }
}
