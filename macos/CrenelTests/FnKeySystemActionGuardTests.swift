import XCTest
@testable import Crenel

@MainActor
final class FnKeySystemActionGuardTests: XCTestCase {
    private final class FakeStore: FnUsageSettingStore {
        var value: Int?
        var savedOriginal: Int??
        var writes = 0
        init(value: Int?) { self.value = value }
        func systemValue() -> Int? { value }
        func setSystemValue(_ value: Int?) { self.value = value; writes += 1 }
    }

    func testFnTriggerSetsDoNothingAndRestoresUserValue() {
        let store = FakeStore(value: 1)
        let guardian = FnKeySystemActionGuard(store: store)

        guardian.update(dictationEnabled: true, trigger: .fnHold)
        XCTAssertEqual(store.value, 0)
        XCTAssertTrue(guardian.ownsFnKey)

        guardian.update(dictationEnabled: true, trigger: .fnHold)
        XCTAssertEqual(store.savedOriginal, .some(1), "A second claim must not save our own 0 as the original")

        guardian.update(dictationEnabled: false, trigger: .fnHold)
        XCTAssertEqual(store.value, 1)
        XCTAssertFalse(guardian.ownsFnKey)
    }

    func testAbsentSettingIsRestoredAsAbsent() {
        let store = FakeStore(value: nil)
        let guardian = FnKeySystemActionGuard(store: store)

        guardian.update(dictationEnabled: true, trigger: .fnHold)
        guardian.update(dictationEnabled: true, trigger: .rightOptionHold)

        XCTAssertNil(store.value)
        XCTAssertFalse(guardian.ownsFnKey)
    }

    func testUserChoiceMadeMeanwhileIsKept() {
        let store = FakeStore(value: 2)
        let guardian = FnKeySystemActionGuard(store: store)
        guardian.update(dictationEnabled: true, trigger: .fnHold)
        store.value = 3

        guardian.update(dictationEnabled: false, trigger: .fnHold)

        XCTAssertEqual(store.value, 3)
    }

    func testOtherTriggerNeverTouchesSystemSetting() {
        let store = FakeStore(value: 1)
        let guardian = FnKeySystemActionGuard(store: store)

        guardian.update(dictationEnabled: true, trigger: .rightCommandHold)
        guardian.update(dictationEnabled: false, trigger: .fnHold)

        XCTAssertEqual(store.writes, 0)
    }

    // The live store goes through HIToolbox so the running 🌐 key handler hears the change.

    private final class FakeToolbox {
        var value: Int32 = 1
        var updates: [Int32] = []
        var cleared = 0
        /// What HIToolbox reports once the stored value is gone.
        var systemDefault: Int32 = 2
        lazy var toolbox = FnUsageToolbox(
            get: { self.value },
            update: { self.value = $0; self.updates.append($0) },
            clearStoredValue: { self.cleared += 1; self.value = self.systemDefault }
        )
    }

    func testLiveStoreAppliesValuesThroughHIToolbox() {
        let fake = FakeToolbox()
        let defaults = UserDefaults(suiteName: "FnKeySystemActionGuardTests.\(UUID().uuidString)")!
        let guardian = FnKeySystemActionGuard(store: SystemFnUsageSettingStore(defaults: defaults, toolbox: fake.toolbox))

        guardian.update(dictationEnabled: true, trigger: .fnHold)
        XCTAssertEqual(fake.updates, [0])

        guardian.update(dictationEnabled: false, trigger: .fnHold)
        XCTAssertEqual(fake.updates, [0, 1], "Quitting or turning dictation off restores the user's value live")
        XCTAssertFalse(guardian.ownsFnKey)
    }

    func testLegacyAbsentOriginalIsRestoredAsAnExplicitLiveValue() {
        let fake = FakeToolbox()
        fake.value = 0
        let defaults = UserDefaults(suiteName: "FnKeySystemActionGuardTests.\(UUID().uuidString)")!
        let store = SystemFnUsageSettingStore(defaults: defaults, toolbox: fake.toolbox)
        store.savedOriginal = .some(nil)

        FnKeySystemActionGuard(store: store).update(dictationEnabled: false, trigger: .fnHold)

        XCTAssertEqual(fake.cleared, 1)
        XCTAssertEqual(fake.updates.last, 2, "macOS's own default is applied live")
        XCTAssertNil(store.savedOriginal)
    }
}
