import XCTest
@testable import Crenel

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
            lastFailure: .authentication
        )

        let encoded = try JSONEncoder().encode(job)
        let document = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertTrue(document.contains("authentication"))
        XCTAssertFalse(document.localizedCaseInsensitiveContains("message"))
        XCTAssertFalse(document.localizedCaseInsensitiveContains("transcript"))
    }

    func testMeetingSessionDiagnosticExcludesCalendarIDProcessIDAndUIContent() {
        let secretCalendarID = "gizli-musteri-toplantisi"
        let session = MeetingSession(
            state: .ready,
            confidence: .confirmed,
            evidence: [
                .calendarContext(meetingID: secretCalendarID, isWithinScheduledWindow: true),
                .process(processID: 98_765, isRunning: true),
                .clientUI(clientID: .zoom, meetingWindowPresent: true, callControlsPresent: true)
            ],
            clientID: .zoom,
            processID: 98_765,
            calendarMeetingID: secretCalendarID
        )
        let snapshot = MeetingSessionDetectionSnapshot(
            session: session,
            audioProcess: nil,
            client: MeetingClientSnapshot(
                clientID: .zoom,
                processID: 98_765,
                availability: .available,
                meetingWindowPresent: true,
                callControlsPresent: true,
                microphoneState: .closed
            )
        )

        let logLine = AppLogger.meetingSessionDiagnostic(snapshot).logLine

        XCTAssertTrue(logLine.contains("client=zoom"))
        XCTAssertTrue(logLine.contains("state=ready"))
        XCTAssertFalse(logLine.contains(secretCalendarID))
        XCTAssertFalse(logLine.contains("98765"))
    }
}
