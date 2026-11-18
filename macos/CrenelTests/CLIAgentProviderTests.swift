import XCTest
@testable import Crenel

final class CLIAgentProviderTests: XCTestCase {
    private final class FakeRunner: CLIProcessRunning, @unchecked Sendable {
        var result = CLIProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        private(set) var arguments: [String] = []
        private(set) var input = ""
        private(set) var timeout: TimeInterval = 0

        func run(executable: URL, arguments: [String], standardInput: String, workingDirectory: URL, timeout: TimeInterval) async throws -> CLIProcessResult {
            self.arguments = arguments
            self.input = standardInput
            self.timeout = timeout
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
        let settings = try XCTUnwrap(runner.arguments.firstIndex(of: "--setting-sources"))
        XCTAssertEqual(runner.arguments[settings + 1], "")
        XCTAssertTrue(runner.arguments.contains("--strict-mcp-config"))
        let system = try XCTUnwrap(runner.arguments.firstIndex(of: "--system-prompt"))
        XCTAssertEqual(runner.arguments[system + 1], "Fix spelling.")
        XCTAssertTrue(runner.arguments.contains("--no-session-persistence"))
        XCTAssertGreaterThanOrEqual(runner.timeout, CLIAgentProvider.minimumTimeout)
    }

    func testRetiredCodexSelectionResolvesToTheDevice() throws {
        let choice = try JSONDecoder().decode(AgentProviderKind.self, from: Data(#""codex""#.utf8))
        XCTAssertEqual(choice, .onDevice)
        XCTAssertFalse(CLIAgentTool.allCases.contains { $0.executableName == "codex" })
        XCTAssertTrue(AgentProviderFactory.makeProvider(for: AgentPreferences(provider: choice)) is FoundationModelsProvider)
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

        XCTAssertEqual(CLIAgentProvider.error(for: CLIProcessResult(exitCode: 1, standardOutput: "", standardError: "Rate limit reached"), kind: .claudeCode), .rateLimited(.claudeCode))
        XCTAssertEqual(CLIAgentProvider.error(for: CLIProcessResult(exitCode: 2, standardOutput: "", standardError: "boom"), kind: .claudeCode), .serverError(.claudeCode))
        XCTAssertTrue(AgentError.authentication(.claudeCode).errorDescription?.contains("“claude”") == true)
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
        XCTAssertTrue(AgentProviderFactory.makeProvider(for: AgentPreferences(provider: .claudeCode)) is CLIAgentProvider)
        let service = try XCTUnwrap(AgentMeetingSummaryService.make(
            for: AgentPreferences(provider: .claudeCode),
            provider: CLIAgentProvider(tool: .claudeCode, runner: FakeRunner(), locate: found)
        ))
        XCTAssertEqual(service.profile, .cloud)
        XCTAssertTrue(AgentProviderKind.claudeCode.usesLocalCLI)
        XCTAssertFalse(AgentProviderKind.claudeCode.isCloud)
        XCTAssertNil(AgentPreferences(provider: .claudeCode).modelID(for: .claudeCode))
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
