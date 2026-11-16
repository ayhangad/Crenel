import Foundation

/// Where meeting audio is transcribed.
enum MeetingTranscriptionEngine: String, Codable, CaseIterable, Equatable, Sendable {
    case elevenLabs
    case onDevice

    var displayName: String {
        switch self {
        case .elevenLabs: "ElevenLabs (bulut, konuşmacı ayrımı)"
        case .onDevice: "Cihaz içi (Apple Speech)"
        }
    }

    /// Unknown stored values (from a newer build) decode to the default instead of failing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MeetingTranscriptionEngine(rawValue: raw) ?? .elevenLabs
    }
}

/// Which model writes the meeting summary.
enum MeetingSummaryEngine: String, Codable, CaseIterable, Equatable, Sendable {
    case openAI
    /// The provider chosen in `AgentPreferences` (on-device, OpenAI or Anthropic).
    case agent

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .agent: "Yapay zekâ sağlayıcısı (Ajan ayarları)"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MeetingSummaryEngine(rawValue: raw) ?? .openAI
    }
}

/// Standalone meeting processing settings; designed to be embedded into `AppPreferences`.
struct MeetingProcessingPreferences: Codable, Equatable, Sendable {
    var transcription: MeetingTranscriptionEngine
    var summary: MeetingSummaryEngine

    static let `default` = MeetingProcessingPreferences()

    init(transcription: MeetingTranscriptionEngine = .elevenLabs, summary: MeetingSummaryEngine = .openAI) {
        self.transcription = transcription
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey { case transcription, summary }

    /// Missing keys, wrong types and unknown values fall back to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcription = (try? container.decodeIfPresent(MeetingTranscriptionEngine.self, forKey: .transcription))
            .flatMap { $0 } ?? .elevenLabs
        summary = (try? container.decodeIfPresent(MeetingSummaryEngine.self, forKey: .summary))
            .flatMap { $0 } ?? .openAI
    }
}

typealias MeetingProcessingPreferencesProvider = @Sendable () async -> MeetingProcessingPreferences
typealias AgentPreferencesProvider = @Sendable () async -> AgentPreferences

/// Chooses ElevenLabs or on-device transcription per request from the current preferences.
struct MeetingTranscriptionRouter: TranscriptionServicing {
    private let preferences: MeetingProcessingPreferencesProvider
    private let elevenLabs: any TranscriptionServicing
    private let onDevice: any TranscriptionServicing

    init(
        preferences: @escaping MeetingProcessingPreferencesProvider,
        elevenLabs: any TranscriptionServicing = ElevenLabsTranscriptionService(),
        onDevice: any TranscriptionServicing = LocalMeetingTranscriptionService()
    ) {
        self.preferences = preferences
        self.elevenLabs = elevenLabs
        self.onDevice = onDevice
    }

    /// Static protocol requirement; reports the default (ElevenLabs) backend. Each backend
    /// validates the file against its own capabilities when it is called.
    var capabilities: TranscriptionServiceCapabilities { elevenLabs.capabilities }

    func service(for engine: MeetingTranscriptionEngine) -> any TranscriptionServicing {
        switch engine {
        case .elevenLabs: elevenLabs
        case .onDevice: onDevice
        }
    }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        let engine = await preferences().transcription
        do {
            return try await service(for: engine).transcribe(request, uploadProgress: uploadProgress)
        } catch let error as LocalMeetingTranscriptionError {
            // Keep the worker's retry semantics: unsupported language / unreadable audio are final.
            throw error.serviceError
        }
    }
}

/// Chooses the OpenAI summary service or an agent-provider summary per meeting.
struct MeetingSummaryRouter: MeetingSummaryGenerating {
    typealias AgentServiceFactory = @Sendable (AgentPreferences) -> (any MeetingSummaryGenerating)?

    private let preferences: MeetingProcessingPreferencesProvider
    private let agentPreferences: AgentPreferencesProvider
    private let openAI: any MeetingSummaryGenerating
    private let makeAgentService: AgentServiceFactory

    init(
        preferences: @escaping MeetingProcessingPreferencesProvider,
        agentPreferences: @escaping AgentPreferencesProvider,
        openAI: any MeetingSummaryGenerating = OpenAIMeetingSummaryService(),
        makeAgentService: @escaping AgentServiceFactory = { AgentMeetingSummaryService.make(for: $0) }
    ) {
        self.preferences = preferences
        self.agentPreferences = agentPreferences
        self.openAI = openAI
        self.makeAgentService = makeAgentService
    }

    func generate(from transcript: Transcript) async throws -> MeetingSummary {
        try await resolve().generate(from: transcript)
    }

    func generate(from transcript: Transcript, meeting: StoredMeeting) async throws -> MeetingSummary {
        try await resolve().generate(from: transcript, meeting: meeting)
    }

    /// The agent path never silently falls back to OpenAI (the user may have chosen it to keep
    /// text on the device); a disabled provider marks the summary as needing attention.
    private func resolve() async throws -> any MeetingSummaryGenerating {
        switch await preferences().summary {
        case .openAI:
            return openAI
        case .agent:
            guard let service = makeAgentService(await agentPreferences()) else {
                throw AgentMeetingSummaryError.providerDisabled
            }
            return service
        }
    }
}
