import Foundation

struct TranscriptionServiceCapabilities: Equatable, Sendable {
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
    let transcript: Transcript
}

typealias TranscriptionUploadProgress = @Sendable (Double) -> Void

protocol TranscriptionServicing: Sendable {
    var capabilities: TranscriptionServiceCapabilities { get }

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
    case settingsUnavailable
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
        case .settingsUnavailable, .invalidFile, .unsupportedFeature, .authentication, .invalidResponse, .cancelled:
            false
        }
    }

    var appFailure: AppFailure {
        switch self {
        case .settingsUnavailable:
            .decoding("Processing is paused because your settings could not be read. Restore compatible settings, then retry.")
        case .authentication:
            .provider(
                "Check your API key and Speech-to-Text access in Settings.",
                credentialsInvalid: true
            )
        case .rateLimited:
            .provider("ElevenLabs rate limit reached. Try again in a while.")
        case .timeout:
            .network("The transcription request timed out. Try again.")
        case .networkUnavailable:
            .network("Check your internet connection and try again.")
        case .providerUnavailable:
            .provider("Can’t reach the transcription service right now. Try again.")
        case .invalidResponse:
            .decoding("ElevenLabs returned an unexpected response. Try again.")
        case .invalidFile:
            .fileSystem("This audio file can’t be uploaded for transcription.")
        case .unsupportedFeature:
            .provider("ElevenLabs doesn’t support the requested transcription feature.", credentialsInvalid: false)
        case .cancelled:
            .provider("Transcription was cancelled.", credentialsInvalid: false)
        }
    }
}

enum TranscriptionErrorNormalizer {
    static func normalize(_ error: Error) -> TranscriptionServiceError {
        if let error = error as? TranscriptionServiceError {
            return error
        }
        if error is AppSettingsRepositoryError { return .settingsUnavailable }
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
