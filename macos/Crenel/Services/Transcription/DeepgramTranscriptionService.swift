import Foundation

/// Deepgram pre-recorded transcription (`POST /v1/listen`, Nova-3) with speaker labels.
/// The audio file is the request body as is; nothing is wrapped or copied to disk.
struct DeepgramTranscriptionService: TranscriptionServicing, Sendable {
    static let productionEndpoint = URL(string: "https://api.deepgram.com/v1/listen")!
    static let model = "nova-3"

    let capabilities = TranscriptionServiceCapabilities(
        supportedFileExtensions: ["aac", "aiff", "flac", "m4a", "mp3", "mp4", "ogg", "opus", "wav", "webm"],
        maximumFileSizeBytes: 2_000_000_000,
        supportsDiarization: true,
        supportsAutomaticLanguageDetection: true
    )

    private let apiKeyRepository: any APIKeyRepository
    private let httpClient: any TranscriptionHTTPClient
    private let endpoint: URL

    init(
        apiKeyRepository: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.deepgramService),
        httpClient: any TranscriptionHTTPClient = URLSessionTranscriptionHTTPClient(),
        endpoint: URL = Self.productionEndpoint
    ) {
        self.apiKeyRepository = apiKeyRepository
        self.httpClient = httpClient
        self.endpoint = endpoint
    }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        try TranscriptionFileValidator().validate(request: request, capabilities: capabilities)
        try Task.checkCancellation()

        let apiKey: String
        do {
            guard let storedKey = try await apiKeyRepository.apiKey()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !storedKey.isEmpty else {
                throw TranscriptionServiceError.authentication
            }
            apiKey = storedKey
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            throw TranscriptionServiceError.providerUnavailable
        }

        var urlRequest = URLRequest(url: requestURL(for: request), timeoutInterval: 10 * 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(mimeType(for: request.audioFileURL), forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            uploadProgress(0)
            let response = try await httpClient.upload(
                for: urlRequest,
                fromFile: request.audioFileURL,
                progress: uploadProgress
            )
            uploadProgress(1)
            if let error = TranscriptionErrorNormalizer.normalizeHTTPStatus(
                response.response.statusCode,
                retryAfter: ElevenLabsTranscriptionService.retryAfter(from: response.response)
            ) {
                throw error
            }
            let transcript = try DeepgramTranscriptParser().parse(response.data)
            return TranscriptionResult(transcript: transcript)
        } catch {
            throw TranscriptionErrorNormalizer.normalize(error)
        }
    }

    func requestURL(for request: TranscriptionRequest) -> URL {
        var items = [
            URLQueryItem(name: "model", value: Self.model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
            URLQueryItem(name: "diarize", value: request.requestsDiarization ? "true" : "false")
        ]
        if let code = request.languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !code.isEmpty {
            items.append(URLQueryItem(name: "language", value: code))
        } else {
            items.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + items
        return components.url!
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a", "aac", "mp4": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "flac": "audio/flac"
        case "ogg", "opus": "audio/ogg"
        case "aiff": "audio/aiff"
        case "webm": "audio/webm"
        default: "application/octet-stream"
        }
    }
}

/// Turns Deepgram's response into the shared transcript model. Utterances already carry
/// one speaker each; words are the fallback when utterances are missing.
struct DeepgramTranscriptParser: Sendable {
    private struct Response: Decodable {
        let results: Results
    }

    private struct Results: Decodable {
        let channels: [Channel]
        let utterances: [Utterance]?
    }

    private struct Channel: Decodable {
        let alternatives: [Alternative]
        let detectedLanguage: String?

        enum CodingKeys: String, CodingKey {
            case alternatives
            case detectedLanguage = "detected_language"
        }
    }

    private struct Alternative: Decodable {
        let transcript: String
        let words: [Word]?
    }

    private struct Word: Decodable {
        let word: String
        let punctuatedWord: String?
        let start: TimeInterval?
        let end: TimeInterval?
        let speaker: Int?

        enum CodingKeys: String, CodingKey {
            case word, start, end, speaker
            case punctuatedWord = "punctuated_word"
        }
    }

    private struct Utterance: Decodable {
        let start: TimeInterval
        let end: TimeInterval
        let transcript: String
        let speaker: Int?
    }

    func parse(_ data: Data) throws -> Transcript {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TranscriptionServiceError.invalidResponse
        }
        guard let channel = response.results.channels.first,
              let alternative = channel.alternatives.first else {
            throw TranscriptionServiceError.invalidResponse
        }
        let text = alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        var segments: [TranscriptSegment] = []
        for utterance in response.results.utterances ?? [] {
            let utteranceText = utterance.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !utteranceText.isEmpty else { continue }
            append(
                &segments,
                speakerID: Self.speakerID(utterance.speaker ?? segments.last.map(Self.index) ?? 0),
                start: utterance.start,
                end: utterance.end,
                text: utteranceText
            )
        }
        if segments.isEmpty {
            for word in alternative.words ?? [] {
                let start = max(0, word.start ?? segments.last?.endTime ?? 0)
                append(
                    &segments,
                    speakerID: Self.speakerID(word.speaker ?? segments.last.map(Self.index) ?? 0),
                    start: start,
                    end: max(start, word.end ?? start),
                    text: word.punctuatedWord ?? word.word
                )
            }
        }
        if segments.isEmpty {
            // Same rule as ElevenLabs: a response with no words at all is not a transcript.
            guard !text.isEmpty else { throw TranscriptionServiceError.invalidResponse }
            segments = [TranscriptSegment(speakerID: Self.speakerID(0), startTime: 0, endTime: 0, text: text)]
        }

        return Transcript(
            text: text.isEmpty ? segments.map(\.text).joined(separator: " ") : text,
            languageCode: channel.detectedLanguage,
            segments: segments
        )
    }

    /// Same identifiers as ElevenLabs (`speaker_0`), so naming speakers works the same way.
    static func speakerID(_ index: Int) -> String { "speaker_\(max(0, index))" }

    private static func index(_ segment: TranscriptSegment) -> Int {
        Int(segment.speakerID.dropFirst("speaker_".count)) ?? 0
    }

    private func append(
        _ segments: inout [TranscriptSegment],
        speakerID: String,
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) {
        let start = max(0, start)
        let end = max(start, end)
        if let lastIndex = segments.indices.last, segments[lastIndex].speakerID == speakerID {
            segments[lastIndex].startTime = min(segments[lastIndex].startTime, start)
            segments[lastIndex].endTime = max(segments[lastIndex].endTime, end)
            segments[lastIndex].text += " " + text
        } else {
            segments.append(TranscriptSegment(speakerID: speakerID, startTime: start, endTime: end, text: text))
        }
    }
}

/// Checks a Deepgram key with `GET /v1/auth/token`, which describes the key without
/// uploading audio or creating a billable request.
struct DeepgramAPIKeyValidator: Sendable {
    static let productionEndpoint = URL(string: "https://api.deepgram.com/v1/auth/token")!

    private let httpClient: any TranscriptionHTTPClient
    private let endpoint: URL

    init(
        httpClient: any TranscriptionHTTPClient = URLSessionTranscriptionHTTPClient(),
        endpoint: URL = Self.productionEndpoint
    ) {
        self.httpClient = httpClient
        self.endpoint = endpoint
    }

    func validate(_ apiKey: String) async throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranscriptionServiceError.authentication }

        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Token \(normalized)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let response = try await httpClient.data(for: request)
            if let error = TranscriptionErrorNormalizer.normalizeHTTPStatus(response.response.statusCode) {
                throw error
            }
            guard (try? JSONSerialization.jsonObject(with: response.data)) is [String: Any] else {
                throw TranscriptionServiceError.invalidResponse
            }
        } catch {
            throw TranscriptionErrorNormalizer.normalize(error)
        }
    }
}
