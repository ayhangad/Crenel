import Foundation

enum TranscriptionProviderID: String, CaseIterable, Codable, Sendable {
    case elevenLabs
    case openAI
}

struct ProviderSettings: Codable, Equatable, Sendable {
    var selectedProvider: TranscriptionProviderID
    var languageCode: String?
    var useKnownSpeakers: Bool

    static let `default` = ProviderSettings(
        selectedProvider: .elevenLabs,
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
                debugDescription: "Saklama süresi pozitif bir gün sayısı olmalıdır."
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
    var provider: ProviderSettings
    var meetingRetentionPolicy: MeetingRetentionPolicy

    init(
        reminderLeadTime: TimeInterval,
        isCalendarEnabled: Bool,
        launchAtLogin: Bool,
        provider: ProviderSettings,
        meetingRetentionPolicy: MeetingRetentionPolicy = .keepForever
    ) {
        self.reminderLeadTime = reminderLeadTime
        self.isCalendarEnabled = isCalendarEnabled
        self.launchAtLogin = launchAtLogin
        self.provider = provider
        self.meetingRetentionPolicy = meetingRetentionPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case reminderLeadTime
        case isCalendarEnabled
        case launchAtLogin
        case provider
        case meetingRetentionPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reminderLeadTime = try container.decode(TimeInterval.self, forKey: .reminderLeadTime)
        isCalendarEnabled = try container.decode(Bool.self, forKey: .isCalendarEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        provider = try container.decode(ProviderSettings.self, forKey: .provider)
        meetingRetentionPolicy = try container.decodeIfPresent(
            MeetingRetentionPolicy.self,
            forKey: .meetingRetentionPolicy
        ) ?? .keepForever
    }

    static let `default` = AppPreferences(
        reminderLeadTime: 5 * 60,
        isCalendarEnabled: true,
        launchAtLogin: false,
        provider: .default,
        meetingRetentionPolicy: .keepForever
    )
}
