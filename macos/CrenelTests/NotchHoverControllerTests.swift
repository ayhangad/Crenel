import XCTest
@testable import Crenel

@MainActor
final class NotchHoverControllerTests: XCTestCase {
    func testBriefHoverDoesNotExpand() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe, expansionDelay: .milliseconds(40))

        controller.update(isHovering: true)
        controller.update(isHovering: false)
        try await Task.sleep(for: .milliseconds(70))

        XCTAssertEqual(probe.expansionCount, 0)
        XCTAssertEqual(controller.presentationState, .compact)
    }

    func testSustainedHoverExpands() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe)

        controller.update(isHovering: true)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(probe.expansionCount, 1)
        XCTAssertEqual(controller.presentationState, .expanded)
    }

    func testReturningToPanelCancelsDelayedCompaction() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe, compactionDelay: .milliseconds(50))
        controller.markExpanded()

        controller.update(isHovering: false)
        try await Task.sleep(for: .milliseconds(15))
        controller.update(isHovering: true)
        try await Task.sleep(for: .milliseconds(70))

        XCTAssertEqual(probe.compactionCount, 0)
        XCTAssertEqual(controller.presentationState, .expanded)
    }

    func testLeavingExpandedPanelCompactsAfterDelay() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe)
        controller.markExpanded()

        controller.update(isHovering: false)
        try await Task.sleep(for: .milliseconds(35))

        XCTAssertEqual(probe.compactionCount, 1)
        XCTAssertEqual(controller.presentationState, .compact)
    }

    func testPanelStaysOpenWhenPointerIsStillOnItAtCloseTime() async throws {
        // A fast move onto the panel can be reported as leaving while the shape settles;
        // the pointer is checked again before closing.
        let probe = NotchTransitionProbe()
        let controller = NotchHoverController(
            expansionDelay: .milliseconds(10),
            compactionDelay: .milliseconds(10),
            onExpand: { probe.expansionCount += 1 },
            onCompact: { probe.compactionCount += 1 },
            isStillHovering: { true }
        )
        controller.markExpanded()

        controller.update(isHovering: false)
        try await Task.sleep(for: .milliseconds(35))

        XCTAssertEqual(probe.compactionCount, 0)
        XCTAssertEqual(controller.presentationState, .expanded)
    }

    func testPinnedPanelDoesNotCompactWhenPointerLeaves() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe)
        controller.markExpanded()
        controller.setPinned(true, isHovering: true)

        controller.update(isHovering: false)
        try await Task.sleep(for: .milliseconds(35))

        XCTAssertEqual(probe.compactionCount, 0)
        XCTAssertEqual(controller.presentationState, .expanded)
    }

    func testUnpinningAwayFromPanelCompactsAfterDelay() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe)
        controller.markExpanded()
        controller.setPinned(true, isHovering: false)

        controller.setPinned(false)
        try await Task.sleep(for: .milliseconds(35))

        XCTAssertEqual(probe.compactionCount, 1)
        XCTAssertEqual(controller.presentationState, .compact)
    }

    func testPanelCanCompleteRepeatedOpenCloseCycles() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe)

        for cycle in 1...3 {
            controller.update(isHovering: true)
            try await Task.sleep(for: .milliseconds(25))
            XCTAssertEqual(controller.presentationState, .expanded)
            XCTAssertEqual(probe.expansionCount, cycle)

            controller.update(isHovering: false)
            try await Task.sleep(for: .milliseconds(25))
            XCTAssertEqual(controller.presentationState, .compact)
            XCTAssertEqual(probe.compactionCount, cycle)
        }
    }

    func testCancelPreventsPendingExpansion() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(
            probe: probe,
            expansionDelay: .milliseconds(40)
        )

        controller.update(isHovering: true)
        controller.cancel()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(probe.expansionCount, 0)
        XCTAssertEqual(controller.presentationState, .compact)
    }

    func testExpandedHoverRetainsListAreaAcrossPermanentLayoutShrink() {
        let tall = CGRect(x: 80, y: 0, width: 500, height: 645)
        let short = CGRect(x: 80, y: 0, width: 500, height: 408)
        let retained = CrenelNotchController.expandedHoverBounds(previous: tall, current: short)
        XCTAssertTrue(retained.contains(CGPoint(x: 150, y: 610)))
        XCTAssertFalse(retained.contains(CGPoint(x: 150, y: 680)))
        XCTAssertEqual(CrenelNotchController.expandedHoverBounds(previous: .null, current: short), short)
    }

    func testStationaryPointerIsResampledBeforeCompaction() async throws {
        let probe = NotchTransitionProbe()
        let controller = makeController(probe: probe, compactionDelay: .milliseconds(100))
        controller.markExpanded()
        controller.update(isHovering: false)
        let pointer = CGPoint(x: 150, y: 610)
        let retained = CrenelNotchController.expandedHoverBounds(
            previous: CGRect(x: 80, y: 0, width: 500, height: 645),
            current: CGRect(x: 80, y: 0, width: 500, height: 408))
        var samples = 0
        let polling = CrenelNotchController.pollExpandedHover(interval: .milliseconds(10)) {
            samples += 1
            controller.update(isHovering: retained.contains(pointer))
            return samples < 2
        }
        await polling.value
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(controller.presentationState, .expanded)
        XCTAssertEqual(probe.compactionCount, 0)
    }

    private func makeController(
        probe: NotchTransitionProbe,
        expansionDelay: Duration = .milliseconds(10),
        compactionDelay: Duration = .milliseconds(10)
    ) -> NotchHoverController {
        NotchHoverController(
            expansionDelay: expansionDelay,
            compactionDelay: compactionDelay,
            onExpand: { probe.expansionCount += 1 },
            onCompact: { probe.compactionCount += 1 }
        )
    }
}

@MainActor
private final class NotchTransitionProbe {
    var expansionCount = 0
    var compactionCount = 0
}
