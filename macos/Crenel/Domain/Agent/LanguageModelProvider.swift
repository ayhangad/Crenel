import Foundation

/// A single, tool-less text generation request. The model never receives tools or actions;
/// `userContent` carries user data wrapped in delimiters and must be treated as data.
struct AgentRequest: Equatable, Sendable {
    var systemInstructions: String
    var userContent: String
    var maxOutputTokens: Int
    /// Only honored by providers that support sampling control (on-device). Cloud reasoning
    /// models reject custom sampling, so they ignore it.
    var temperature: Double?
    var timeout: TimeInterval

    init(
        systemInstructions: String,
        userContent: String,
        maxOutputTokens: Int = 1_024,
        temperature: Double? = nil,
        timeout: TimeInterval = 4
    ) {
        self.systemInstructions = systemInstructions
        self.userContent = userContent
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.timeout = timeout
    }
}

protocol LanguageModelProvider: Sendable {
    func generate(_ request: AgentRequest) async throws -> String
    var isAvailable: Bool { get async }
}

enum OnDeviceUnavailableReason: Equatable, Sendable {
    case unsupportedOperatingSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown

    var message: String {
        switch self {
        case .unsupportedOperatingSystem:
            "The on-device model requires macOS 26 or later."
        case .deviceNotEligible:
            "This Mac doesn’t support the Apple Intelligence on-device model."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is off. Turn it on in System Settings → Apple Intelligence & Siri."
        case .modelNotReady:
            "The Apple Intelligence model isn’t ready yet; it may still be downloading. Try again shortly."
        case .unknown:
            "The on-device model is unavailable right now."
        }
    }
}

/// Typed agent failure. Messages never contain keys, request text or provider response bodies.
enum AgentError: Error, LocalizedError, Equatable, Sendable {
    case providerDisabled
    case missingKey(AgentProviderKind)
    case authentication(AgentProviderKind)
    case modelUnavailable(AgentProviderKind)
    case quotaExceeded(AgentProviderKind)
    case rateLimited(AgentProviderKind)
    case serverError(AgentProviderKind)
    case network(AgentProviderKind)
    case invalidRequest(AgentProviderKind)
    case timeout
    case invalidResponse
    case refused
    case inputTooLong
    case unsupportedLanguage
    case onDeviceUnavailable(OnDeviceUnavailableReason)
    /// The command-line tool for this provider isn't installed (or can't be found).
    case toolNotFound(AgentProviderKind)

    var errorDescription: String? {
        switch self {
        case .providerDisabled:
            "AI editing is off."
        case .missingKey(let kind):
            "No \(kind.displayName) API key. Add one in Settings."
        case .authentication(let kind) where kind.usesLocalCLI:
            "\(kind.displayName) isn’t signed in. Open Terminal, run “claude” and sign in."
        case .authentication(let kind):
            "Couldn’t verify the \(kind.displayName) key. Check it in Settings."
        case .modelUnavailable(let kind):
            "Can’t reach the selected \(kind.displayName) model. Check the model name."
        case .quotaExceeded(let kind):
            "\(kind.displayName) balance or usage quota is exhausted."
        case .rateLimited(let kind):
            "\(kind.displayName) rate limit reached. Try again shortly."
        case .serverError(let kind):
            "\(kind.displayName) isn’t responding. Try again later."
        case .network(let kind):
            "Can’t reach \(kind.displayName). Check your internet connection."
        case .invalidRequest(let kind):
            "\(kind.displayName) rejected the request."
        case .timeout:
            "The AI didn’t respond in time; the text was used unedited."
        case .invalidResponse:
            "The AI response wasn’t usable; the text was used unedited."
        case .refused:
            "The model refused to process this text."
        case .inputTooLong:
            "The text is too long for the model."
        case .unsupportedLanguage:
            "The on-device model doesn’t support this language."
        case .onDeviceUnavailable(let reason):
            reason.message
        case .toolNotFound(let kind):
            "\(kind.displayName) isn’t installed on this Mac."
        }
    }
}
