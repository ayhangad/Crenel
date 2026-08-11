import Foundation

struct MeetingSessionDiagnostic: Codable, Equatable, Sendable {
    static let marker = "meeting-session-v1"

    let sessionID: UUID
    let state: String
    let confidence: String
    let client: String
    let microphone: String
    let evidenceKinds: [String]

    var logLine: String {
        let evidence = evidenceKinds.sorted().isEmpty
            ? "none"
            : evidenceKinds.sorted().joined(separator: ",")
        return "\(Self.marker) session=\(sessionID.uuidString.lowercased()) "
            + "state=\(state) confidence=\(confidence) client=\(client) "
            + "microphone=\(microphone) evidence=\(evidence)"
    }

    static func parse(line: String) -> MeetingSessionDiagnostic? {
        guard let markerRange = line.range(of: marker) else { return nil }
        let payload = line[markerRange.lowerBound...]
        var fields: [Substring: Substring] = [:]
        for component in payload.split(separator: " ").dropFirst() {
            guard let separator = component.firstIndex(of: "=") else { continue }
            fields[component[..<separator]] = component[component.index(after: separator)...]
        }
        guard let sessionValue = fields["session"],
              let sessionID = UUID(uuidString: String(sessionValue)),
              let state = fields["state"],
              let confidence = fields["confidence"],
              let client = fields["client"],
              let microphone = fields["microphone"],
              let evidence = fields["evidence"] else {
            return nil
        }
        let evidenceKinds = evidence == "none"
            ? []
            : evidence.split(separator: ",").map(String.init).sorted()
        return MeetingSessionDiagnostic(
            sessionID: sessionID,
            state: String(state),
            confidence: String(confidence),
            client: String(client),
            microphone: String(microphone),
            evidenceKinds: evidenceKinds
        )
    }

    static func parseDocument(_ document: String) -> [MeetingSessionDiagnostic] {
        document.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            if let data = line.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["eventMessage"] as? String {
                return parse(line: message)
            }
            return parse(line: line)
        }
    }
}

struct MeetingSessionRunAudit: Codable, Equatable, Sendable {
    let sessionID: UUID
    let expectedClientObserved: Bool
    let confirmedReadyObserved: Bool
    let confirmedEndObservedAfterReady: Bool
    let terminalStateRegressed: Bool
    let stateSequence: [String]
    let passed: Bool
}

struct MeetingSessionAcceptanceAuditResult: Codable, Equatable, Sendable {
    let expectedClient: String
    let requiredRuns: Int
    let observedRuns: Int
    let passingRuns: Int
    let ignoredDiagnostics: Int
    let runs: [MeetingSessionRunAudit]
    let passed: Bool
}

enum MeetingSessionAcceptanceAuditError: LocalizedError, Equatable {
    case invalidRequiredRuns(Int)
    case invalidExpectedClient(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRequiredRuns(value):
            "Gerekli session koşusu geçersiz: \(value)"
        case let .invalidExpectedClient(value):
            "Beklenen meeting istemcisi geçersiz: \(value)"
        }
    }
}

struct MeetingSessionAcceptanceAuditor {
    static let supportedClients = ["zoom", "googleMeetChrome"]

    func audit(
        diagnostics: [MeetingSessionDiagnostic],
        expectedClient: String,
        requiredRuns: Int = 5
    ) throws -> MeetingSessionAcceptanceAuditResult {
        guard requiredRuns > 0 else {
            throw MeetingSessionAcceptanceAuditError.invalidRequiredRuns(requiredRuns)
        }
        guard Self.supportedClients.contains(expectedClient) else {
            throw MeetingSessionAcceptanceAuditError.invalidExpectedClient(expectedClient)
        }

        var sessionOrder: [UUID] = []
        var grouped: [UUID: [MeetingSessionDiagnostic]] = [:]
        for diagnostic in diagnostics {
            if grouped[diagnostic.sessionID] == nil {
                sessionOrder.append(diagnostic.sessionID)
            }
            grouped[diagnostic.sessionID, default: []].append(diagnostic)
        }

        let relevantIDs = sessionOrder.filter { sessionID in
            grouped[sessionID, default: []].contains { $0.client == expectedClient }
        }
        let runs = relevantIDs.map { sessionID in
            auditRun(
                sessionID: sessionID,
                diagnostics: grouped[sessionID, default: []],
                expectedClient: expectedClient
            )
        }
        let passingRuns = runs.filter(\.passed).count
        let passed = runs.count >= requiredRuns
            && passingRuns >= requiredRuns
            && runs.allSatisfy(\.passed)
        let relevantDiagnosticCount = relevantIDs.reduce(0) {
            $0 + grouped[$1, default: []].count
        }
        return MeetingSessionAcceptanceAuditResult(
            expectedClient: expectedClient,
            requiredRuns: requiredRuns,
            observedRuns: runs.count,
            passingRuns: passingRuns,
            ignoredDiagnostics: diagnostics.count - relevantDiagnosticCount,
            runs: runs,
            passed: passed
        )
    }

    private func auditRun(
        sessionID: UUID,
        diagnostics: [MeetingSessionDiagnostic],
        expectedClient: String
    ) -> MeetingSessionRunAudit {
        let readyIndex = diagnostics.firstIndex {
            $0.client == expectedClient
                && $0.state == "ready"
                && $0.confidence == "confirmed"
        }
        let endIndex = readyIndex.flatMap { readyIndex in
            diagnostics.indices.first {
                $0 > readyIndex
                    && diagnostics[$0].state == "ended"
                    && diagnostics[$0].confidence == "confirmed"
            }
        }
        let firstEndedIndex = diagnostics.firstIndex { $0.state == "ended" }
        let terminalStateRegressed = firstEndedIndex.map { endedIndex in
            diagnostics.indices.contains { $0 > endedIndex && diagnostics[$0].state != "ended" }
        } ?? false
        let stateSequence = diagnostics.map(\.state).reduce(into: [String]()) { sequence, state in
            if sequence.last != state {
                sequence.append(state)
            }
        }
        let clientObserved = diagnostics.contains { $0.client == expectedClient }
        let readyObserved = readyIndex != nil
        let endObserved = endIndex != nil
        return MeetingSessionRunAudit(
            sessionID: sessionID,
            expectedClientObserved: clientObserved,
            confirmedReadyObserved: readyObserved,
            confirmedEndObservedAfterReady: endObserved,
            terminalStateRegressed: terminalStateRegressed,
            stateSequence: stateSequence,
            passed: clientObserved && readyObserved && endObserved && !terminalStateRegressed
        )
    }
}
