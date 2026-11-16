import CoreGraphics
import Foundation

/// Abstraction so the controller can be tested without a real event tap.
@MainActor
protocol DictationTriggerMonitoring: AnyObject {
    var onEvent: ((DictationTriggerEvent) -> Void)? { get set }
    var settings: DictationTriggerSettings { get set }
    @discardableResult func start() -> Bool
    func stop()
    /// Tell the monitor the session ended without a key event (timeout, error, manual stop).
    func sessionEndedExternally()
}

/// Listen-only CGEventTap that detects press/release of the configured dictation trigger.
///
/// Requires Input Monitoring permission (`CGPreflightListenEventAccess`). Events are never
/// modified or swallowed, so the system's own Fn/Globe action still fires; users should set
/// "Press 🌐 key to" to "Do Nothing" in Keyboard settings.
@MainActor
final class DictationHotKeyMonitor: DictationTriggerMonitoring {
    var onEvent: ((DictationTriggerEvent) -> Void)?

    var settings: DictationTriggerSettings {
        get { matcher.settings }
        set { matcher.settings = newValue }
    }

    private var matcher: DictationTriggerMatcher
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(settings: DictationTriggerSettings = .default) {
        matcher = DictationTriggerMatcher(settings: settings)
    }

    static func hasInputMonitoringAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Shows the system prompt the first time; afterwards the user must enable it in System Settings.
    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    var isRunning: Bool {
        eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    @discardableResult
    func start() -> Bool {
        stop()
        guard Self.hasInputMonitoringAccess() else { return false }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<DictationHotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap source is added to the main run loop, so this runs on the main thread.
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        matcher.hardReset()
    }

    func sessionEndedExternally() {
        matcher.sessionEndedExternally()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            // A release may have been missed while disabled; abandon an in-flight hold safely.
            if matcher.isSessionActive {
                matcher.hardReset()
                onEvent?(.cancelled)
            } else {
                matcher.hardReset()
            }
            return
        case .flagsChanged, .keyDown, .keyUp:
            break
        default:
            return
        }

        guard let keyEvent = Self.keyEvent(type: type, event: event),
              let output = matcher.handle(keyEvent) else { return }
        onEvent?(output)
    }

    nonisolated static func keyEvent(type: CGEventType, event: CGEvent) -> DictationKeyEvent? {
        let kind: DictationKeyEvent.Kind
        switch type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: return nil
        }
        return DictationKeyEvent(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: modifierFlags(from: event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            timestamp: TimeInterval(event.timestamp) / 1_000_000_000
        )
    }

    nonisolated static func modifierFlags(from flags: CGEventFlags) -> DictationModifierFlags {
        var result: DictationModifierFlags = []
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        // IOKit NX_DEVICERALTKEYMASK / NX_DEVICERCMDKEYMASK device-dependent bits.
        if flags.rawValue & 0x0000_0040 != 0 { result.insert(.rightOption) }
        if flags.rawValue & 0x0000_0010 != 0 { result.insert(.rightCommand) }
        return result
    }

    deinit {
        // `stop()` must be called by the owner on the main actor; invalidate defensively.
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }
}
