import Foundation

/// Where meeting audio is transcribed.
enum MeetingTranscriptionEngine: String, Codable, CaseIterable, Equatable, Sendable {
    case elevenLabs
    case deepgram
    case onDevice

    var displayName: String {
        switch self {
        case .elevenLabs: "ElevenLabs (cloud, speaker labels)"
        case .deepgram: "Deepgram (cloud, speaker labels)"
        case .onDevice: "On-device (Apple Speech)"
        }
    }

    func defaultLanguageTitle(locale: Locale = .current) -> String {
        guard self == .onDevice else { return "Automatic" }
        let code = locale.language.languageCode?.identifier ?? locale.identifier
        let language = locale.localizedString(forLanguageCode: code) ?? code
        return "Mac language (\(language))"
    }

    /// Unknown stored values (from a newer build) decode to the default instead of failing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MeetingTranscriptionEngine(rawValue: raw) ?? .onDevice
    }
}

/// Which model writes the meeting summary.
enum MeetingSummaryEngine: String, Codable, CaseIterable, Equatable, Sendable {
    case openAI
    case onDevice
    /// The provider chosen in `AgentPreferences` (on-device, OpenAI or Anthropic).
    case agent

    var displayName: String {
        switch self {
        case .onDevice: "On this Mac (Apple)"
        case .openAI: "OpenAI"
        case .agent: "AI provider (Agent settings)"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MeetingSummaryEngine(rawValue: raw) ?? .onDevice
    }
}

/// Standalone meeting processing settings; designed to be embedded into `AppPreferences`.
struct MeetingProcessingPreferences: Codable, Equatable, Sendable {
    var transcription: MeetingTranscriptionEngine
    var summary: MeetingSummaryEngine

    static let `default` = MeetingProcessingPreferences()

    init(transcription: MeetingTranscriptionEngine = .onDevice, summary: MeetingSummaryEngine = .agent) {
        self.transcription = transcription
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey { case transcription, summary }

    /// Missing keys in older documents use defaults. A malformed preference blocks processing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcription = try container.decodeIfPresent(MeetingTranscriptionEngine.self, forKey: .transcription) ?? .onDevice
        summary = try container.decodeIfPresent(MeetingSummaryEngine.self, forKey: .summary) ?? .agent
    }
}

typealias MeetingProcessingPreferencesProvider = @Sendable () async throws -> MeetingProcessingPreferences
typealias AgentPreferencesProvider = @Sendable () async throws -> AgentPreferences

/// Chooses ElevenLabs, Deepgram or on-device transcription per request from the current preferences.
struct MeetingTranscriptionRouter: TranscriptionServicing {
    private let preferences: MeetingProcessingPreferencesProvider
    private let elevenLabs: any TranscriptionServicing
    private let deepgram: any TranscriptionServicing
    private let onDevice: any TranscriptionServicing

    init(
        preferences: @escaping MeetingProcessingPreferencesProvider,
        elevenLabs: any TranscriptionServicing = ElevenLabsTranscriptionService(),
        deepgram: any TranscriptionServicing = DeepgramTranscriptionService(),
        onDevice: any TranscriptionServicing = LocalMeetingTranscriptionService()
    ) {
        self.preferences = preferences
        self.elevenLabs = elevenLabs
        self.deepgram = deepgram
        self.onDevice = onDevice
    }

    /// Static protocol requirement; reports the default on-device backend. Each backend
    /// validates the file against its own capabilities when it is called.
    var capabilities: TranscriptionServiceCapabilities { onDevice.capabilities }

    func service(for engine: MeetingTranscriptionEngine) -> any TranscriptionServicing {
        switch engine {
        case .elevenLabs: elevenLabs
        case .deepgram: deepgram
        case .onDevice: onDevice
        }
    }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        let engine = try await preferences().transcription
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
    private let owner: MeetingOwner

    init(
        preferences: @escaping MeetingProcessingPreferencesProvider,
        agentPreferences: @escaping AgentPreferencesProvider,
        openAI: any MeetingSummaryGenerating = OpenAIMeetingSummaryService(),
        makeAgentService: @escaping AgentServiceFactory = { AgentMeetingSummaryService.make(for: $0) },
        owner: MeetingOwner = .current()
    ) {
        self.preferences = preferences
        self.agentPreferences = agentPreferences
        self.openAI = openAI
        self.makeAgentService = makeAgentService
        self.owner = owner
    }

    /// Only the owner's action items are kept, whichever service wrote the notes.
    func generate(from transcript: Transcript) async throws -> MeetingSummary {
        owner.ownActions(of: try await resolve().generate(from: transcript), in: transcript)
    }

    func generate(from transcript: Transcript, meeting: StoredMeeting) async throws -> MeetingSummary {
        owner.ownActions(of: try await resolve().generate(from: transcript, meeting: meeting), in: transcript)
    }

    /// The agent path never silently falls back to OpenAI (the user may have chosen it to keep
    /// text on the device); a disabled provider marks the summary as needing attention.
    private func resolve() async throws -> any MeetingSummaryGenerating {
        let engine = try await preferences().summary
        switch engine {
        case .openAI:
            return openAI
        case .agent, .onDevice:
            let selected = engine == .onDevice ? AgentPreferences(provider: .onDevice) : try await agentPreferences()
            guard let service = makeAgentService(selected) else {
                throw AgentMeetingSummaryError.providerDisabled
            }
            return service
        }
    }
}
