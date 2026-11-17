import Foundation

struct TranscriptionSettingsSnapshot: Equatable, Sendable {
    var languageCode: String?
    var hasStoredAPIKey: Bool
}

struct GeneralSettingsSnapshot: Equatable, Sendable {
    var reminderLeadTime: TimeInterval
    var isCalendarEnabled: Bool
    var launchAtLogin: Bool
    var meetingRetentionPolicy: MeetingRetentionPolicy
    var selectedCalendarIDs: [String]? = nil

    static let `default` = GeneralSettingsSnapshot(
        reminderLeadTime: 10 * 60,
        isCalendarEnabled: true,
        launchAtLogin: false,
        meetingRetentionPolicy: .keepForever
    )
}

enum SettingsActionResult: Equatable, Sendable {
    case succeeded(message: String? = nil)
    case failed(message: String)
}

enum TranscriptionSettingsSaveResult: Equatable, Sendable {
    case saved(retriedJobCount: Int)
    case failed(AppFailure)
}

struct TranscriptionSettings: Codable, Equatable, Sendable {
    var languageCode: String?
    var useKnownSpeakers: Bool

    static let `default` = TranscriptionSettings(
        languageCode: nil,
        useKnownSpeakers: false
    )
}

struct MeetingRetentionPolicy: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case days
    }

    static let keepForever = MeetingRetentionPolicy(days: nil)

    private(set) var days: Int?

    init?(deletingAfterDays days: Int) {
        guard days > 0 else { return nil }
        self.days = days
    }

    private init(days: Int?) {
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let days = try container.decodeIfPresent(Int.self, forKey: .days) else {
            self = .keepForever
            return
        }
        guard let policy = Self(deletingAfterDays: days) else {
            throw DecodingError.dataCorruptedError(
                forKey: .days,
                in: container,
                debugDescription: "Retention must be a positive number of days."
            )
        }
        self = policy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(days, forKey: .days)
    }

    func cutoffDate(relativeTo date: Date) -> Date? {
        guard let days else { return nil }
        return date.addingTimeInterval(-TimeInterval(days) * 24 * 60 * 60)
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var reminderLeadTime: TimeInterval
    var isCalendarEnabled: Bool
    var launchAtLogin: Bool
    var selectedMicrophoneID: String?
    var transcription: TranscriptionSettings
    var meetingRetentionPolicy: MeetingRetentionPolicy
    var selectedCalendarIDs: [String]? = nil
    var hasCompletedOnboarding: Bool
    var crenel: CrenelPreferences = .default

    init(
        reminderLeadTime: TimeInterval,
        isCalendarEnabled: Bool,
        launchAtLogin: Bool,
        selectedMicrophoneID: String? = nil,
        transcription: TranscriptionSettings,
        meetingRetentionPolicy: MeetingRetentionPolicy = .keepForever,
        hasCompletedOnboarding: Bool = false
    ) {
        self.reminderLeadTime = reminderLeadTime
        self.isCalendarEnabled = isCalendarEnabled
        self.launchAtLogin = launchAtLogin
        self.selectedMicrophoneID = selectedMicrophoneID
        self.transcription = transcription
        self.meetingRetentionPolicy = meetingRetentionPolicy
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    private enum CodingKeys: String, CodingKey {
        case reminderLeadTime
        case isCalendarEnabled
        case launchAtLogin
        case selectedMicrophoneID
        case transcription
        // Pre-V1 documents stored transcription settings under this key.
        case provider
        case meetingRetentionPolicy
        case selectedCalendarIDs
        case hasCompletedOnboarding
        case crenel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedCalendarIDs = try container.decodeIfPresent([String].self, forKey: .selectedCalendarIDs)
        reminderLeadTime = try container.decode(TimeInterval.self, forKey: .reminderLeadTime)
        isCalendarEnabled = try container.decode(Bool.self, forKey: .isCalendarEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        selectedMicrophoneID = try container.decodeIfPresent(
            String.self,
            forKey: .selectedMicrophoneID
        )
        transcription = try container.decodeIfPresent(
            TranscriptionSettings.self,
            forKey: .transcription
        ) ?? container.decodeIfPresent(
            TranscriptionSettings.self,
            forKey: .provider
        ) ?? .default
        meetingRetentionPolicy = try container.decodeIfPresent(
            MeetingRetentionPolicy.self,
            forKey: .meetingRetentionPolicy
        ) ?? .keepForever
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedOnboarding
        ) ?? false
        crenel = (try? container.decodeIfPresent(CrenelPreferences.self, forKey: .crenel)) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try container.encode(reminderLeadTime, forKey: .reminderLeadTime)
        try container.encode(isCalendarEnabled, forKey: .isCalendarEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encodeIfPresent(selectedMicrophoneID, forKey: .selectedMicrophoneID)
        try container.encode(transcription, forKey: .transcription)
        try container.encode(meetingRetentionPolicy, forKey: .meetingRetentionPolicy)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(crenel, forKey: .crenel)
    }

    static let `default` = AppPreferences(
        reminderLeadTime: 10 * 60,
        isCalendarEnabled: true,
        launchAtLogin: false,
        selectedMicrophoneID: nil,
        transcription: .default,
        meetingRetentionPolicy: .keepForever,
        hasCompletedOnboarding: false
    )
}

/// Settings for the Crenel features. Each field decodes independently so a newer or
/// partial document never resets the others.
struct CrenelPreferences: Codable, Equatable, Sendable {
    var taskStorage: TaskStorageBackend = .reminders
    var dictationEnabled = true
    var dictationTrigger: DictationTriggerSettings = .default
    var dictationLanguage: DictationLanguage = .automatic
    var dictationVocabulary: [String] = []
    var agent: AgentPreferences = .default
    var meetingProcessing: MeetingProcessingPreferences = MeetingProcessingPreferences()

    static let `default` = CrenelPreferences()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case taskStorage, dictationEnabled, dictationTrigger, dictationLanguage
        case dictationVocabulary, agent, meetingProcessing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CrenelPreferences.default
        taskStorage = (try? container.decodeIfPresent(TaskStorageBackend.self, forKey: .taskStorage)) ?? fallback.taskStorage
        dictationEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .dictationEnabled)) ?? fallback.dictationEnabled
        dictationTrigger = (try? container.decodeIfPresent(DictationTriggerSettings.self, forKey: .dictationTrigger)) ?? fallback.dictationTrigger
        dictationLanguage = (try? container.decodeIfPresent(DictationLanguage.self, forKey: .dictationLanguage)) ?? fallback.dictationLanguage
        dictationVocabulary = (try? container.decodeIfPresent([String].self, forKey: .dictationVocabulary)) ?? fallback.dictationVocabulary
        agent = (try? container.decodeIfPresent(AgentPreferences.self, forKey: .agent)) ?? fallback.agent
        meetingProcessing = (try? container.decodeIfPresent(MeetingProcessingPreferences.self, forKey: .meetingProcessing)) ?? fallback.meetingProcessing
    }
}
