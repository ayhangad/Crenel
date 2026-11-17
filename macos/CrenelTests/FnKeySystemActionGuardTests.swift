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
}
