import Foundation

/// A coding agent CLI installed on this Mac, used as a plain text model with the user's own
/// sign-in (no API key in Crenel). Tools are switched off and each request runs in an empty
/// temporary folder, so the agent only ever answers in text.
enum CLIAgentTool: String, CaseIterable, Sendable {
    case claudeCode = "claude"
    case codex = "codex"

    var kind: AgentProviderKind {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        }
    }

    var executableName: String { rawValue }

    /// Arguments for one non-interactive, tool-less request. The text goes to standard input and
    /// the answer comes back on standard output.
    func arguments(systemInstructions: String, model: String?) -> [String] {
        switch self {
        case .claudeCode:
            var arguments = [
                "-p", "--output-format", "text",
                "--tools", "",
                "--setting-sources", "",
                "--strict-mcp-config",
                "--no-session-persistence",
                "--system-prompt", systemInstructions
            ]
            if let model { arguments += ["--model", model] }
            return arguments
        case .codex:
            var arguments = [
                "exec", "--skip-git-repo-check", "--ephemeral",
                "--ignore-user-config", "--ignore-rules",
                "--sandbox", "read-only", "--color", "never"
            ]
            arguments += CodexSafety.disableArguments
            arguments += [
                "-c", #"web_search="disabled""#,
                "-c", "developer_instructions=" + CodexSafety.tomlString(systemInstructions)
            ]
            if let model { arguments += ["--model", model] }
            return arguments + ["-"]
        }
    }
}

/// Codex can't hide its tools from the model the way Claude Code's `--tools ""` does. Its
/// command, file, image, patch and web tools all run through the code-mode host, so that host
/// and the plain shell tool are switched off, along with every other tool feature. Before each
/// run Codex is asked whether those gates are really off; if it can't confirm, it isn't run.
enum CodexSafety {
    static let minimumVersion = [0, 170, 0]

    /// Features that give the model tools. Unknown names make Codex exit, so a renamed feature
    /// fails closed.
    static let disabledFeatures = [
        "code_mode_host", "shell_tool", "unified_exec", "apps", "plugins", "hooks",
        "image_generation", "browser_use", "browser_use_external", "in_app_browser",
        "computer_use", "skill_search", "tool_suggest", "sleep_tool", "memories",
        "multi_agent", "goals"
    ]

    /// These must read `false` in Codex's own feature list before any text is sent.
    static let requiredOff = ["code_mode_host", "shell_tool"]

    static var disableArguments: [String] { disabledFeatures.flatMap { ["--disable", $0] } }
    static let versionArguments = ["--version"]
    static var featureListArguments: [String] { ["features", "list"] + disableArguments }

    /// `codex-cli 0.170.0` → `[0, 170, 0]`.
    static func version(from output: String) -> [Int]? {
        guard let token = output.split(whereSeparator: \.isWhitespace).last(where: { $0.first?.isNumber == true }) else { return nil }
        let parts = token.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        return parts.count >= 2 ? parts : nil
    }

    static func isSupported(version: [Int]) -> Bool {
        for (index, minimum) in minimumVersion.enumerated() {
            let value = index < version.count ? version[index] : 0
            if value != minimum { return value > minimum }
        }
        return true
    }

    /// Every required gate is listed and off.
    static func gatesAreOff(in featureList: String) -> Bool {
        var states: [String: String] = [:]
        for line in featureList.split(separator: "\n") {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard let name = columns.first, let state = columns.last, columns.count >= 3 else { continue }
            states[String(name)] = String(state)
        }
        return requiredOff.allSatisfy { states[$0] == "false" }
    }

    /// A TOML basic string, so `-c` never reads the instructions as another type.
    static func tomlString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    /// Confirmed installs, keyed by path and modification date so an update is checked again.
    private static let confirmed = Confirmed()

    static func verify(
        executable: URL,
        runner: any CLIProcessRunning,
        workingDirectory: URL,
        cacheKey: String? = nil
    ) async throws {
        let key = cacheKey ?? Self.cacheKey(for: executable)
        if let key, confirmed.contains(key) { return }
        let version = try await runner.run(
            executable: executable, arguments: versionArguments, standardInput: "",
            workingDirectory: workingDirectory, timeout: 15
        )
        guard version.exitCode == 0, let parsed = Self.version(from: version.standardOutput), isSupported(version: parsed) else {
            throw AgentError.toolUnsafe(.codex)
        }
        let features = try await runner.run(
            executable: executable, arguments: featureListArguments, standardInput: "",
            workingDirectory: workingDirectory, timeout: 15
        )
        guard features.exitCode == 0, gatesAreOff(in: features.standardOutput) else {
            throw AgentError.toolUnsafe(.codex)
        }
        if let key { confirmed.insert(key) }
    }

    private static func cacheKey(for executable: URL) -> String? {
        let resolved = executable.resolvingSymlinksInPath()
        guard let date = (try? FileManager.default.attributesOfItem(atPath: resolved.path))?[.modificationDate] as? Date else { return nil }
        return "\(resolved.path)#\(date.timeIntervalSince1970)"
    }

    private final class Confirmed: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: Set<String> = []
        func contains(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return keys.contains(key) }
        func insert(_ key: String) { lock.lock(); keys.insert(key); lock.unlock() }
    }
}

// MARK: - Locating the tool

/// GUI apps don't get the shell's PATH, so the usual install folders are searched first and the
/// user's login shell is asked last. Results are cached for the app's lifetime.
enum CLIToolLocator {
    private static let cache = Cache()

    static func locate(_ tool: CLIAgentTool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        if let cached = cache.value(for: tool) { return cached }
        let found = candidates(for: tool, home: home).first(where: isExecutable) ?? loginShellLookup(tool.executableName)
        if let found { cache.store(found, for: tool) }
        return found
    }

    static func candidates(for tool: CLIAgentTool, home: URL) -> [URL] {
        let name = tool.executableName
        var folders = [
            home.appending(path: ".local/bin"),
            home.appending(path: ".claude/local"),
            URL(filePath: "/opt/homebrew/bin"),
            URL(filePath: "/usr/local/bin"),
            home.appending(path: ".npm-global/bin"),
            home.appending(path: ".bun/bin"),
            home.appending(path: ".volta/bin"),
            home.appending(path: "Library/pnpm")
        ]
        // nvm: newest Node version first.
        let nvm = home.appending(path: ".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            folders += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { nvm.appending(path: $0).appending(path: "bin") }
        }
        return folders.map { $0.appending(path: name) }
    }

    static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static func loginShellLookup(_ name: String) -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-l", "-c", "command -v \(name)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").reversed()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("/") }
            .map { URL(filePath: $0) }
            .flatMap { isExecutable($0) ? $0 : nil }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [CLIAgentTool: URL] = [:]
        func value(for tool: CLIAgentTool) -> URL? { lock.lock(); defer { lock.unlock() }; return paths[tool] }
        func store(_ url: URL, for tool: CLIAgentTool) { lock.lock(); paths[tool] = url; lock.unlock() }
    }
}

// MARK: - Running

struct CLIProcessResult: Equatable, Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
}

protocol CLIProcessRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL,
        timeout: TimeInterval
    ) async throws -> CLIProcessResult
}

struct FoundationCLIProcessRunner: CLIProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL,
        timeout: TimeInterval
    ) async throws -> CLIProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.environment(for: executable)
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        let collected = Collected()
        output.fileHandleForReading.readabilityHandler = { collected.appendOut($0.availableData) }
        error.fileHandleForReading.readabilityHandler = { collected.appendErr($0.availableData) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLIProcessResult, Error>) in
                let once = Once()
                process.terminationHandler = { finished in
                    output.fileHandleForReading.readabilityHandler = nil
                    error.fileHandleForReading.readabilityHandler = nil
                    collected.appendOut(output.fileHandleForReading.readDataToEndOfFile())
                    collected.appendErr(error.fileHandleForReading.readDataToEndOfFile())
                    once.run {
                        if collected.timedOut { continuation.resume(throwing: AgentError.timeout); return }
                        continuation.resume(returning: CLIProcessResult(
                            exitCode: finished.terminationStatus,
                            standardOutput: collected.out,
                            standardError: collected.err
                        ))
                    }
                }
                do {
                    try process.run()
                } catch {
                    once.run { continuation.resume(throwing: error) }
                    return
                }
                input.fileHandleForWriting.write(Data(standardInput.utf8))
                try? input.fileHandleForWriting.close()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    collected.timedOut = true
                    process.terminate()
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// The tool's own folder goes first on PATH so scripts find their runtime (`node` for nvm
    /// installs).
    static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let folders = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        environment["PATH"] = (folders + [environment["PATH"] ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var outData = Data(), errData = Data()
        private var _timedOut = false
        var timedOut: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _timedOut }
            set { lock.lock(); _timedOut = newValue; lock.unlock() }
        }
        func appendOut(_ data: Data) { lock.lock(); outData.append(data); lock.unlock() }
        func appendErr(_ data: Data) { lock.lock(); errData.append(data); lock.unlock() }
        var out: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
        var err: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock()
            guard !done else { lock.unlock(); return }
            done = true
            lock.unlock()
            body()
        }
    }
}

// MARK: - Provider

struct CLIAgentProvider: LanguageModelProvider {
    /// Process start-up and sign-in checks take seconds on top of the model's own time.
    static let minimumTimeout: TimeInterval = 60

    let tool: CLIAgentTool
    var model: String?
    private let runner: any CLIProcessRunning
    private let locate: @Sendable (CLIAgentTool) -> URL?
    /// Tests pass a fresh key so each run checks Codex again; `nil` uses the installed file.
    private let safetyCacheKey: String?

    init(
        tool: CLIAgentTool,
        model: String? = nil,
        runner: any CLIProcessRunning = FoundationCLIProcessRunner(),
        locate: @escaping @Sendable (CLIAgentTool) -> URL? = { CLIToolLocator.locate($0) },
        safetyCacheKey: String? = nil
    ) {
        self.tool = tool
        self.model = model
        self.runner = runner
        self.locate = locate
        self.safetyCacheKey = safetyCacheKey
    }

    var isAvailable: Bool {
        get async { locate(tool) != nil }
    }

    func generate(_ request: AgentRequest) async throws -> String {
        guard let executable = locate(tool) else { throw AgentError.toolNotFound(tool.kind) }
        let folder = FileManager.default.temporaryDirectory.appending(path: "crenel-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        if tool == .codex {
            try await CodexSafety.verify(executable: executable, runner: runner, workingDirectory: folder, cacheKey: safetyCacheKey)
        }

        let result = try await runner.run(
            executable: executable,
            arguments: tool.arguments(systemInstructions: request.systemInstructions, model: model),
            standardInput: request.userContent,
            workingDirectory: folder,
            timeout: max(request.timeout, Self.minimumTimeout)
        )
        try Task.checkCancellation()
        guard result.exitCode == 0 else { throw Self.error(for: result, kind: tool.kind) }

        let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentError.invalidResponse }
        return trimmed
    }

    /// Maps a failed run to a short reason. The tool's output is never shown or logged: it can
    /// echo the user's text.
    static func error(for result: CLIProcessResult, kind: AgentProviderKind) -> AgentError {
        let text = (result.standardError + "\n" + result.standardOutput).lowercased()
        if ["not logged in", "log in", "login", "authenticat", "unauthorized", "api key"].contains(where: text.contains) {
            return .authentication(kind)
        }
        if ["rate limit", "usage limit", "too many requests"].contains(where: text.contains) {
            return .rateLimited(kind)
        }
        if ["model", "not found", "does not exist"].allSatisfy(text.contains) || text.contains("invalid model") {
            return .modelUnavailable(kind)
        }
        if ["network", "connection", "offline", "timed out"].contains(where: text.contains) {
            return .network(kind)
        }
        return .serverError(kind)
    }
}
