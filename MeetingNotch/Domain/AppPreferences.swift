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

struct AppPreferences: Codable, Equatable, Sendable {
    var reminderLeadTime: TimeInterval
    var isCalendarEnabled: Bool
    var launchAtLogin: Bool
    var provider: ProviderSettings

    static let `default` = AppPreferences(
        reminderLeadTime: 5 * 60,
        isCalendarEnabled: true,
        launchAtLogin: false,
        provider: .default
    )
}
