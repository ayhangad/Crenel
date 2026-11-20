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

/// Live store. Writing `AppleFnUsageType` with CFPreferences alone only changed the file:
/// the system process that handles the 🌐 key (TextInputSwitcher) keeps its cached value
/// until the next login, so the key stayed "Do Nothing" after Crenel quit until the Mac
/// restarted. System Settings changes it through HIToolbox's `TISUpdateFnUsageType`, which
/// writes the value and tells every process to re-read it; Crenel does the same and only
/// falls back to CFPreferences if that function is missing.
final class SystemFnUsageSettingStore: FnUsageSettingStore {
    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString
    private static let savedKey = "crenel.fnUsageType.original"
    private static let absentMarker = -1

    private let defaults: UserDefaults
    private let toolbox: FnUsageToolbox?

    init(defaults: UserDefaults = .standard, toolbox: FnUsageToolbox? = .live) {
        self.defaults = defaults
        self.toolbox = toolbox
    }

    func systemValue() -> Int? {
        // The effective value, including macOS's own default when the key is absent.
        if let toolbox { return Int(toolbox.get()) }
        CFPreferencesAppSynchronize(Self.domain)
        return (CFPreferencesCopyAppValue(Self.key, Self.domain) as? NSNumber)?.intValue
    }

    func setSystemValue(_ value: Int?) {
        guard let toolbox else {
            CFPreferencesSetAppValue(Self.key, value.map { NSNumber(value: $0) }, Self.domain)
            CFPreferencesAppSynchronize(Self.domain)
            return
        }
        if let value, (0...3).contains(value) {
            toolbox.update(Int32(value))
            return
        }
        // Earlier builds saved "absent" when the user had never picked a value. Remove the
        // key, let HIToolbox work out macOS's default for this Mac, and apply that live.
        // The first update clears HIToolbox's in-process cache so the default is re-read.
        toolbox.update(toolbox.get())
        toolbox.clearStoredValue()
        toolbox.update(toolbox.get())
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

/// HIToolbox's own getter and setter for "Press 🌐 key to", loaded at run time.
struct FnUsageToolbox {
    let get: () -> Int32
    let update: (Int32) -> Void
    /// Removes the stored value so macOS falls back to its default.
    var clearStoredValue: () -> Void = {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesSetAppValue("AppleFnUsageType" as CFString, nil, domain)
        CFPreferencesAppSynchronize(domain)
    }

    static let live: FnUsageToolbox? = {
        typealias Getter = @convention(c) () -> Int32
        typealias Setter = @convention(c) (Int32) -> Void
        guard let carbon = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_LAZY),
              let getter = dlsym(carbon, "TISGetFnUsageType"),
              let setter = dlsym(carbon, "TISUpdateFnUsageType") else { return nil }
        let get = unsafeBitCast(getter, to: Getter.self)
        let update = unsafeBitCast(setter, to: Setter.self)
        return FnUsageToolbox(get: { get() }, update: { update($0) })
    }()
}
