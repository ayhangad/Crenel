import Foundation

struct ElevenLabsTranscriptionService: TranscriptionServicing, Sendable {
    static let productionEndpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

    let capabilities = TranscriptionServiceCapabilities(
        supportedFileExtensions: ["aac", "aiff", "flac", "m4a", "mp3", "ogg", "opus", "wav", "webm"],
        maximumFileSizeBytes: 5_000_000_000,
        supportsDiarization: true,
        supportsAutomaticLanguageDetection: true
    )

    private let apiKeyRepository: any APIKeyRepository
    private let httpClient: any TranscriptionHTTPClient
    private let endpoint: URL
    private let multipartBuilder: MultipartFormFileBuilder

    init(
        apiKeyRepository: any APIKeyRepository = KeychainAPIKeyRepository(),
        httpClient: any TranscriptionHTTPClient = URLSessionTranscriptionHTTPClient(),
        endpoint: URL = Self.productionEndpoint,
        multipartBuilder: MultipartFormFileBuilder = MultipartFormFileBuilder()
    ) {
        self.apiKeyRepository = apiKeyRepository
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.multipartBuilder = multipartBuilder
    }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        try TranscriptionFileValidator().validate(request: request, capabilities: capabilities)
        try Task.checkCancellation()

        let apiKey: String
        do {
            guard let storedKey = try await apiKeyRepository.apiKey(),
                  !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptionServiceError.authentication
            }
            apiKey = storedKey
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            throw TranscriptionServiceError.providerUnavailable
        }

        let boundary = "Crenel-\(request.idempotencyKey.uuidString)"
        var fields = [
            MultipartFormFileBuilder.Field(name: "model_id", value: "scribe_v2"),
            MultipartFormFileBuilder.Field(
                name: "diarize",
                value: request.requestsDiarization ? "true" : "false"
            ),
            MultipartFormFileBuilder.Field(name: "timestamps_granularity", value: "word"),
            MultipartFormFileBuilder.Field(name: "tag_audio_events", value: "false")
        ]
        if let languageCode = normalizedLanguageCode(request.languageCode) {
            fields.append(.init(name: "language_code", value: languageCode))
        }

        let bodyURL: URL
        do {
            bodyURL = try multipartBuilder.build(
                fields: fields,
                fileFieldName: "file",
                sourceFileURL: request.audioFileURL,
                mimeType: mimeType(for: request.audioFileURL),
                boundary: boundary
            )
        } catch {
            throw TranscriptionErrorNormalizer.normalize(error)
        }
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 10 * 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            uploadProgress(0)
            let response = try await httpClient.upload(
                for: urlRequest,
                fromFile: bodyURL,
                progress: uploadProgress
            )
            uploadProgress(1)
            if let error = TranscriptionErrorNormalizer.normalizeHTTPStatus(
                response.response.statusCode,
                retryAfter: Self.retryAfter(from: response.response)
            ) {
                throw error
            }
            let transcript = try ElevenLabsTranscriptParser().parse(response.data)
            return TranscriptionResult(transcript: transcript)
        } catch {
            throw TranscriptionErrorNormalizer.normalize(error)
        }
    }

    private func normalizedLanguageCode(_ languageCode: String?) -> String? {
        guard let code = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return nil }
        return code.lowercased()
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a", "aac": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "flac": "audio/flac"
        case "ogg", "opus": "audio/ogg"
        case "aiff": "audio/aiff"
        case "webm": "audio/webm"
        default: "application/octet-stream"
        }
    }

    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}

struct ElevenLabsTranscriptParser: Sendable {
    private struct Response: Decodable {
        let languageCode: String?
        let text: String
        let words: [Word]

        enum CodingKeys: String, CodingKey {
            case languageCode = "language_code"
            case text
            case words
        }
    }

    private struct Word: Decodable {
        let text: String
        let start: TimeInterval?
        let end: TimeInterval?
        let type: String?
        let speakerID: String?

        enum CodingKeys: String, CodingKey {
            case text, start, end, type
            case speakerID = "speaker_id"
        }
    }

    private struct SegmentBuilder {
        var speakerID: String
        var startTime: TimeInterval
        var endTime: TimeInterval
        var text: String
    }

    func parse(_ data: Data) throws -> Transcript {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TranscriptionServiceError.invalidResponse
        }
        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !response.words.isEmpty else {
            throw TranscriptionServiceError.invalidResponse
        }

        var builders: [SegmentBuilder] = []
        for word in response.words where word.type != "audio_event" {
            if word.type == "spacing", let lastIndex = builders.indices.last {
                builders[lastIndex].text += word.text
                builders[lastIndex].endTime = max(
                    builders[lastIndex].endTime,
                    word.end ?? builders[lastIndex].endTime
                )
                continue
            }
            let fallbackSpeaker = builders.last?.speakerID ?? "speaker_0"
            let speakerID = word.speakerID ?? fallbackSpeaker
            let start = max(0, word.start ?? builders.last?.endTime ?? 0)
            let end = max(start, word.end ?? start)

            if let lastIndex = builders.indices.last,
               builders[lastIndex].speakerID == speakerID {
                builders[lastIndex].text += word.text
                builders[lastIndex].startTime = min(builders[lastIndex].startTime, start)
                builders[lastIndex].endTime = max(builders[lastIndex].endTime, end)
            } else {
                builders.append(SegmentBuilder(
                    speakerID: speakerID,
                    startTime: start,
                    endTime: end,
                    text: word.text
                ))
            }
        }

        var segments = builders.compactMap { builder -> TranscriptSegment? in
            let text = builder.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                speakerID: builder.speakerID,
                startTime: builder.startTime,
                endTime: builder.endTime,
                text: text
            )
        }
        if segments.isEmpty {
            segments = [TranscriptSegment(
                speakerID: "speaker_0",
                startTime: 0,
                endTime: 0,
                text: response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )]
        }

        return Transcript(
            text: response.text,
            languageCode: response.languageCode,
            segments: segments
        )
    }
}

struct ElevenLabsAPIKeyValidator: Sendable {
    static let productionEndpoint = URL(
        string: "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe"
    )!

    private struct TokenResponse: Decodable {
        let token: String
    }

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

        // ElevenLabs keys may be deliberately restricted to Speech-to-Text. Requesting an
        // unused, short-lived Scribe token authenticates that scope without uploading
        // audio or creating a billable transcription. It also avoids treating the batch
        // endpoint's evolving missing-file validation response as a credential result.
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(normalized, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let response = try await httpClient.data(for: request)
            if let error = TranscriptionErrorNormalizer.normalizeHTTPStatus(response.response.statusCode) {
                throw error
            }
            guard let payload = try? JSONDecoder().decode(TokenResponse.self, from: response.data),
                  !payload.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptionServiceError.invalidResponse
            }
        } catch {
            throw TranscriptionErrorNormalizer.normalize(error)
        }
    }
}
