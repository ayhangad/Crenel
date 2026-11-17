import XCTest
@testable import Crenel

final class MeetingSessionLifecyclePolicyTests: XCTestCase {
    func testConfirmedReadySessionOffersRecordingOnlyOnce() {
        var policy = MeetingSessionLifecyclePolicy()
        let session = makeSession(state: .ready, confidence: .confirmed)
        let expected = MeetingLifecyclePrompt.recordingOffer(
            sessionID: session.id,
            clientID: .zoom
        )

        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: false,
                canOfferRecording: true
            ),
            .present(expected)
        )
        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: false,
                canOfferRecording: true
            ),
            .none
        )
        XCTAssertEqual(policy.dismissRecordingOffer(), .dismiss)
        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: false,
                canOfferRecording: true
            ),
            .none
        )
    }

    func testProbableStartNeverOffersRecording() {
        var policy = MeetingSessionLifecyclePolicy()
        let session = makeSession(state: .candidate, confidence: .probable)

        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: false,
                canOfferRecording: true
            ),
            .none
        )
    }

    func testProbableEndRequestsManualConfirmation() {
        var policy = MeetingSessionLifecyclePolicy()
        let session = makeSession(state: .endSuspected, confidence: .probable)

        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: true,
                canOfferRecording: false
            ),
            .present(
                .endConfirmation(sessionID: session.id, clientID: .zoom)
            )
        )
    }

    func testConfirmedEndStartsFiveSecondAutoStop() {
        var policy = MeetingSessionLifecyclePolicy()
        let now = Date(timeIntervalSince1970: 2_000)
        let session = makeSession(state: .ended, confidence: .confirmed)

        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: true,
                canOfferRecording: false,
                now: now
            ),
            .present(
                .autoStop(
                    sessionID: session.id,
                    clientID: .zoom,
                    deadline: now.addingTimeInterval(5)
                )
            )
        )
    }

    func testContinueRecordingSuppressesFurtherEndPromptsForSession() {
        var policy = MeetingSessionLifecyclePolicy()
        let session = makeSession(state: .ended, confidence: .confirmed)
        _ = policy.evaluate(
            session,
            isRecording: true,
            canOfferRecording: false
        )

        XCTAssertEqual(policy.continueRecording(sessionID: session.id), .dismiss)
        XCTAssertEqual(
            policy.evaluate(
                session,
                isRecording: true,
                canOfferRecording: false
            ),
            .none
        )
    }

    func testRecoveredRecordingSignalDismissesEndConfirmation() {
        var policy = MeetingSessionLifecyclePolicy()
        let sessionID = UUID()
        _ = policy.evaluate(
            makeSession(
                id: sessionID,
                state: .endSuspected,
                confidence: .probable
            ),
            isRecording: true,
            canOfferRecording: false
        )

        XCTAssertEqual(
            policy.evaluate(
                makeSession(
                    id: sessionID,
                    state: .recording,
                    confidence: .confirmed
                ),
                isRecording: true,
                canOfferRecording: false
            ),
            .dismiss
        )
    }

    private func makeSession(
        id: UUID = UUID(),
        state: MeetingSessionState,
        confidence: DetectionConfidence
    ) -> MeetingSession {
        MeetingSession(
            id: id,
            state: state,
            confidence: confidence,
            clientID: .zoom
        )
    }
}
