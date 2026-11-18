import Foundation
import XCTest
@testable import Crenel

final class AgentProviderTests: XCTestCase {
    private let request = AgentRequest(
        systemInstructions: "SYSTEM",
        userContent: "<transcript>\nmerhaba dünya\n</transcript>",
        maxOutputTokens: 900,
        temperature: 0.3,
        timeout: 4
    )

    // MARK: OpenAI

    func testOpenAIBuildsResponsesRequestWithKeyAndNoSampling() async throws {
        let http = FakeAgentHTTPClient(responses: [.status(200, Self.openAIBody(text: "Merhaba dünya."))])
        let provider = OpenAIProvider(keys: FakeAgentKeys("sk-test"), http: http)

        let output = try await provider.generate(request)

        XCTAssertEqual(output, "Merhaba dünya.")
        let firstRequest = await http.requests.first
        let sent = try XCTUnwrap(firstRequest)
        XCTAssertEqual(sent.url, URL(string: "https://api.openai.com/v1/responses"))
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(sent.timeoutInterval, 4)
        let body = try Self.json(sent)
        XCTAssertEqual(body["model"] as? String, "gpt-5-mini")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["instructions"] as? String, "SYSTEM")
        XCTAssertEqual(body["input"] as? String, request.userContent)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 900)
        XCTAssertNil(body["temperature"])
    }

    func testOpenAIUsesModelOverride() async throws {
        let http = FakeAgentHTTPClient(responses: [.status(200, Self.openAIBody(text: "x"))])
        let preferences = AgentPreferences(provider: .openAI, openAIModelID: " gpt-custom ")
        let provider = try XCTUnwrap(AgentProviderFactory.makeProvider(
            for: preferences, openAIKeys: FakeAgentKeys("k"), anthropicKeys: FakeAgentKeys(nil), http: http
        ))
        _ = try await provider.generate(request)
        let firstRequest = await http.requests.first
        let body = try Self.json(try XCTUnwrap(firstRequest))
        XCTAssertEqual(body["model"] as? String, "gpt-custom")
    }

    func testOpenAIErrorMapping() async {
        let cases: [(FakeAgentHTTPClient.Reply, AgentError)] = [
            (.status(401, Data()), .authentication(.openAI)),
            (.status(404, Data()), .modelUnavailable(.openAI)),
            (.status(429, Data(#"{"error":{"code":"insufficient_quota"}}"#.utf8)), .quotaExceeded(.openAI)),
            (.status(429, Data(#"{"error":{"code":"rate_limit_exceeded"}}"#.utf8)), .rateLimited(.openAI)),
            (.status(500, Data()), .serverError(.openAI)),
            (.status(503, Data()), .serverError(.openAI)),
            (.failure(URLError(.timedOut)), .timeout),
            (.failure(URLError(.notConnectedToInternet)), .network(.openAI)),
            (.status(200, Data(#"{"status":"incomplete","output":[]}"#.utf8)), .invalidResponse)
        ]
        for (reply, expected) in cases {
            let provider = OpenAIProvider(keys: FakeAgentKeys("k"), http: FakeAgentHTTPClient(responses: [reply]))
            await assertThrows(expected) { try await provider.generate(self.request) }
        }
    }

    func testOpenAIMissingKeyDoesNotHitNetwork() async {
        let http = FakeAgentHTTPClient(responses: [])
        let provider = OpenAIProvider(keys: FakeAgentKeys(nil), http: http)
        await assertThrows(.missingKey(.openAI)) { try await provider.generate(self.request) }
        let count = await http.requests.count
        XCTAssertEqual(count, 0)
        let available = await provider.isAvailable
        XCTAssertFalse(available)
    }

    // MARK: Anthropic

    func testAnthropicBuildsMessagesRequest() async throws {
        let http = FakeAgentHTTPClient(responses: [.status(200, Self.anthropicBody(text: "Merhaba dünya."))])
        let provider = AnthropicProvider(model: "claude-opus-5-5", keys: FakeAgentKeys("sk-ant-test"), http: http)

        let output = try await provider.generate(request)

        XCTAssertEqual(output, "Merhaba dünya.")
        let firstRequest = await http.requests.first
        let sent = try XCTUnwrap(firstRequest)
        XCTAssertEqual(sent.url, URL(string: "https://api.anthropic.com/v1/messages"))
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"))
        let body = try Self.json(sent)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 900)
        XCTAssertEqual(body["system"] as? String, "SYSTEM")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["thinking"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, request.userContent)
    }

    func testAnthropicOmitsFallbackForModelsWithoutIt() async throws {
        let http = FakeAgentHTTPClient(responses: [.status(200, Self.anthropicBody(text: "x"))])
        let provider = AnthropicProvider(model: "claude-haiku-5-5", keys: FakeAgentKeys("k"), http: http)
        _ = try await provider.generate(request)
        let firstRequest = await http.requests.first
        let sent = try XCTUnwrap(firstRequest)
        XCTAssertNil(sent.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertNil(try Self.json(sent)["fallbacks"])
        XCTAssertEqual(AnthropicProvider.defaultModel, "claude-haiku-5-5")
        XCTAssertEqual((try Self.json(sent)["output_config"] as? [String: Any])?["effort"] as? String, "low")
    }

    func testAnthropicJoinsTextBlocksAndSkipsThinking() throws {
        let data = Data("""
        {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Bir "},{"type":"text","text":"iki."}],
         "stop_reason":"end_turn"}
        """.utf8)
        XCTAssertEqual(try AnthropicProvider.parse(data), "Bir iki.")
    }

    func testAnthropicErrorMapping() async {
        let cases: [(FakeAgentHTTPClient.Reply, AgentError)] = [
            (.status(401, Data()), .authentication(.anthropic)),
            (.status(403, Data()), .authentication(.anthropic)),
            (.status(404, Data()), .modelUnavailable(.anthropic)),
            (.status(429, Data()), .rateLimited(.anthropic)),
            (.status(400, Data()), .invalidRequest(.anthropic)),
            (.status(500, Data()), .serverError(.anthropic)),
            (.status(529, Data()), .serverError(.anthropic)),
            (.failure(URLError(.timedOut)), .timeout),
            (.status(200, Self.anthropicBody(text: "", stopReason: "refusal")), .refused),
            (.status(200, Self.anthropicBody(text: "yarım", stopReason: "max_tokens")), .invalidResponse),
            (.status(200, Data("not json".utf8)), .invalidResponse)
        ]
        for (reply, expected) in cases {
            let provider = AnthropicProvider(keys: FakeAgentKeys("k"), http: FakeAgentHTTPClient(responses: [reply]))
            await assertThrows(expected) { try await provider.generate(self.request) }
        }
    }

    func testAnthropicKeychainServiceFollowsExistingPrefix() {
        XCTAssertEqual(KeychainAPIKeyRepository.anthropicService, "gad.Crenel.anthropic-api-key")
    }

    func testErrorMessagesAreReadableAndNeverEchoSecrets() {
        let errors: [AgentError] = [
            .missingKey(.anthropic), .authentication(.openAI), .rateLimited(.anthropic), .serverError(.openAI),
            .timeout, .onDeviceUnavailable(.appleIntelligenceNotEnabled), .onDeviceUnavailable(.deviceNotEligible),
            .onDeviceUnavailable(.modelNotReady)
        ]
        for error in errors {
            let message = try? XCTUnwrap(error.errorDescription)
            XCTAssertFalse(message?.isEmpty ?? true)
            XCTAssertFalse(message?.contains("sk-") ?? true)
        }
        XCTAssertTrue(AgentError.onDeviceUnavailable(.appleIntelligenceNotEnabled).errorDescription!
            .contains("Apple Intelligence is off"))
    }

    // MARK: Preferences

    func testPreferencesDefaultsAndTolerantDecoding() throws {
        XCTAssertEqual(AgentPreferences.default.provider, .onDevice)
        XCTAssertTrue(AgentPreferences.default.cleanupEnabled)
        XCTAssertTrue(AgentPreferences.default.commandModeEnabled)

        let decoded = try JSONDecoder().decode(AgentPreferences.self, from: Data(#"{"provider":"future"}"#.utf8))
        XCTAssertEqual(decoded, .default)

        let custom = AgentPreferences(provider: .anthropic, anthropicModelID: "claude-sonnet-5-5",
                                      cleanupEnabled: false, commandModeEnabled: false)
        let roundTrip = try JSONDecoder().decode(AgentPreferences.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(roundTrip, custom)
        XCTAssertEqual(roundTrip.modelID(for: .anthropic), "claude-sonnet-5-5")
        XCTAssertEqual(AgentPreferences.default.modelID(for: .anthropic), "claude-haiku-5-5")
        XCTAssertEqual(AgentPreferences.default.modelID(for: .openAI), "gpt-5-mini")
        XCTAssertNil(AgentProviderFactory.makeProvider(for: AgentPreferences(provider: .off)))
    }

    // MARK: Helpers

    private func assertThrows(
        _ expected: AgentError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @escaping () async throws -> String
    ) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AgentError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected \(error)", file: file, line: line)
        }
    }

    private static func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    static func openAIBody(text: String) -> Data {
        let object: [String: Any] = [
            "status": "completed",
            "output": [
                ["type": "reasoning", "content": []],
                ["type": "message", "content": [["type": "output_text", "text": text]]]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func anthropicBody(text: String, stopReason: String = "end_turn") -> Data {
        let object: [String: Any] = [
            "content": text.isEmpty ? [] : [["type": "text", "text": text]],
            "stop_reason": stopReason
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

actor FakeAgentHTTPClient: AgentHTTPClient {
    enum Reply: Sendable {
        case status(Int, Data)
        case failure(URLError)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(responses: [Reply]) {
        replies = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case .status(let code, let data):
            return (data, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        case .failure(let error):
            throw error
        }
    }
}

final class AgentProviderResolverTests: XCTestCase {
    @MainActor
    func testLateAutomaticResolutionCannotReplaceExplicitPreferences() async throws {
        var release: CheckedContinuation<AgentPreferences, Never>?
        let entered = expectation(description: "resolver suspended")
        let selection = AgentSelectionResolution { _ in
            await withCheckedContinuation {
                release = $0
                entered.fulfill()
            }
        }
        var current = CrenelPreferences.default
        current.agent.provider = .automatic
        var delivered: [AgentProviderKind] = []
        let pending = selection.apply(current, microphoneID: "old") { value, _ in delivered.append(value.agent.provider) }
        await fulfillment(of: [entered], timeout: 2)
        current.agent.provider = .onDevice
        selection.apply(current, microphoneID: "new") { value, _ in delivered.append(value.agent.provider) }
        release?.resume(returning: AgentPreferences(provider: .openAI))
        await pending?.value
        XCTAssertEqual(delivered, [.automatic, .onDevice])
    }

    func testAutomaticPrefersAnthropicThenOpenAIThenOnDevice() async {
        let auto = AgentPreferences(provider: .automatic)
        let both = await AgentProviderResolver.resolve(auto, anthropicKeys: FakeAgentKeys("a"), openAIKeys: FakeAgentKeys("o"))
        XCTAssertEqual(both.provider, .anthropic)
        let openAIOnly = await AgentProviderResolver.resolve(auto, anthropicKeys: FakeAgentKeys(nil), openAIKeys: FakeAgentKeys("o"))
        XCTAssertEqual(openAIOnly.provider, .openAI)
        let none = await AgentProviderResolver.resolve(auto, anthropicKeys: FakeAgentKeys("  "), openAIKeys: FakeAgentKeys(nil))
        XCTAssertEqual(none.provider, .onDevice)
    }

    func testExplicitChoiceIsNeverOverridden() async {
        let chosen = AgentPreferences(provider: .onDevice)
        let resolved = await AgentProviderResolver.resolve(chosen, anthropicKeys: FakeAgentKeys("a"), openAIKeys: FakeAgentKeys("o"))
        XCTAssertEqual(resolved.provider, .onDevice)
    }
}

struct FakeAgentKeys: APIKeyRepository {
    let key: String?
    init(_ key: String?) { self.key = key }
    func apiKey() async throws -> String? { key }
    func saveAPIKey(_ apiKey: String) async throws {}
    func deleteAPIKey() async throws {}
}
