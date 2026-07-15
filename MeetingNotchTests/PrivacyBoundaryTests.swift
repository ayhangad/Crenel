import XCTest
@testable import MeetingNotch

final class PrivacyBoundaryTests: XCTestCase {
    private struct SensitiveError: LocalizedError {
        let secret: String
        var errorDescription: String? { "Toplantı içeriği: \(secret)" }
    }

    func testDiagnosticContainsOnlyErrorType() {
        let secret = "gizli-toplanti-metni"
        let diagnostic = PrivacySafeDiagnostic(error: SensitiveError(secret: secret))

        XCTAssertFalse(diagnostic.errorType.contains(secret))
        XCTAssertTrue(diagnostic.errorType.contains("SensitiveError"))
    }

    func testUnknownProviderErrorIsNormalizedWithoutItsMessage() {
        let secret = "müşteri-bütçesi-çok-gizli"
        let error = SensitiveError(secret: secret)

        let normalized = TranscriptionErrorNormalizer.normalize(error)

        XCTAssertEqual(normalized, .providerUnavailable)
        XCTAssertFalse(normalized.appFailure.message.contains(secret))
    }

    func testPersistableProcessingFailureContainsNoProviderPayload() throws {
        let job = ProcessingJob(
            meetingID: UUID(),
            providerID: .openAI,
            lastFailure: .authentication
        )

        let encoded = try JSONEncoder().encode(job)
        let document = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(document.contains("authentication"))
        XCTAssertFalse(document.localizedCaseInsensitiveContains("message"))
        XCTAssertFalse(document.localizedCaseInsensitiveContains("transcript"))
    }
}
