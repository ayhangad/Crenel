import Foundation

/// OpenAI Responses API provider (same endpoint family and default model as meeting summaries).
struct OpenAIProvider: LanguageModelProvider {
    static let defaultModel = "gpt-5-mini"
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private let keys: any APIKeyRepository
    private let http: any AgentHTTPClient
    let model: String

    init(
        model: String = OpenAIProvider.defaultModel,
        keys: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.openAIService),
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
            throw AgentError.missingKey(.openAI)
        }
        let urlRequest = try makeURLRequest(request, apiKey: key)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: urlRequest)
        } catch {
            throw AgentHTTPErrorMapper.transportError(error, provider: .openAI)
        }
        guard (200...299).contains(response.statusCode) else {
            throw AgentHTTPErrorMapper.error(status: response.statusCode, data: data, provider: .openAI)
        }
        return try Self.parse(data)
    }

    func makeURLRequest(_ request: AgentRequest, apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // gpt-5 family are reasoning models: no temperature; reasoning tokens count toward the cap.
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "store": false,
            "reasoning": ["effort": "low"],
            "max_output_tokens": request.maxOutputTokens,
            "instructions": request.systemInstructions,
            "input": request.userContent
        ] as [String: Any])
        return urlRequest
    }

    static func parse(_ data: Data) throws -> String {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw AgentError.invalidResponse
        }
        if envelope.output?.contains(where: { $0.content?.contains { $0.type == "refusal" } ?? false }) == true {
            throw AgentError.refused
        }
        guard envelope.status == "completed" else { throw AgentError.invalidResponse }
        let text = (envelope.output ?? [])
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidResponse
        }
        return text
    }

    private struct Envelope: Decodable {
        let status: String?
        let output: [Item]?
        struct Item: Decodable {
            let content: [Content]?
            struct Content: Decodable { let type: String; let text: String? }
        }
    }
}
