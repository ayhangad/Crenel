import Foundation

struct TranscriptionProviderCapabilities: Equatable, Sendable {
    let supportedFileExtensions: Set<String>
    let maximumFileSizeBytes: Int64
    let supportsDiarization: Bool
    let supportsAutomaticLanguageDetection: Bool

    init(
        supportedFileExtensions: Set<String>,
        maximumFileSizeBytes: Int64,
        supportsDiarization: Bool,
        supportsAutomaticLanguageDetection: Bool
    ) {
        self.supportedFileExtensions = Set(
            supportedFileExtensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        )
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.supportsDiarization = supportsDiarization
        self.supportsAutomaticLanguageDetection = supportsAutomaticLanguageDetection
    }
}

struct TranscriptionRequest: Equatable, Sendable {
    let audioFileURL: URL
    let languageCode: String?
    let requestsDiarization: Bool
    let idempotencyKey: UUID

    init(
        audioFileURL: URL,
        languageCode: String?,
        requestsDiarization: Bool = true,
        idempotencyKey: UUID = UUID()
    ) {
        self.audioFileURL = audioFileURL
        self.languageCode = languageCode
        self.requestsDiarization = requestsDiarization
        self.idempotencyKey = idempotencyKey
    }
}

struct TranscriptionResult: Equatable, Sendable {
    let providerID: TranscriptionProviderID
    let transcript: Transcript
}

typealias TranscriptionUploadProgress = @Sendable (Double) -> Void

protocol TranscriptionProvider: Sendable {
    var id: TranscriptionProviderID { get }
    var capabilities: TranscriptionProviderCapabilities { get }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult
}

enum TranscriptionFeature: String, Equatable, Sendable {
    case diarization
    case automaticLanguageDetection
}

enum TranscriptionFileValidationFailure: String, Equatable, Sendable {
    case missing
    case unreadable
    case notRegularFile
    case empty
    case unsupportedFormat
    case tooLarge
}

enum TranscriptionServiceError: Error, Equatable, Sendable {
    case invalidFile(TranscriptionFileValidationFailure)
    case unsupportedFeature(TranscriptionFeature)
    case authentication
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case networkUnavailable
    case providerUnavailable
    case invalidResponse
    case cancelled

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .timeout, .networkUnavailable, .providerUnavailable:
            true
        case .invalidFile, .unsupportedFeature, .authentication, .invalidResponse, .cancelled:
            false
        }
    }

    var appFailure: AppFailure {
        switch self {
        case .authentication:
            .provider(
                "API anahtarını ve Speech-to-Text yetkisini Ayarlar'dan kontrol edin.",
                credentialsInvalid: true
            )
        case .rateLimited:
            .provider("Provider istek sınırına ulaştı. Bir süre sonra tekrar deneyin.")
        case .timeout:
            .network("Transkripsiyon isteği zaman aşımına uğradı. Tekrar deneyin.")
        case .networkUnavailable:
            .network("İnternet bağlantısını kontrol edip tekrar deneyin.")
        case .providerUnavailable:
            .provider("Transkripsiyon servisine şu anda ulaşılamıyor. Tekrar deneyin.")
        case .invalidResponse:
            .decoding("Provider yanıtı beklenen biçimde değildi. Tekrar deneyin.")
        case .invalidFile:
            .fileSystem("Ses dosyası provider yüklemesine uygun değil.")
        case .unsupportedFeature:
            .provider("Seçili provider istenen transkripsiyon özelliğini desteklemiyor.", credentialsInvalid: false)
        case .cancelled:
            .provider("Transkripsiyon işlemi iptal edildi.", credentialsInvalid: false)
        }
    }
}

enum TranscriptionErrorNormalizer {
    static func normalize(_ error: Error) -> TranscriptionServiceError {
        if let error = error as? TranscriptionServiceError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        guard let urlError = error as? URLError else {
            return .providerUnavailable
        }

        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
            return .networkUnavailable
        default:
            return .providerUnavailable
        }
    }

    static func normalizeHTTPStatus(
        _ statusCode: Int,
        retryAfter: TimeInterval? = nil
    ) -> TranscriptionServiceError? {
        switch statusCode {
        case 200..<300:
            nil
        case 401, 403:
            .authentication
        case 408:
            .timeout
        case 429:
            .rateLimited(retryAfter: retryAfter)
        case 500..<600:
            .providerUnavailable
        default:
            .invalidResponse
        }
    }
}
