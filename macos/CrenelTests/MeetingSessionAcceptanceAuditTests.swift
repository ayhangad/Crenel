import XCTest
@testable import Crenel

final class MeetingSessionAcceptanceAuditTests: XCTestCase {
    func testParsesPlainAndNDJSONSessionDiagnostics() throws {
        let diagnostic = makeDiagnostic(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            state: "ready",
            confidence: "confirmed",
            client: "zoom"
        )
        let ndjsonData = try JSONSerialization.data(
            withJSONObject: ["eventMessage": diagnostic.logLine],
            options: [.sortedKeys]
        )
        let ndjson = try XCTUnwrap(String(data: ndjsonData, encoding: .utf8))
        let parsed = MeetingSessionDiagnostic.parseDocument(
            "prefix \(diagnostic.logLine)\n\(ndjson)"
        )

        XCTAssertEqual(parsed, [diagnostic, diagnostic])
    }

    func testFiveConfirmedReadyToEndedSessionsPass() throws {
        let diagnostics = (1...5).flatMap { index in
            successfulRun(index: index, client: "zoom")
        }

        let result = try MeetingSessionAcceptanceAuditor().audit(
            diagnostics: diagnostics,
            expectedClient: "zoom",
            requiredRuns: 5
        )

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.observedRuns, 5)
        XCTAssertEqual(result.passingRuns, 5)
        XCTAssertTrue(result.runs.allSatisfy { $0.stateSequence == ["candidate", "ready", "recording", "endSuspected", "ended"] })
    }

    func testMissingReadyOrTerminalRegressionFailsWholeClientMatrix() throws {
        var diagnostics = (1...4).flatMap { index in
            successfulRun(index: index, client: "googleMeetChrome")
        }
        let failedID = sessionID(5)
        diagnostics += [
            makeDiagnostic(sessionID: failedID, state: "candidate", confidence: "probable", client: "googleMeetChrome"),
            makeDiagnostic(sessionID: failedID, state: "ended", confidence: "confirmed", client: "googleMeetChrome"),
            makeDiagnostic(sessionID: failedID, state: "candidate", confidence: "probable", client: "googleMeetChrome")
        ]

        let result = try MeetingSessionAcceptanceAuditor().audit(
            diagnostics: diagnostics,
            expectedClient: "googleMeetChrome",
            requiredRuns: 5
        )

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.observedRuns, 5)
        XCTAssertEqual(result.passingRuns, 4)
        XCTAssertFalse(result.runs.last!.confirmedReadyObserved)
        XCTAssertTrue(result.runs.last!.terminalStateRegressed)
    }

    func testOtherClientDiagnosticsAreIgnoredRatherThanCounted() throws {
        let diagnostics = successfulRun(index: 1, client: "zoom")
            + successfulRun(index: 2, client: "googleMeetChrome")

        let result = try MeetingSessionAcceptanceAuditor().audit(
            diagnostics: diagnostics,
            expectedClient: "zoom",
            requiredRuns: 1
        )

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.observedRuns, 1)
        XCTAssertEqual(result.ignoredDiagnostics, 5)
    }

    private func successfulRun(index: Int, client: String) -> [MeetingSessionDiagnostic] {
        let id = sessionID(index)
        return [
            makeDiagnostic(sessionID: id, state: "candidate", confidence: "probable", client: client),
            makeDiagnostic(sessionID: id, state: "ready", confidence: "confirmed", client: client),
            makeDiagnostic(sessionID: id, state: "recording", confidence: "confirmed", client: client),
            makeDiagnostic(sessionID: id, state: "endSuspected", confidence: "probable", client: client),
            makeDiagnostic(sessionID: id, state: "ended", confidence: "confirmed", client: client)
        ]
    }

    private func makeDiagnostic(
        sessionID: UUID,
        state: String,
        confidence: String,
        client: String
    ) -> MeetingSessionDiagnostic {
        MeetingSessionDiagnostic(
            sessionID: sessionID,
            state: state,
            confidence: confidence,
            client: client,
            microphone: "closed",
            evidenceKinds: ["clientUI", "process"]
        )
    }

    private func sessionID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }
}
