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
