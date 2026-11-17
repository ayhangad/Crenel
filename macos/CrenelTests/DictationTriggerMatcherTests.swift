import CoreGraphics
import XCTest
@testable import Crenel

final class DictationTriggerMatcherTests: XCTestCase {
    private func flags(_ keyCode: UInt16, _ modifiers: DictationModifierFlags, at time: TimeInterval) -> DictationKeyEvent {
        DictationKeyEvent(kind: .flagsChanged, keyCode: keyCode, modifiers: modifiers, timestamp: time)
    }

    private func keyDown(_ keyCode: UInt16, _ modifiers: DictationModifierFlags = [], repeat isRepeat: Bool = false, at time: TimeInterval) -> DictationKeyEvent {
        DictationKeyEvent(kind: .keyDown, keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, timestamp: time)
    }

    private func keyUp(_ keyCode: UInt16, _ modifiers: DictationModifierFlags = [], at time: TimeInterval) -> DictationKeyEvent {
        DictationKeyEvent(kind: .keyUp, keyCode: keyCode, modifiers: modifiers, timestamp: time)
    }

    private let fn = DictationKeyCode.function

    func testDefaultSettingsAreFnHoldToTalk() throws {
        XCTAssertEqual(DictationTriggerSettings.default.trigger, .fnHold)
        XCTAssertEqual(DictationTriggerSettings.default.mode, .holdToTalk)

        let custom = DictationTriggerSettings(trigger: .shortcut(keyCode: 49, modifiers: [.control, .option]), mode: .toggle)
        let data = try JSONEncoder().encode(custom)
        XCTAssertEqual(try JSONDecoder().decode(DictationTriggerSettings.self, from: data), custom)
    }

    func testFnHoldBeginsAndEnds() {
        var matcher = DictationTriggerMatcher()
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        XCTAssertNil(matcher.handle(flags(fn, .function, at: 0.1)), "Duplicate down is ignored")
        XCTAssertEqual(matcher.handle(flags(fn, [], at: 1.0)), .ended)
        XCTAssertFalse(matcher.isSessionActive)
    }

    func testGlobeKeyCodeIsAccepted() {
        var matcher = DictationTriggerMatcher()
        XCTAssertEqual(matcher.handle(flags(DictationKeyCode.globe, .function, at: 0)), .began)
        XCTAssertEqual(matcher.handle(flags(DictationKeyCode.globe, [], at: 1)), .ended)
    }

    func testFnPressedWithOtherModifierIsIgnoredAsChord() {
        var matcher = DictationTriggerMatcher()
        XCTAssertNil(matcher.handle(flags(fn, [.function, .control], at: 0)))
        XCTAssertNil(matcher.handle(flags(fn, [.control], at: 0.5)))
        XCTAssertEqual(matcher.phase, .idle)
    }

    func testOtherKeyDuringHoldCancelsAndSuppressesUntilRelease() {
        var matcher = DictationTriggerMatcher()
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        // Fn + Left arrow is a system shortcut.
        XCTAssertEqual(matcher.handle(keyDown(0x7B, .function, at: 0.4)), .cancelled)
        XCTAssertNil(matcher.handle(keyUp(0x7B, .function, at: 0.5)))
        XCTAssertNil(matcher.handle(flags(fn, [], at: 0.8)), "Release after chord emits nothing")
        XCTAssertEqual(matcher.phase, .idle)
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 2)), .began)
    }

    func testAddingModifierDuringHoldCancels() {
        var matcher = DictationTriggerMatcher()
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        XCTAssertEqual(matcher.handle(flags(0x37, [.function, .command], at: 0.3)), .cancelled)
    }

    func testEscapeCancelsActiveSession() {
        var matcher = DictationTriggerMatcher()
        XCTAssertNil(matcher.handle(keyDown(DictationKeyCode.escape, at: 0)), "Esc does nothing while idle")
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        XCTAssertEqual(matcher.handle(keyDown(DictationKeyCode.escape, .function, at: 0.5)), .cancelled)
        XCTAssertNil(matcher.handle(flags(fn, [], at: 1)))
    }

    func testDoubleTapFnStartsHandsFreeUntilNextPress() {
        var matcher = DictationTriggerMatcher()
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        XCTAssertEqual(matcher.handle(flags(fn, [], at: 0.1)), .ended) // controller drops as too short
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0.3)), .began)
        XCTAssertNil(matcher.handle(flags(fn, [], at: 0.4)), "Release of second tap keeps listening")
        XCTAssertTrue(matcher.isSessionActive)
        XCTAssertNil(matcher.handle(keyDown(0x00, at: 2)), "Typing doesn't cancel hands-free")
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 10)), .ended)
        XCTAssertNil(matcher.handle(flags(fn, [], at: 10.1)))
        XCTAssertEqual(matcher.phase, .idle)
    }

    func testSlowSecondPressIsNotDoubleTap() {
        var matcher = DictationTriggerMatcher()
        _ = matcher.handle(flags(fn, .function, at: 0))
        _ = matcher.handle(flags(fn, [], at: 0.1))
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 1.0)), .began)
        XCTAssertEqual(matcher.handle(flags(fn, [], at: 2.0)), .ended)
    }

    func testDoubleTapDisabled() {
        var matcher = DictationTriggerMatcher(settings: DictationTriggerSettings(allowsDoubleTapHandsFree: false))
        _ = matcher.handle(flags(fn, .function, at: 0))
        _ = matcher.handle(flags(fn, [], at: 0.1))
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0.2)), .began)
        XCTAssertEqual(matcher.handle(flags(fn, [], at: 0.3)), .ended)
    }

    func testRightOptionUsesDeviceSpecificFlag() {
        var matcher = DictationTriggerMatcher(settings: DictationTriggerSettings(trigger: .rightOptionHold))
        // Left option should not trigger.
        XCTAssertNil(matcher.handle(flags(0x3A, .option, at: 0)))
        XCTAssertNil(matcher.handle(flags(0x3A, [], at: 0.1)))
        XCTAssertEqual(matcher.handle(flags(DictationKeyCode.rightOption, [.option, .rightOption], at: 1)), .began)
        XCTAssertEqual(matcher.handle(flags(DictationKeyCode.rightOption, [], at: 2)), .ended)
    }

    func testRightCommandHold() {
        var matcher = DictationTriggerMatcher(settings: DictationTriggerSettings(trigger: .rightCommandHold))
        XCTAssertEqual(matcher.handle(flags(DictationKeyCode.rightCommand, [.command, .rightCommand], at: 0)), .began)
        XCTAssertEqual(matcher.handle(keyDown(0x08, [.command, .rightCommand], at: 0.2)), .cancelled, "⌘C is a chord")
    }

    func testToggleModeStartsAndStopsOnPresses() {
        var matcher = DictationTriggerMatcher(settings: DictationTriggerSettings(trigger: .fnHold, mode: .toggle))
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        XCTAssertNil(matcher.handle(flags(fn, [], at: 0.2)))
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 5)), .ended)
        XCTAssertNil(matcher.handle(flags(fn, [], at: 5.1)))
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 6)), .began)
    }

    func testShortcutHoldRequiresExactModifiersAndIgnoresRepeats() {
        let space: UInt16 = 49
        var matcher = DictationTriggerMatcher(settings: DictationTriggerSettings(
            trigger: .shortcut(keyCode: space, modifiers: [.control, .option])
        ))
        XCTAssertNil(matcher.handle(keyDown(space, [.control], at: 0)), "Wrong modifiers")
        XCTAssertNil(matcher.handle(keyUp(space, [.control], at: 0.1)))
        XCTAssertEqual(matcher.handle(keyDown(space, [.control, .option], at: 1)), .began)
        XCTAssertNil(matcher.handle(keyDown(space, [.control, .option], repeat: true, at: 1.5)))
        XCTAssertEqual(matcher.handle(keyUp(space, [.control, .option], at: 2)), .ended)
    }

    func testSessionEndedExternallySuppressesUntilRelease() {
        var matcher = DictationTriggerMatcher()
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 0)), .began)
        matcher.sessionEndedExternally()
        XCTAssertNil(matcher.handle(flags(fn, [], at: 400)))
        XCTAssertEqual(matcher.handle(flags(fn, .function, at: 401)), .began)
    }

    func testCGEventFlagConversion() {
        let raw = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskAlternate.rawValue | 0x40
        let converted = DictationHotKeyMonitor.modifierFlags(from: CGEventFlags(rawValue: raw))
        XCTAssertEqual(converted, [.function, .option, .rightOption])
    }
}
