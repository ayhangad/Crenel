import CoreGraphics
import XCTest
@testable import MeetingNotch

final class NotchScreenResolverTests: XCTestCase {
    private let builtIn = NotchScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        hasNotch: true,
        isMain: true
    )
    private let external = NotchScreenDescriptor(
        id: 2,
        frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
        hasNotch: false,
        isMain: false
    )

    func testStartupPrefersMainPhysicalNotch() {
        let result = NotchScreenSelectionPolicy.startupScreen(from: [external, builtIn])

        XCTAssertEqual(result, builtIn)
    }

    func testStartupUsesNotchedScreenBeforeNotchlessMainScreen() {
        let notchlessMain = NotchScreenDescriptor(
            id: external.id,
            frame: external.frame,
            hasNotch: false,
            isMain: true
        )
        let secondaryNotch = NotchScreenDescriptor(
            id: builtIn.id,
            frame: builtIn.frame,
            hasNotch: true,
            isMain: false
        )

        let result = NotchScreenSelectionPolicy.startupScreen(from: [notchlessMain, secondaryNotch])

        XCTAssertEqual(result, secondaryNotch)
    }

    func testPresentationFollowsPointerToExternalScreen() {
        let result = NotchScreenSelectionPolicy.presentationScreen(
            from: [builtIn, external],
            pointerLocation: CGPoint(x: 2_000, y: 500)
        )

        XCTAssertEqual(result, external)
    }

    func testPresentationFallsBackToStartupPolicyWhenPointerIsOutsideScreens() {
        let result = NotchScreenSelectionPolicy.presentationScreen(
            from: [external, builtIn],
            pointerLocation: CGPoint(x: -2_000, y: -2_000)
        )

        XCTAssertEqual(result, builtIn)
    }

    func testNotchlessOnlySetupStillReturnsMainScreenForFloatingFallback() {
        let notchlessMain = NotchScreenDescriptor(
            id: external.id,
            frame: external.frame,
            hasNotch: false,
            isMain: true
        )

        XCTAssertEqual(
            NotchScreenSelectionPolicy.startupScreen(from: [notchlessMain]),
            notchlessMain
        )
    }

    func testStartupPolicySupportsCommonNotchedMacBookGeometries() {
        let commonMacBookScreens = [
            NotchScreenDescriptor(
                id: 13,
                frame: CGRect(x: 0, y: 0, width: 1_470, height: 956),
                hasNotch: true,
                isMain: true
            ),
            NotchScreenDescriptor(
                id: 14,
                frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                hasNotch: true,
                isMain: true
            ),
            NotchScreenDescriptor(
                id: 15,
                frame: CGRect(x: 0, y: 0, width: 1_710, height: 1_107),
                hasNotch: true,
                isMain: true
            ),
            NotchScreenDescriptor(
                id: 16,
                frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
                hasNotch: true,
                isMain: true
            ),
        ]

        for screen in commonMacBookScreens {
            XCTAssertEqual(
                NotchScreenSelectionPolicy.startupScreen(from: [external, screen]),
                screen,
                "Notched MacBook geometry \(screen.frame.size) should be selected"
            )
        }
    }

    func testPresentationSupportsExternalDisplayWithNegativeOrigin() {
        let leftExternal = NotchScreenDescriptor(
            id: 3,
            frame: CGRect(x: -1_920, y: -98, width: 1_920, height: 1_080),
            hasNotch: false,
            isMain: false
        )

        let result = NotchScreenSelectionPolicy.presentationScreen(
            from: [builtIn, leftExternal],
            pointerLocation: CGPoint(x: -960, y: 400)
        )

        XCTAssertEqual(result, leftExternal)
    }

    func testEmptyScreenListDoesNotProduceAnInvalidSelection() {
        XCTAssertNil(NotchScreenSelectionPolicy.startupScreen(from: []))
        XCTAssertNil(
            NotchScreenSelectionPolicy.presentationScreen(
                from: [],
                pointerLocation: .zero
            )
        )
    }
}
