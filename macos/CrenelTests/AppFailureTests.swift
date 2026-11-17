import XCTest
@testable import Crenel

final class AppFailureTests: XCTestCase {
    func testNetworkFailureIsRetryable() {
        let failure = AppFailure.network("Bağlantı yok.")

        XCTAssertEqual(failure.category, .network)
        XCTAssertTrue(failure.isRetryable)
        XCTAssertEqual(failure.recoveryButtonTitle, "Check connection")
    }

    func testInvalidCredentialsRequireSettingsUpdate() {
        let failure = AppFailure.provider("API anahtarı geçersiz.", credentialsInvalid: true)

        XCTAssertEqual(failure.category, .provider)
        XCTAssertFalse(failure.isRetryable)
        XCTAssertEqual(failure.recoveryAction, .updateCredentials)
    }
}
