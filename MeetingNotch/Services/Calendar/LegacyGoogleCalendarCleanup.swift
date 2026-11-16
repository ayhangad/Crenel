import Foundation

/// Crenel reads Google calendars through macOS Internet Accounts. Earlier builds could
/// store a Google OAuth refresh token; this removes it so no unused credential remains.
enum LegacyGoogleCalendarCleanup {
    static let keychainService = "gad.MeetingNotch.google-calendar-oauth"

    static func removeStoredGrant() async throws {
        try await KeychainAPIKeyRepository(service: keychainService).deleteAPIKey()
    }
}
