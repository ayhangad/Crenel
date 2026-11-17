import Foundation

private struct Arguments {
    var audioURLs: [URL] = []
    var transcriptURLs: [URL] = []
    var forbiddenPhrases: [String] = []
    var reportDirectory: URL?
    var toneFrequency = 997.0
    var maximumToneAmplitude = 0.02
    var minimumDurationSeconds: Double?
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
      Scripts/privacy-canary-audit.sh \\
        --report-dir QA/Evidence/2026-08-11/meet-canary-01 \\
        --audio /path/to/system.m4a \\
        --audio /path/to/final.m4a \\
        --transcript /path/to/transcript.json \\
        --forbidden-phrase "sentetik benzersiz cümle" \\
        --tone-hz 997 \\
        --max-tone-amplitude 0.02 \\
        --minimum-duration-seconds 3900

    Her --audio dosyasında tone'un eşik altında, her --transcript dosyasında yasaklı
    cümlenin yok olması beklenir. --minimum-duration-seconds verilirse tüm seslere uygulanır.
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
        case "--audio":
            arguments.audioURLs.append(URL(fileURLWithPath: try value(after: raw[index])))
        case "--transcript":
            arguments.transcriptURLs.append(URL(fileURLWithPath: try value(after: raw[index])))
        case "--forbidden-phrase":
            arguments.forbiddenPhrases.append(try value(after: raw[index]))
        case "--report-dir":
            arguments.reportDirectory = URL(fileURLWithPath: try value(after: raw[index]), isDirectory: true)
        case "--tone-hz":
            let rawValue = try value(after: raw[index])
            guard let value = Double(rawValue) else {
                throw CommandError.usage("Geçersiz --tone-hz: \(rawValue)")
            }
            arguments.toneFrequency = value
        case "--max-tone-amplitude":
            let rawValue = try value(after: raw[index])
            guard let value = Double(rawValue) else {
                throw CommandError.usage("Geçersiz --max-tone-amplitude: \(rawValue)")
            }
            arguments.maximumToneAmplitude = value
        case "--minimum-duration-seconds":
            let rawValue = try value(after: raw[index])
            guard let value = Double(rawValue), value >= 0 else {
                throw CommandError.usage("Geçersiz --minimum-duration-seconds: \(rawValue)")
            }
            arguments.minimumDurationSeconds = value
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            throw CommandError.usage("Bilinmeyen seçenek: \(raw[index])\n\n\(usage())")
        }
        index += 1
    }

    guard !arguments.audioURLs.isEmpty else {
        throw CommandError.usage("En az bir --audio gerekli.\n\n\(usage())")
    }
    if !arguments.transcriptURLs.isEmpty && arguments.forbiddenPhrases.isEmpty {
        throw CommandError.usage(
            "--transcript kullanıldığında en az bir --forbidden-phrase gerekli.\n\n\(usage())"
        )
    }
    guard let reportDirectory = arguments.reportDirectory else {
        throw CommandError.usage("--report-dir gerekli.\n\n\(usage())")
    }
    arguments.reportDirectory = reportDirectory.standardizedFileURL
    return arguments
}

private func formatted(_ value: Double, digits: Int = 4) -> String {
    String(format: "%.*f", digits, value)
}

private func markdown(for result: PrivacyCanaryAuditResult) -> String {
    var lines = [
        "# Privacy canary audit",
        "",
        "- Result: \(result.passed ? "PASS" : "FAIL")",
        "- Generated: \(ISO8601DateFormatter().string(from: result.generatedAt))",
        "- Forbidden tone: \(formatted(result.toneFrequency, digits: 1)) Hz",
        "",
        "## Audio",
        "",
        "| File | Duration | Rate/channels | Max tone amplitude | Threshold | Result |",
        "| --- | ---: | ---: | ---: | ---: | --- |"
    ]
    for item in result.audio {
        lines.append(
            "| \(URL(fileURLWithPath: item.path).lastPathComponent) | "
                + "\(formatted(item.durationSeconds, digits: 2)) s | "
                + "\(formatted(item.sampleRate, digits: 0)) Hz / \(item.channelCount) | "
                + "\(formatted(item.maximumToneAmplitude)) | \(formatted(item.toneThreshold)) | "
                + "\(item.passed ? "PASS" : "FAIL") |"
        )
    }

    lines += [
        "",
        "## Transcript",
        "",
        "| File | Forbidden phrases | Matches | Result |",
        "| --- | ---: | --- | --- |"
    ]
    if result.transcripts.isEmpty {
        lines.append("| — | 0 | — | NOT RUN |")
    } else {
        for item in result.transcripts {
            let matches = item.matchedPhrases.isEmpty ? "—" : item.matchedPhrases.joined(separator: ", ")
            lines.append(
                "| \(URL(fileURLWithPath: item.path).lastPathComponent) | "
                    + "\(item.forbiddenPhraseCount) | \(matches) | \(item.passed ? "PASS" : "FAIL") |"
            )
        }
    }

    lines += [
        "",
        "## Manual checks still required",
        "",
        "- Closed/unknown unique phrase must also be absent from raw microphone and final audio by listening or separate speech recognition.",
        "- Selected Meet tab audio must remain audible locally.",
        "- Extension/native bridge disconnect must visibly trigger fail-closed finalize.",
        ""
    ]
    return lines.joined(separator: "\n")
}

do {
    let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let result = try PrivacyCanaryFileAuditor().audit(
        audioURLs: arguments.audioURLs,
        transcriptURLs: arguments.transcriptURLs,
        forbiddenPhrases: arguments.forbiddenPhrases,
        toneFrequency: arguments.toneFrequency,
        maximumToneAmplitude: arguments.maximumToneAmplitude,
        minimumDurationSeconds: arguments.minimumDurationSeconds
    )
    let reportDirectory = arguments.reportDirectory!
    try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(
        to: reportDirectory.appending(path: "canary-audit.json"),
        options: .atomic
    )
    try markdown(for: result).write(
        to: reportDirectory.appending(path: "canary-audit.md"),
        atomically: true,
        encoding: .utf8
    )
    print("\(result.passed ? "PASS" : "FAIL"): \(reportDirectory.path)")
    exit(result.passed ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
    exit(2)
}
