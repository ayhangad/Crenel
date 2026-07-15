import Foundation
import Security
import XCTest
@testable import MeetingNotch

final class KeychainAPIKeyRepositoryTests: XCTestCase {
    func testSaveAndReadUseProviderSpecificAccounts() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        try await repository.saveAPIKey("  open-ai-secret\n", for: .openAI)
        try await repository.saveAPIKey("eleven-labs-secret", for: .elevenLabs)

        let openAIKey = try await repository.apiKey(for: .openAI)
        let elevenLabsKey = try await repository.apiKey(for: .elevenLabs)
        XCTAssertEqual(openAIKey, "open-ai-secret")
        XCTAssertEqual(elevenLabsKey, "eleven-labs-secret")
        XCTAssertEqual(store.lastService, "test.service")
        XCTAssertEqual(store.accounts, Set(["openAI", "elevenLabs"]))
    }

    func testSaveReplacesExistingKey() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store)
        try await repository.saveAPIKey("old-secret", for: .openAI)

        try await repository.saveAPIKey("new-secret", for: .openAI)

        let stored = try await repository.apiKey(for: .openAI)
        XCTAssertEqual(stored, "new-secret")
    }

    func testMissingKeyReturnsNilAndDeleteIsIdempotent() async throws {
        let repository = KeychainAPIKeyRepository(store: InMemoryKeychainDataStore())

        let missingKey = try await repository.apiKey(for: .openAI)
        XCTAssertNil(missingKey)
        try await repository.deleteAPIKey(for: .openAI)
        try await repository.deleteAPIKey(for: .openAI)
    }

    func testDeleteDoesNotAffectOtherProvider() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store)
        try await repository.saveAPIKey("open-ai-secret", for: .openAI)
        try await repository.saveAPIKey("eleven-labs-secret", for: .elevenLabs)

        try await repository.deleteAPIKey(for: .openAI)

        let deletedKey = try await repository.apiKey(for: .openAI)
        let remainingKey = try await repository.apiKey(for: .elevenLabs)
        XCTAssertNil(deletedKey)
        XCTAssertEqual(remainingKey, "eleven-labs-secret")
    }

    func testBlankKeyIsRejectedWithoutWriting() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store)

        do {
            try await repository.saveAPIKey(" \n\t ", for: .openAI)
            XCTFail("Boş API anahtarının reddedilmesi bekleniyordu.")
        } catch let error as APIKeyRepositoryError {
            XCTAssertEqual(error, .emptyAPIKey)
        }

        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testInvalidUTF8StoredValueIsRejected() async throws {
        let store = InMemoryKeychainDataStore()
        try store.save(Data([0xFF]), service: "test.service", account: "openAI")
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        do {
            _ = try await repository.apiKey(for: .openAI)
            XCTFail("Geçersiz metin verisinin reddedilmesi bekleniyordu.")
        } catch let error as APIKeyRepositoryError {
            XCTAssertEqual(error, .invalidStoredValue)
        }
    }

    func testStorageFailureDoesNotExposeAPIKey() async throws {
        let secret = "must-never-appear-in-errors-or-logs"
        let repository = KeychainAPIKeyRepository(store: FailingKeychainDataStore(secret: secret))

        do {
            try await repository.saveAPIKey(secret, for: .openAI)
            XCTFail("Depo hatasının iletilmesi bekleniyordu.")
        } catch let error as APIKeyRepositoryError {
            XCTAssertEqual(error, .keychainFailure(operation: .save, status: nil))
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
    }

    func testSettingsDocumentDoesNotContainStoredAPIKey() async throws {
        let secret = "keychain-only-secret"
        let store = InMemoryKeychainDataStore()
        let keyRepository = KeychainAPIKeyRepository(store: store)
        try await keyRepository.saveAPIKey(secret, for: .openAI)

        let suiteName = "KeychainAPIKeyRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsRepository = UserDefaultsAppSettingsRepository(
            defaults: defaults,
            storageKey: "test.preferences"
        )
        var preferences = AppPreferences.default
        preferences.provider.selectedProvider = .openAI
        try await settingsRepository.save(preferences)

        let settingsData = try XCTUnwrap(defaults.data(forKey: "test.preferences"))
        XCTAssertFalse(String(decoding: settingsData, as: UTF8.self).contains(secret))
        let storedKey = try await keyRepository.apiKey(for: .openAI)
        XCTAssertEqual(storedKey, secret)
    }
}

private final class InMemoryKeychainDataStore: KeychainDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private(set) var lastService: String?

    var accounts: Set<String> {
        lock.withLock { Set(values.keys.compactMap { $0.split(separator: "|", maxSplits: 1).last.map(String.init) }) }
    }

    func read(service: String, account: String) throws -> Data? {
        lock.withLock {
            lastService = service
            return values[key(service: service, account: account)]
        }
    }

    func save(_ data: Data, service: String, account: String) throws {
        lock.withLock {
            lastService = service
            values[key(service: service, account: account)] = data
        }
    }

    func delete(service: String, account: String) throws {
        lock.withLock {
            lastService = service
            values.removeValue(forKey: key(service: service, account: account))
        }
    }

    private func key(service: String, account: String) -> String {
        "\(service)|\(account)"
    }
}

private struct FailingKeychainDataStore: KeychainDataStore {
    let secret: String

    func read(service: String, account: String) throws -> Data? {
        throw Failure(message: secret)
    }

    func save(_ data: Data, service: String, account: String) throws {
        throw Failure(message: secret)
    }

    func delete(service: String, account: String) throws {
        throw Failure(message: secret)
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
