import Foundation

/// Reads and writes the system "Press 🌐 key to" setting (`com.apple.HIToolbox`
/// `AppleFnUsageType`). `nil` means the key is absent and macOS uses its default.
protocol FnUsageSettingStore: AnyObject {
    func systemValue() -> Int?
    func setSystemValue(_ value: Int?)
    /// The user's own value, saved before Crenel changed it. `.some(nil)` = it was absent.
    var savedOriginal: Int?? { get set }
}

/// While Fn is Crenel's dictation key, a lone Fn press must not also switch the input
/// language, open the emoji panel or start system dictation. Like other hold-to-talk apps,
/// Crenel sets "Press 🌐 key to" to "Do Nothing" while it owns Fn and restores the user's
/// own choice as soon as dictation is turned off or moved to another key.
@MainActor
final class FnKeySystemActionGuard {
    /// `AppleFnUsageType` values: 0 Do Nothing, 1 Change Input Source, 2 Emoji, 3 Dictation.
    static let doNothing = 0

    private let store: any FnUsageSettingStore

    init(store: any FnUsageSettingStore = SystemFnUsageSettingStore()) {
        self.store = store
    }

    var ownsFnKey: Bool { store.savedOriginal != nil }

    func update(dictationEnabled: Bool, trigger: DictationTrigger) {
        if dictationEnabled, trigger == .fnHold {
            claim()
        } else {
            release()
        }
    }

    private func claim() {
        let current = store.systemValue()
        if store.savedOriginal == nil {
            // Remember the user's own value once; never overwrite it with our own "Do Nothing".
            store.savedOriginal = .some(current)
        }
        if current != Self.doNothing {
            store.setSystemValue(Self.doNothing)
        }
    }

    private func release() {
        guard let original = store.savedOriginal else { return }
        // Only undo our own change; if the user picked something else meanwhile, keep it.
        if store.systemValue() == Self.doNothing {
            store.setSystemValue(original)
        }
        store.savedOriginal = nil
    }
}

final class SystemFnUsageSettingStore: FnUsageSettingStore {
    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString
    private static let savedKey = "crenel.fnUsageType.original"
    private static let absentMarker = -1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func systemValue() -> Int? {
        CFPreferencesAppSynchronize(Self.domain)
        return (CFPreferencesCopyAppValue(Self.key, Self.domain) as? NSNumber)?.intValue
    }

    func setSystemValue(_ value: Int?) {
        CFPreferencesSetAppValue(Self.key, value.map { NSNumber(value: $0) }, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
    }

    var savedOriginal: Int?? {
        get {
            guard let stored = defaults.object(forKey: Self.savedKey) as? Int else { return nil }
            return .some(stored == Self.absentMarker ? nil : stored)
        }
        set {
            switch newValue {
            case .none: defaults.removeObject(forKey: Self.savedKey)
            case .some(let value): defaults.set(value ?? Self.absentMarker, forKey: Self.savedKey)
            }
        }
    }
}
