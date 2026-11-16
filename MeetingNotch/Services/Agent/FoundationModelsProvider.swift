import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence on-device model. Text never leaves the Mac.
struct FoundationModelsProvider: LanguageModelProvider {
    enum Availability: Equatable, Sendable {
        case available
        case unavailable(OnDeviceUnavailableReason)
    }

    init() {}

    var availability: Availability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .unavailable(.unsupportedOperatingSystem) }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(Self.map(reason))
        }
        #else
        return .unavailable(.unsupportedOperatingSystem)
        #endif
    }

    var isAvailable: Bool {
        get async { availability == .available }
    }

    func generate(_ request: AgentRequest) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw AgentError.onDeviceUnavailable(.unsupportedOperatingSystem)
        }
        if case .unavailable(let reason) = availability {
            throw AgentError.onDeviceUnavailable(reason)
        }
        // A fresh session per request: no transcript history is carried between dictations.
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: request.systemInstructions
        )
        let options = GenerationOptions(
            temperature: request.temperature,
            maximumResponseTokens: request.maxOutputTokens
        )
        do {
            let response = try await session.respond(to: request.userContent, options: options)
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AgentError.invalidResponse
        }
        #else
        throw AgentError.onDeviceUnavailable(.unsupportedOperatingSystem)
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    static func map(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> OnDeviceUnavailableReason {
        switch reason {
        case .deviceNotEligible: .deviceNotEligible
        case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
        case .modelNotReady: .modelNotReady
        @unknown default: .unknown
        }
    }

    @available(macOS 26.0, *)
    static func map(_ error: LanguageModelSession.GenerationError) -> AgentError {
        switch error {
        case .guardrailViolation, .refusal: .refused
        case .exceededContextWindowSize: .inputTooLong
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .assetsUnavailable: .onDeviceUnavailable(.modelNotReady)
        case .rateLimited, .concurrentRequests: .serverError(.onDevice)
        default: .invalidResponse
        }
    }
    #endif
}
