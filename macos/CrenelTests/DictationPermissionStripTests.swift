import XCTest
@testable import Crenel

final class DictationPermissionStripTests: XCTestCase {
    func testPermissionFailuresOfferAllowNotSettings() {
        for failure in [DictationFailure.accessibilityPermissionMissing, .microphonePermissionDenied, .inputMonitoringPermissionMissing] {
            XCTAssertEqual(NotchClosedText.dictationFailure(failure).fix, .allowAccess, "\(failure)")
        }
        XCTAssertEqual(NotchClosedText.dictationFailure(.speechAssetsMissing(localeIdentifier: "tr_TR")).fix, .downloadModel)
    }
}
