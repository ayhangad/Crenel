import Foundation

/// Which language model the dictation agent uses. `.off` keeps only the deterministic pass.
enum AgentProviderKind: String, Codable, CaseIterable, Equatable, Sendable {
    /// Recommended default: the Anthropic key if there is one, else the OpenAI key, else on-device.
    /// Resolved to a concrete provider by `AgentProviderResolver` before any request is built.
    case automatic
    case onDevice
    case openAI
    case anthropic
    /// The user's signed-in Claude Code on this Mac (`claude` CLI); no API key.
    case claudeCode
    case off

    var displayName: String {
        switch self {
        case .automatic: "Automatic (recommended)"
        case .onDevice: "On-device (Apple Intelligence)"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .claudeCode: "Claude Code"
        case .off: "Off"
        }
    }

    var isCloud: Bool { self == .openAI || self == .anthropic }

    /// Runs through a command-line tool installed on this Mac. Each request starts a process
    /// (seconds, not milliseconds), so these are used for meeting summaries, not dictation.
    var usesLocalCLI: Bool { self == .claudeCode }

    /// Large context window and output budget (cloud APIs and the CLI tools behind them).
    var hasLargeContext: Bool { isCloud || usesLocalCLI }

    /// Model used when the user has not set an override. `nil` for providers without model choice.
    var defaultModelID: String? {
        switch self {
        case .openAI: OpenAIProvider.defaultModel
        case .anthropic: AnthropicProvider.defaultModel
        case .automatic, .onDevice, .claudeCode, .off: nil
        }
    }

    /// Unknown stored values (from a newer build) decode to the default instead of failing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentProviderKind(rawValue: raw) ?? .onDevice
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
        provider: AgentProviderKind = .onDevice,
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
        case .automatic, .onDevice, .claudeCode, .off: nil
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
