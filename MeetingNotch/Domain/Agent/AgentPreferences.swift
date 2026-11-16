import Foundation

/// Which language model the dictation agent uses. `.off` keeps only the deterministic pass.
enum AgentProviderKind: String, Codable, CaseIterable, Equatable, Sendable {
    /// Recommended default: the Anthropic key if there is one, else the OpenAI key, else on-device.
    /// Resolved to a concrete provider by `AgentProviderResolver` before any request is built.
    case automatic
    case onDevice
    case openAI
    case anthropic
    case off

    var displayName: String {
        switch self {
        case .automatic: "Otomatik (önerilen)"
        case .onDevice: "Cihaz içi (Apple Intelligence)"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .off: "Kapalı"
        }
    }

    var isCloud: Bool { self == .openAI || self == .anthropic }

    /// Model used when the user has not set an override. `nil` for providers without model choice.
    var defaultModelID: String? {
        switch self {
        case .openAI: OpenAIProvider.defaultModel
        case .anthropic: AnthropicProvider.defaultModel
        case .automatic, .onDevice, .off: nil
        }
    }

    /// Unknown stored values (from a newer build) decode to the default instead of failing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentProviderKind(rawValue: raw) ?? .automatic
    }
}

/// Standalone agent settings; designed to be embedded into `AppPreferences` by the integrator.
struct AgentPreferences: Codable, Equatable, Sendable {
    var provider: AgentProviderKind
    var openAIModelID: String?
    var anthropicModelID: String?
    var cleanupEnabled: Bool
    var commandModeEnabled: Bool

    static let `default` = AgentPreferences()

    init(
        provider: AgentProviderKind = .automatic,
        openAIModelID: String? = nil,
        anthropicModelID: String? = nil,
        cleanupEnabled: Bool = true,
        commandModeEnabled: Bool = true
    ) {
        self.provider = provider
        self.openAIModelID = openAIModelID
        self.anthropicModelID = anthropicModelID
        self.cleanupEnabled = cleanupEnabled
        self.commandModeEnabled = commandModeEnabled
    }

    /// Effective model id: a non-blank override, otherwise the provider default.
    func modelID(for kind: AgentProviderKind) -> String? {
        let override: String? = switch kind {
        case .openAI: openAIModelID
        case .anthropic: anthropicModelID
        case .automatic, .onDevice, .off: nil
        }
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return kind.defaultModelID
    }

    private enum CodingKeys: String, CodingKey {
        case provider, openAIModelID, anthropicModelID, cleanupEnabled, commandModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AgentPreferences()
        provider = try container.decodeIfPresent(AgentProviderKind.self, forKey: .provider) ?? fallback.provider
        openAIModelID = try container.decodeIfPresent(String.self, forKey: .openAIModelID)
        anthropicModelID = try container.decodeIfPresent(String.self, forKey: .anthropicModelID)
        cleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? fallback.cleanupEnabled
        commandModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .commandModeEnabled)
            ?? fallback.commandModeEnabled
    }
}
