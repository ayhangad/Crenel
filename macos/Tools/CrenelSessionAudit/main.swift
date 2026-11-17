import Foundation

private struct Arguments {
    var inputURL: URL?
    var reportDirectory: URL?
    var expectedClient: String?
    var requiredRuns = 5
}

private enum CommandError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message): message
        }
    }
}

private func usage() -> String {
    """
    Kullanım:
      Scripts/session-acceptance-audit.sh \\
        --input /path/to/session.ndjson \\
        --client zoom|googleMeetChrome \\
        --required-runs 5 \\
        --report-dir QA/Evidence/2026-08-11/zoom-session-5x
    """
}

private func parseArguments(_ raw: [String]) throws -> Arguments {
    var arguments = Arguments()
    var index = 0

    func value(after option: String) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < raw.count else {
            throw CommandError.usage("\(option) için değer eksik.\n\n\(usage())")
        }
        index = valueIndex
        return raw[valueIndex]
    }

    while index < raw.count {
        switch raw[index] {
        case "--input":
            arguments.inputURL = URL(fileURLWithPath: try value(after: raw[index]))
        case "--client":
            arguments.expectedClient = try value(after: raw[index])
        case "--required-runs":
            let rawValue = try value(after: raw[index])
            guard let value = Int(rawValue), value > 0 else {
                throw CommandError.usage("Geçersiz --required-runs: \(rawValue)")
            }
            arguments.requiredRuns = value
        case "--report-dir":
            arguments.reportDirectory = URL(fileURLWithPath: try value(after: raw[index]), isDirectory: true)
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            throw CommandError.usage("Bilinmeyen seçenek: \(raw[index])\n\n\(usage())")
        }
        index += 1
    }

    guard arguments.inputURL != nil,
          arguments.reportDirectory != nil,
          arguments.expectedClient != nil else {
        throw CommandError.usage("--input, --client ve --report-dir gereklidir.\n\n\(usage())")
    }
    return arguments
}

private func markdown(for result: MeetingSessionAcceptanceAuditResult) -> String {
    var lines = [
        "# Meeting session acceptance audit",
        "",
        "- Result: \(result.passed ? "PASS" : "FAIL")",
        "- Client: \(result.expectedClient)",
        "- Required runs: \(result.requiredRuns)",
        "- Observed runs: \(result.observedRuns)",
        "- Passing runs: \(result.passingRuns)",
        "- Ignored diagnostics: \(result.ignoredDiagnostics)",
        "",
        "| Session | Confirmed ready | Confirmed end after ready | Terminal regression | Sequence | Result |",
        "| --- | --- | --- | --- | --- | --- |"
    ]
    for run in result.runs {
        lines.append(
            "| \(run.sessionID.uuidString.lowercased()) | "
                + "\(run.confirmedReadyObserved ? "yes" : "no") | "
                + "\(run.confirmedEndObservedAfterReady ? "yes" : "no") | "
                + "\(run.terminalStateRegressed ? "yes" : "no") | "
                + "\(run.stateSequence.joined(separator: " → ")) | "
                + "\(run.passed ? "PASS" : "FAIL") |"
        )
    }
    lines += [
        "",
        "Bu audit yalnız normalize session zincirini doğrular. 60 saniyelik sessizlikte yanlış",
        "bitiş olmaması, gerçek hang-up zamanıyla eşleşme ve Accessibility kapalı manuel kayıt",
        "davranışı timeline.md üzerinde fiziksel olarak ayrıca işaretlenmelidir.",
        ""
    ]
    return lines.joined(separator: "\n")
}

do {
    let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let inputURL = arguments.inputURL!
    guard let document = try? String(contentsOf: inputURL, encoding: .utf8) else {
        throw CommandError.usage("Session log okunamadı: \(inputURL.path)")
    }
    let diagnostics = MeetingSessionDiagnostic.parseDocument(document)
    let result = try MeetingSessionAcceptanceAuditor().audit(
        diagnostics: diagnostics,
        expectedClient: arguments.expectedClient!,
        requiredRuns: arguments.requiredRuns
    )
    let reportDirectory = arguments.reportDirectory!
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(
        to: reportDirectory.appending(path: "session-audit.json"),
        options: .atomic
    )
    try markdown(for: result).write(
        to: reportDirectory.appending(path: "session-audit.md"),
        atomically: true,
        encoding: .utf8
    )
    print("\(result.passed ? "PASS" : "FAIL"): \(reportDirectory.path)")
    exit(result.passed ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
    exit(2)
}
