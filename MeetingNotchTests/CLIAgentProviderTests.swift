import XCTest
@testable import MeetingNotch

final class CLIAgentProviderTests: XCTestCase {
    private final class FakeRunner: CLIProcessRunning, @unchecked Sendable {
        var result = CLIProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        var fileAnswer: String?
        private(set) var arguments: [String] = []
        private(set) var input = ""
        private(set) var timeout: TimeInterval = 0

        func run(executable: URL, arguments: [String], standardInput: String, workingDirectory: URL, timeout: TimeInterval) async throws -> CLIProcessResult {
            self.arguments = arguments
            self.input = standardInput
            self.timeout = timeout
            if let fileAnswer, let index = arguments.firstIndex(of: "--output-last-message") {
                try fileAnswer.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
            }
            return result
        }
    }

    private let request = AgentRequest(systemInstructions: "Fix spelling.", userContent: "hello wrld", timeout: 4)
    private let found: @Sendable (CLIAgentTool) -> URL? = { _ in URL(filePath: "/usr/bin/true") }

    func testClaudeCodeRunsToolLessWithTheSystemPromptAndReadsStandardOutput() async throws {
        let runner = FakeRunner()
        runner.result.standardOutput = "  hello world\n"
        let answer = try await CLIAgentProvider(tool: .claudeCode, runner: runner, locate: found).generate(request)

        XCTAssertEqual(answer, "hello world")
        XCTAssertEqual(runner.input, "hello wrld")
        XCTAssertEqual(Array(runner.arguments.prefix(3)), ["-p", "--output-format", "text"])
        let tools = try XCTUnwrap(runner.arguments.firstIndex(of: "--tools"))
        XCTAssertEqual(runner.arguments[tools + 1], "")
        let system = try XCTUnwrap(runner.arguments.firstIndex(of: "--system-prompt"))
        XCTAssertEqual(runner.arguments[system + 1], "Fix spelling.")
        XCTAssertTrue(runner.arguments.contains("--no-session-persistence"))
        XCTAssertGreaterThanOrEqual(runner.timeout, CLIAgentProvider.minimumTimeout)
    }

    func testCodexRunsReadOnlyAndReadsTheLastMessageFile() async throws {
        let runner = FakeRunner()
        runner.result.standardOutput = "log noise"
        runner.fileAnswer = "hello world"
        let answer = try await CLIAgentProvider(tool: .codex, model: "gpt-5", runner: runner, locate: found).generate(request)

        XCTAssertEqual(answer, "hello world")
        XCTAssertEqual(runner.input, "Fix spelling.\n\nhello wrld")
        XCTAssertEqual(runner.arguments.first, "exec")
        XCTAssertEqual(runner.arguments.last, "-")
        let sandbox = try XCTUnwrap(runner.arguments.firstIndex(of: "--sandbox"))
        XCTAssertEqual(runner.arguments[sandbox + 1], "read-only")
        let model = try XCTUnwrap(runner.arguments.firstIndex(of: "--model"))
        XCTAssertEqual(runner.arguments[model + 1], "gpt-5")
    }

    func testMissingToolEmptyAnswerAndFailuresMapToAgentErrors() async {
        let missing = CLIAgentProvider(tool: .claudeCode, runner: FakeRunner(), locate: { _ in nil })
        await assertThrows(AgentError.toolNotFound(.claudeCode)) { try await missing.generate(self.request) }

        let empty = FakeRunner()
        await assertThrows(AgentError.invalidResponse) {
            try await CLIAgentProvider(tool: .claudeCode, runner: empty, locate: self.found).generate(self.request)
        }

        let signedOut = FakeRunner()
        signedOut.result = CLIProcessResult(exitCode: 1, standardOutput: "", standardError: "Not logged in · Please run /login")
        await assertThrows(AgentError.authentication(.claudeCode)) {
            try await CLIAgentProvider(tool: .claudeCode, runner: signedOut, locate: self.found).generate(self.request)
        }

        XCTAssertEqual(CLIAgentProvider.error(for: CLIProcessResult(exitCode: 1, standardOutput: "", standardError: "Rate limit reached"), kind: .codex), .rateLimited(.codex))
        XCTAssertEqual(CLIAgentProvider.error(for: CLIProcessResult(exitCode: 2, standardOutput: "", standardError: "boom"), kind: .codex), .serverError(.codex))
        XCTAssertTrue(AgentError.authentication(.codex).errorDescription?.contains("“codex”") == true)
    }

    func testCommandLineProvidersAreNotUsedForDictation() async {
        let runner = FakeRunner()
        runner.result.standardOutput = "SHOULD NOT BE USED"
        let refiner = DictationRefiner(
            preferences: AgentPreferences(provider: .claudeCode),
            provider: CLIAgentProvider(tool: .claudeCode, runner: runner, locate: found)
        )
        let outcome = await refiner.refine(
            transcript: "this is a longer test sentence",
            context: DictationContext(appBundleIdentifier: nil, appName: nil, selectedText: nil, localeIdentifier: "en-US", vocabulary: [])
        )
        guard case .insert(let text) = outcome else { return XCTFail("Expected insert") }
        XCTAssertFalse(text.contains("SHOULD NOT"))
        XCTAssertTrue(runner.arguments.isEmpty)
    }

    func testFactoryAndSummaryUseTheCommandLineToolsWithLargeContext() throws {
        XCTAssertTrue(AgentProviderFactory.makeProvider(for: AgentPreferences(provider: .codex)) is CLIAgentProvider)
        let service = try XCTUnwrap(AgentMeetingSummaryService.make(
            for: AgentPreferences(provider: .claudeCode),
            provider: CLIAgentProvider(tool: .claudeCode, runner: FakeRunner(), locate: found)
        ))
        XCTAssertEqual(service.profile, .cloud)
        XCTAssertTrue(AgentProviderKind.claudeCode.usesLocalCLI)
        XCTAssertFalse(AgentProviderKind.claudeCode.isCloud)
        XCTAssertNil(AgentPreferences(provider: .codex).modelID(for: .codex))
    }

    func testLocatorSearchesNvmFoldersNewestFirst() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "crenel-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for version in ["v18.2.0", "v22.10.1"] {
            try FileManager.default.createDirectory(at: home.appending(path: ".nvm/versions/node/\(version)/bin"), withIntermediateDirectories: true)
        }
        let paths = CLIToolLocator.candidates(for: .claudeCode, home: home).map(\.path)
        let newer = try XCTUnwrap(paths.firstIndex { $0.contains("v22.10.1") })
        let older = try XCTUnwrap(paths.firstIndex { $0.contains("v18.2.0") })
        XCTAssertLessThan(newer, older)
        XCTAssertTrue(paths.allSatisfy { $0.hasSuffix("/claude") })
    }

    /// Opt-in: runs the real Claude Code CLI if it is installed and signed in.
    func testRealClaudeCodeAnswersWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment["CRENEL_CLI_AGENT_SMOKE"] == "1" else {
            throw XCTSkip("Set CRENEL_CLI_AGENT_SMOKE=1 to run the real Claude Code CLI.")
        }
        let answer = try await CLIAgentProvider(tool: .claudeCode).generate(
            AgentRequest(systemInstructions: "Reply with the single word OK.", userContent: "Ping", timeout: 60)
        )
        XCTAssertTrue(answer.uppercased().contains("OK"))
    }

    private func assertThrows(_ expected: AgentError, _ body: () async throws -> String, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? AgentError, expected, line: line)
        }
    }
}
