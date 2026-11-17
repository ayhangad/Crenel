import Foundation

/// A keyboard event normalized away from CoreGraphics so trigger logic stays testable.
struct DictationKeyEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case flagsChanged
        case keyDown
        case keyUp
    }

    var kind: Kind
    var keyCode: UInt16
    var modifiers: DictationModifierFlags
    var isRepeat: Bool
    /// Seconds on a monotonic clock.
    var timestamp: TimeInterval

    init(
        kind: Kind,
        keyCode: UInt16,
        modifiers: DictationModifierFlags = [],
        isRepeat: Bool = false,
        timestamp: TimeInterval
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }
}

/// Pure state machine that turns raw key events into dictation begin/end/cancel events.
struct DictationTriggerMatcher {
    enum Phase: Equatable {
        case idle
        /// Hold-to-talk session in progress.
        case holding(pressedAt: TimeInterval)
        /// Trigger is physically down but must be ignored until release (chord or session end).
        case suppressed
        /// Toggle / hands-free session in progress; `awaitingRelease` swallows the starting press's release.
        case latched(awaitingRelease: Bool)
    }

    var settings: DictationTriggerSettings {
        didSet {
            if settings != oldValue { hardReset() }
        }
    }
    var doubleTapWindow: TimeInterval = 0.35
    var maximumTapDuration: TimeInterval = 0.3

    private(set) var phase: Phase = .idle
    private(set) var isTriggerDown = false
    private var lastTapReleasedAt: TimeInterval?

    init(settings: DictationTriggerSettings = .default) {
        self.settings = settings
    }

    var isSessionActive: Bool {
        switch phase {
        case .holding, .latched:
            return true
        case .idle, .suppressed:
            return false
        }
    }

    /// Called when the session ended for reasons outside the keyboard (timeout, error).
    mutating func sessionEndedExternally() {
        phase = isTriggerDown ? .suppressed : .idle
        lastTapReleasedAt = nil
    }

    mutating func hardReset() {
        phase = .idle
        isTriggerDown = false
        lastTapReleasedAt = nil
    }

    mutating func handle(_ event: DictationKeyEvent) -> DictationTriggerEvent? {
        let transition = triggerTransition(for: event)

        if event.kind == .keyDown, event.keyCode == DictationKeyCode.escape, isSessionActive {
            phase = isTriggerDown ? .suppressed : .idle
            lastTapReleasedAt = nil
            return .cancelled
        }

        switch phase {
        case .idle:
            guard transition == .pressed else { return nil }
            return handlePressWhileIdle(event)

        case .holding(let pressedAt):
            if transition == .released {
                phase = .idle
                if event.timestamp - pressedAt <= maximumTapDuration {
                    lastTapReleasedAt = event.timestamp
                } else {
                    lastTapReleasedAt = nil
                }
                return .ended
            }
            if isChordInterruption(event, transition: transition) {
                phase = isTriggerDown ? .suppressed : .idle
                lastTapReleasedAt = nil
                return .cancelled
            }
            return nil

        case .suppressed:
            if transition == .released || !isTriggerDown {
                phase = .idle
            }
            return nil

        case .latched(let awaitingRelease):
            switch transition {
            case .released where awaitingRelease:
                phase = .latched(awaitingRelease: false)
                return nil
            case .pressed where !awaitingRelease:
                phase = .suppressed
                lastTapReleasedAt = nil
                return .ended
            default:
                return nil
            }
        }
    }

    // MARK: - Private

    private enum Transition: Equatable {
        case pressed
        case released
    }

    private func handlePressWhileIdleChord(_ event: DictationKeyEvent) -> Bool {
        let others = event.modifiers.intersection(.standard).subtracting(ownModifierFlag)
        return !others.isEmpty
    }

    private mutating func handlePressWhileIdle(_ event: DictationKeyEvent) -> DictationTriggerEvent? {
        if settings.trigger.isModifierKey, handlePressWhileIdleChord(event) {
            phase = .suppressed
            lastTapReleasedAt = nil
            return nil
        }

        switch settings.mode {
        case .toggle:
            phase = .latched(awaitingRelease: true)
            lastTapReleasedAt = nil
            return .began
        case .holdToTalk:
            if settings.trigger == .fnHold,
               settings.allowsDoubleTapHandsFree,
               let lastTapReleasedAt,
               event.timestamp - lastTapReleasedAt <= doubleTapWindow {
                self.lastTapReleasedAt = nil
                phase = .latched(awaitingRelease: true)
                return .began
            }
            phase = .holding(pressedAt: event.timestamp)
            return .began
        }
    }

    /// While holding, any other key press or extra modifier turns the gesture into a chord.
    private func isChordInterruption(_ event: DictationKeyEvent, transition: Transition?) -> Bool {
        guard transition == nil else { return false }
        switch event.kind {
        case .keyDown:
            if case .shortcut(let keyCode, _) = settings.trigger, event.keyCode == keyCode {
                return false
            }
            return true
        case .flagsChanged:
            guard settings.trigger.isModifierKey else { return false }
            let others = event.modifiers.intersection(.standard).subtracting(ownModifierFlag)
            return !others.isEmpty
        case .keyUp:
            return false
        }
    }

    private var ownModifierFlag: DictationModifierFlags {
        switch settings.trigger {
        case .fnHold:
            return .function
        case .rightOptionHold:
            return .option
        case .rightCommandHold:
            return .command
        case .shortcut:
            return []
        }
    }

    private var triggerKeyCodes: Set<UInt16> {
        switch settings.trigger {
        case .fnHold:
            return [DictationKeyCode.function, DictationKeyCode.globe]
        case .rightOptionHold:
            return [DictationKeyCode.rightOption]
        case .rightCommandHold:
            return [DictationKeyCode.rightCommand]
        case .shortcut(let keyCode, _):
            return [keyCode]
        }
    }

    /// Which flag proves the trigger key itself is down (device-specific for right-side keys).
    private var triggerDownFlag: DictationModifierFlags {
        switch settings.trigger {
        case .fnHold:
            return .function
        case .rightOptionHold:
            return .rightOption
        case .rightCommandHold:
            return .rightCommand
        case .shortcut:
            return []
        }
    }

    private mutating func triggerTransition(for event: DictationKeyEvent) -> Transition? {
        switch settings.trigger {
        case .fnHold, .rightOptionHold, .rightCommandHold:
            guard event.kind == .flagsChanged else { return nil }
            let isDown: Bool
            if triggerKeyCodes.contains(event.keyCode) {
                isDown = event.modifiers.contains(triggerDownFlag)
            } else if isTriggerDown, !event.modifiers.contains(triggerDownFlag) {
                // Missed the release event of the trigger itself; recover.
                isDown = false
            } else {
                return nil
            }
            return updateTriggerDown(isDown)

        case .shortcut(let keyCode, let modifiers):
            guard event.keyCode == keyCode else { return nil }
            switch event.kind {
            case .keyDown:
                guard !event.isRepeat, !isTriggerDown else { return nil }
                guard event.modifiers.intersection(.standard) == modifiers.intersection(.standard) else {
                    return nil
                }
                return updateTriggerDown(true)
            case .keyUp:
                return updateTriggerDown(false)
            case .flagsChanged:
                return nil
            }
        }
    }

    private mutating func updateTriggerDown(_ isDown: Bool) -> Transition? {
        defer { isTriggerDown = isDown }
        if isDown, !isTriggerDown { return .pressed }
        if !isDown, isTriggerDown { return .released }
        return nil
    }
}
