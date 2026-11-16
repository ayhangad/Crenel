import Foundation

/// Modifier state carried by keyboard events, independent of CoreGraphics types.
struct DictationModifierFlags: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let shift = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)
    static let function = Self(rawValue: 1 << 4)
    /// Device-specific bits; only meaningful in live events, never in shortcut definitions.
    static let rightOption = Self(rawValue: 1 << 8)
    static let rightCommand = Self(rawValue: 1 << 9)

    /// Device-independent modifiers used for chord/shortcut comparison.
    static let standard: Self = [.shift, .control, .option, .command, .function]
}

/// Virtual key codes (Carbon `kVK_*`) needed by the matcher.
enum DictationKeyCode {
    static let escape: UInt16 = 0x35
    static let function: UInt16 = 0x3F
    /// Some Apple keyboards report the Globe key with this code.
    static let globe: UInt16 = 0xB3
    static let rightOption: UInt16 = 0x3D
    static let rightCommand: UInt16 = 0x36
}

/// Which physical key (or shortcut) starts dictation.
enum DictationTrigger: Codable, Hashable, Sendable {
    case fnHold
    case rightOptionHold
    case rightCommandHold
    case shortcut(keyCode: UInt16, modifiers: DictationModifierFlags)

    var isModifierKey: Bool {
        if case .shortcut = self { return false }
        return true
    }

    var displayName: String {
        switch self {
        case .fnHold:
            return "Fn (🌐)"
        case .rightOptionHold:
            return "Sağ Option (⌥)"
        case .rightCommandHold:
            return "Sağ Command (⌘)"
        case .shortcut:
            return "Özel kısayol"
        }
    }
}

enum DictationTriggerMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Speak while holding the trigger; release to finish.
    case holdToTalk
    /// Press once to start, press again to finish.
    case toggle
}

struct DictationTriggerSettings: Codable, Hashable, Sendable {
    var trigger: DictationTrigger
    var mode: DictationTriggerMode
    /// Double-tapping Fn starts a hands-free session that ends on the next Fn press.
    var allowsDoubleTapHandsFree: Bool

    init(
        trigger: DictationTrigger = .fnHold,
        mode: DictationTriggerMode = .holdToTalk,
        allowsDoubleTapHandsFree: Bool = true
    ) {
        self.trigger = trigger
        self.mode = mode
        self.allowsDoubleTapHandsFree = allowsDoubleTapHandsFree
    }

    static let `default` = DictationTriggerSettings()
}

/// What the trigger monitor reports to the dictation controller.
enum DictationTriggerEvent: Equatable, Sendable {
    case began
    case ended
    case cancelled
}
