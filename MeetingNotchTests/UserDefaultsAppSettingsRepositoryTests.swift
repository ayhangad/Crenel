import Foundation
import XCTest
@testable import MeetingNotch

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
            provider: ProviderSettings(
                selectedProvider: .openAI,
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

        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertNil(json["apiKey"])
    }

    func testSaveReplacesExistingPreferences() async throws {
        try await repository.save(.default)
        var updated = AppPreferences.default
        updated.reminderLeadTime = 60
        updated.provider.languageCode = "en"

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

        XCTAssertNil(defaults.object(forKey: storageKey))
        let loadedAfterRecovery = try await repository.load()
        XCTAssertEqual(loadedAfterRecovery, .default)
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
        XCTAssertFalse(loaded.hasCompletedOnboarding)
        XCTAssertEqual(defaults.data(forKey: storageKey), data)
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
