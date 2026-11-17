import Foundation
import Security
import XCTest
@testable import Crenel

final class KeychainAPIKeyRepositoryTests: XCTestCase {
    func testSaveAndReadUseSingleElevenLabsAccount() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        try await repository.saveAPIKey("  eleven-labs-secret\n")

        let elevenLabsKey = try await repository.apiKey()
        XCTAssertEqual(elevenLabsKey, "eleven-labs-secret")
        XCTAssertEqual(store.lastService, "test.service")
        XCTAssertEqual(store.accounts, Set([KeychainAPIKeyRepository.account]))
    }

    func testSaveReplacesExistingKey() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store)
        try await repository.saveAPIKey("old-secret")

        try await repository.saveAPIKey("new-secret")

        let stored = try await repository.apiKey()
        XCTAssertEqual(stored, "new-secret")
    }

    func testMissingKeyReturnsNilAndDeleteIsIdempotent() async throws {
        let repository = KeychainAPIKeyRepository(store: InMemoryKeychainDataStore())

        let missingKey = try await repository.apiKey()
        XCTAssertNil(missingKey)
        try await repository.deleteAPIKey()
        try await repository.deleteAPIKey()
    }

    func testLegacyElevenLabsAccountMigratesWithoutLosingKey() async throws {
        let store = InMemoryKeychainDataStore()
        try store.save(
            Data("legacy-eleven-secret".utf8),
            service: "test.service",
            account: KeychainAPIKeyRepository.legacyElevenLabsAccount
        )
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        let migrated = try await repository.apiKey()

        XCTAssertEqual(migrated, "legacy-eleven-secret")
        XCTAssertEqual(store.accounts, Set([KeychainAPIKeyRepository.account]))
    }

    func testExistingSingleAccountWinsOverLegacyAccount() async throws {
        let store = InMemoryKeychainDataStore()
        try store.save(
            Data("current".utf8),
            service: "test.service",
            account: KeychainAPIKeyRepository.account
        )
        try store.save(
            Data("legacy".utf8),
            service: "test.service",
            account: KeychainAPIKeyRepository.legacyElevenLabsAccount
        )
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        let stored = try await repository.apiKey()
        XCTAssertEqual(stored, "current")
    }

    func testDeleteRemovesCurrentAndLegacyAccounts() async throws {
        let store = InMemoryKeychainDataStore()
        try store.save(
            Data("current".utf8),
            service: "test.service",
            account: KeychainAPIKeyRepository.account
        )
        try store.save(
            Data("legacy".utf8),
            service: "test.service",
            account: KeychainAPIKeyRepository.legacyElevenLabsAccount
        )
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        try await repository.deleteAPIKey()

        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testBlankKeyIsRejectedWithoutWriting() async throws {
        let store = InMemoryKeychainDataStore()
        let repository = KeychainAPIKeyRepository(store: store)

        do {
            try await repository.saveAPIKey(" \n\t ")
            XCTFail("Boş API anahtarının reddedilmesi bekleniyordu.")
        } catch let error as APIKeyRepositoryError {
            XCTAssertEqual(error, .emptyAPIKey)
        }

        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testInvalidUTF8StoredValueIsRejected() async throws {
        let store = InMemoryKeychainDataStore()
        try store.save(
            Data([0xFF]),
            service: "test.service",
            account: KeychainAPIKeyRepository.account
        )
        let repository = KeychainAPIKeyRepository(store: store, service: "test.service")

        do {
            _ = try await repository.apiKey()
            XCTFail("Geçersiz metin verisinin reddedilmesi bekleniyordu.")
        } catch let error as APIKeyRepositoryError {
            XCTAssertEqual(error, .invalidStoredValue)
        }
    }

    func testStorageFailureDoesNotExposeAPIKey() async throws {
        let secret = "must-never-appear-in-errors-or-logs"
        let repository = KeychainAPIKeyRepository(store: FailingKeychainDataStore(secret: secret))

        do {
            try await repository.saveAPIKey(secret)
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
        try await keyRepository.saveAPIKey(secret)

        let suiteName = "KeychainAPIKeyRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsRepository = UserDefaultsAppSettingsRepository(
            defaults: defaults,
            storageKey: "test.preferences"
        )
        var preferences = AppPreferences.default
        preferences.transcription.languageCode = "tr"
        try await settingsRepository.save(preferences)

        let settingsData = try XCTUnwrap(defaults.data(forKey: "test.preferences"))
        XCTAssertFalse(String(decoding: settingsData, as: UTF8.self).contains(secret))
        let storedKey = try await keyRepository.apiKey()
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
