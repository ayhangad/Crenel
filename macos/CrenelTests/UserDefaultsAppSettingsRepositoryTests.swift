import Foundation
import XCTest
@testable import Crenel

final class UserDefaultsAppSettingsRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var repository: UserDefaultsAppSettingsRepository!
    private let storageKey = "test.preferences"
    private let recoveryKeyPrefix = "test.recovery.preferences"

    override func setUpWithError() throws {
        suiteName = "UserDefaultsAppSettingsRepositoryTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        repository = makeRepository()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testMissingStoreLoadsDefaults() async throws {
        let loaded = try await repository.load()

        XCTAssertEqual(loaded, .default)
    }

    func testSaveLoadsPreferencesAfterRepositoryRestart() async throws {
        let preferences = AppPreferences(
            reminderLeadTime: 10 * 60,
            isCalendarEnabled: false,
            launchAtLogin: true,
            selectedMicrophoneID: "usb-microphone",
            transcription: TranscriptionSettings(
                languageCode: "tr",
                useKnownSpeakers: true
            ),
            meetingRetentionPolicy: try XCTUnwrap(
                MeetingRetentionPolicy(deletingAfterDays: 30)
            ),
            hasCompletedOnboarding: true
        )

        try await repository.save(preferences)

        let restartedRepository = makeRepository()
        let loaded = try await restartedRepository.load()
        XCTAssertEqual(loaded, preferences)
        XCTAssertEqual(loaded.selectedMicrophoneID, "usb-microphone")

        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertNil(json["apiKey"])
    }

    func testSaveReplacesExistingPreferences() async throws {
        try await repository.save(.default)
        var updated = AppPreferences.default
        updated.reminderLeadTime = 60
        updated.transcription.languageCode = "en"

        try await repository.save(updated)

        let loaded = try await repository.load()
        XCTAssertEqual(loaded, updated)
    }

    func testResetRemovesStoreAndRestoresDefaults() async throws {
        var preferences = AppPreferences.default
        preferences.launchAtLogin = true
        try await repository.save(preferences)

        await repository.reset()

        let loaded = try await repository.load()
        XCTAssertEqual(loaded, .default)
        XCTAssertNil(defaults.object(forKey: storageKey))
    }

    func testCorruptStoreIsQuarantinedBeforeDefaultCanBeUsed() async throws {
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: storageKey)

        do {
            _ = try await repository.load()
            XCTFail("Bozuk ayar belgesinin hata üretmesi bekleniyordu.")
        } catch let error as AppSettingsRepositoryError {
            guard case .corruptStore(let recoveryKey) = error else {
                return XCTFail("Beklenmeyen hata: \(error)")
            }
            XCTAssertTrue(recoveryKey.hasPrefix(recoveryKeyPrefix))
            XCTAssertEqual(defaults.data(forKey: recoveryKey), corruptData)
        }

        do {
            try await makeRepository().save(.default)
            XCTFail("A restarted repository must preserve unreadable settings")
        } catch is AppSettingsRepositoryError {}
        XCTAssertEqual(defaults.data(forKey: storageKey), corruptData)
    }

    func testDiscardingUnreadableSettingsKeepsACopyAndRestoresDefaults() async throws {
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: storageKey)
        await repository.discardUnreadableSettings()

        XCTAssertEqual(defaults.data(forKey: "\(recoveryKeyPrefix).discarded"), corruptData)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, .default)
        try await repository.save(.default)
    }

    func testUnsupportedSchemaIsPreservedInPlace() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 99,
            "preferences": [
                "reminderLeadTime": 300,
                "isCalendarEnabled": true,
                "launchAtLogin": false,
                "provider": [
                    "selectedProvider": "elevenLabs",
                    "useKnownSpeakers": false
                ]
            ]
        ])
        defaults.set(data, forKey: storageKey)

        do {
            _ = try await repository.load()
            XCTFail("Desteklenmeyen sürümün hata üretmesi bekleniyordu.")
        } catch let error as AppSettingsRepositoryError {
            XCTAssertEqual(error, .unsupportedSchema(99))
        }

        XCTAssertEqual(defaults.data(forKey: storageKey), data)
    }

    func testLegacyPreferencesWithoutRetentionPolicyLoadAsKeepForever() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "preferences": [
                "reminderLeadTime": 300,
                "isCalendarEnabled": true,
                "launchAtLogin": false,
                "provider": [
                    "selectedProvider": "elevenLabs",
                    "useKnownSpeakers": false
                ]
            ]
        ])
        defaults.set(data, forKey: storageKey)

        let loaded = try await repository.load()

        XCTAssertEqual(loaded.meetingRetentionPolicy, .keepForever)
        XCTAssertNil(loaded.selectedMicrophoneID)
        XCTAssertFalse(loaded.hasCompletedOnboarding)
        XCTAssertEqual(loaded.transcription, .default)
        let migratedData = try XCTUnwrap(defaults.data(forKey: storageKey))
        XCTAssertNotEqual(migratedData, data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
    }

    func testLegacyProviderSettingsAreRewrittenAsSingleTranscriptionSettings() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "preferences": [
                "reminderLeadTime": 300,
                "isCalendarEnabled": true,
                "launchAtLogin": false,
                "provider": [
                    "selectedProvider": "openAI",
                    "languageCode": "en",
                    "useKnownSpeakers": true
                ]
            ]
        ])
        defaults.set(data, forKey: storageKey)

        let loaded = try await repository.load()
        try await repository.save(loaded)

        XCTAssertEqual(loaded.transcription.languageCode, "en")
        XCTAssertTrue(loaded.transcription.useKnownSpeakers)
        let migratedData = try XCTUnwrap(defaults.data(forKey: storageKey))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        let preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        XCTAssertNil(preferences["provider"])
        let transcription = try XCTUnwrap(
            preferences["transcription"] as? [String: Any]
        )
        XCTAssertEqual(transcription["languageCode"] as? String, "en")
        XCTAssertNil(transcription["selectedProvider"])
    }

    func testOnboardingCompletionPersistsAcrossRepositoryRestart() async throws {
        var preferences = AppPreferences.default
        preferences.hasCompletedOnboarding = true

        try await repository.save(preferences)

        let loaded = try await makeRepository().load()
        XCTAssertTrue(loaded.hasCompletedOnboarding)
    }

    private func makeRepository() -> UserDefaultsAppSettingsRepository {
        UserDefaultsAppSettingsRepository(
            defaults: defaults,
            storageKey: storageKey,
            recoveryKeyPrefix: recoveryKeyPrefix
        )
    }
}
