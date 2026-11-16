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
            "Cihaz içi model macOS 26 veya üzerini gerektirir."
        case .deviceNotEligible:
            "Bu Mac, Apple Intelligence cihaz içi modelini desteklemiyor."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence kapalı. Sistem Ayarları → Apple Intelligence ve Siri bölümünden açabilirsiniz."
        case .modelNotReady:
            "Apple Intelligence modeli henüz hazır değil; indiriliyor olabilir. Biraz sonra tekrar deneyin."
        case .unknown:
            "Cihaz içi model şu anda kullanılamıyor."
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

    var errorDescription: String? {
        switch self {
        case .providerDisabled:
            "Yapay zekâ düzenlemesi kapalı."
        case .missingKey(let kind):
            "\(kind.displayName) API anahtarı bulunamadı. Ayarlar’dan anahtarınızı ekleyin."
        case .authentication(let kind):
            "\(kind.displayName) anahtarı doğrulanamadı. Ayarlar’dan bağlantıyı kontrol edin."
        case .modelUnavailable(let kind):
            "Seçilen \(kind.displayName) modeline erişilemiyor. Model adını kontrol edin."
        case .quotaExceeded(let kind):
            "\(kind.displayName) bakiyesi veya kullanım kotası yetersiz."
        case .rateLimited(let kind):
            "\(kind.displayName) istek sınırına ulaşıldı. Biraz sonra tekrar deneyin."
        case .serverError(let kind):
            "\(kind.displayName) şu anda yanıt veremiyor. Daha sonra tekrar deneyin."
        case .network(let kind):
            "\(kind.displayName) sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edin."
        case .invalidRequest(let kind):
            "\(kind.displayName) isteği kabul etmedi."
        case .timeout:
            "Yapay zekâ zamanında yanıt vermedi; metin düzenlenmeden kullanıldı."
        case .invalidResponse:
            "Yapay zekâ yanıtı kullanılabilir değildi; metin düzenlenmeden kullanıldı."
        case .refused:
            "Model bu metni işlemeyi reddetti."
        case .inputTooLong:
            "Metin, modelin işleyebileceği uzunluğu aşıyor."
        case .unsupportedLanguage:
            "Cihaz içi model bu dili desteklemiyor."
        case .onDeviceUnavailable(let reason):
            reason.message
        }
    }
}
