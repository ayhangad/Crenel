import Foundation

/// Minimal HTTP seam for agent providers so tests can inject fakes.
protocol AgentHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionAgentHTTPClient: AgentHTTPClient {
    private let session: URLSession

    /// Ephemeral by default: dictated text and responses are never written to the URL cache.
    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse
        }
        return (data, http)
    }
}

enum AgentHTTPErrorMapper {
    /// Maps non-2xx statuses. Only a fixed provider error code is inspected; bodies are never surfaced.
    static func error(status: Int, data: Data, provider: AgentProviderKind) -> AgentError {
        switch status {
        case 401, 403: return .authentication(provider)
        case 404: return .modelUnavailable(provider)
        case 408: return .timeout
        case 429:
            return errorCode(in: data) == "insufficient_quota" ? .quotaExceeded(provider) : .rateLimited(provider)
        case 400...499: return .invalidRequest(provider)
        default: return .serverError(provider)
        }
    }

    static func transportError(_ error: Error, provider: AgentProviderKind) -> Error {
        if error is CancellationError { return CancellationError() }
        if let agent = error as? AgentError { return agent }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return CancellationError()
            case .timedOut: return AgentError.timeout
            default: return AgentError.network(provider)
            }
        }
        return AgentError.network(provider)
    }

    private static func errorCode(in data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        return error?["code"] as? String ?? error?["type"] as? String
    }
}
