import Foundation

/// Anthropic Messages API provider over raw HTTP (no official Swift SDK).
struct AnthropicProvider: LanguageModelProvider {
    static let defaultModel = "claude-haiku-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that accept server-side refusal fallbacks (`fallbacks: "default"`).
    static let fallbackModels: Set<String> = [
        "claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"
    ]

    private let keys: any APIKeyRepository
    private let http: any AgentHTTPClient
    let model: String

    init(
        model: String = AnthropicProvider.defaultModel,
        keys: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.anthropicService),
        http: any AgentHTTPClient = URLSessionAgentHTTPClient()
    ) {
        self.model = model
        self.keys = keys
        self.http = http
    }

    var isAvailable: Bool {
        get async {
            guard let key = try? await keys.apiKey() else { return false }
            return !key.isEmpty
        }
    }

    func generate(_ request: AgentRequest) async throws -> String {
        guard let key = try? await keys.apiKey(), !key.isEmpty else {
            throw AgentError.missingKey(.anthropic)
        }
        let urlRequest = try makeURLRequest(request, apiKey: key)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: urlRequest)
        } catch {
            throw AgentHTTPErrorMapper.transportError(error, provider: .anthropic)
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 529 { throw AgentError.serverError(.anthropic) }
            throw AgentHTTPErrorMapper.error(status: response.statusCode, data: data, provider: .anthropic)
        }
        return try Self.parse(data)
    }

    func makeURLRequest(_ request: AgentRequest, apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // API version 2026-10-21 rejects temperature/top_p/top_k, so sampling is never sent.
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxOutputTokens,
            "system": request.systemInstructions,
            "messages": [["role": "user", "content": request.userContent]]
        ]
        if Self.supportsEffort(model) {
            // Short rewrite task: low effort keeps latency inside the dictation time budget.
            body["output_config"] = ["effort": "low"]
        }
        if Self.fallbackModels.contains(model) {
            urlRequest.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    static func supportsEffort(_ model: String) -> Bool {
        !(model.hasPrefix("claude-haiku-4") || model.hasPrefix("claude-sonnet-4-5") || model.hasPrefix("claude-3"))
    }

    static func parse(_ data: Data) throws -> String {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else {
            throw AgentError.invalidResponse
        }
        switch message.stopReason {
        case "refusal": throw AgentError.refused
        case "max_tokens": throw AgentError.invalidResponse
        default: break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidResponse
        }
        return text
    }

    private struct Message: Decodable {
        let content: [Block]
        let stopReason: String?
        struct Block: Decodable { let type: String; let text: String? }
        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }
}
