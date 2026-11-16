import Foundation
import Security

protocol APIKeyRepository: Sendable {
    func apiKey() async throws -> String?
    func saveAPIKey(_ apiKey: String) async throws
    func deleteAPIKey() async throws
}

enum APIKeyRepositoryOperation: String, Equatable, Sendable {
    case read
    case save
    case delete
}

enum APIKeyRepositoryError: LocalizedError, Equatable {
    case emptyAPIKey
    case invalidStoredValue
    case keychainFailure(operation: APIKeyRepositoryOperation, status: OSStatus?)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "API key can’t be empty."
        case .invalidStoredValue:
            "The API key in Keychain isn’t readable text."
        case .keychainFailure(let operation, let status):
            if let status {
                "Keychain operation failed (\(operation.rawValue), status: \(status))."
            } else {
                "Keychain operation failed (\(operation.rawValue))."
            }
        }
    }
}

protocol KeychainDataStore: Sendable {
    func read(service: String, account: String) throws -> Data?
    func save(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SystemKeychainDataStore: KeychainDataStore, Sendable {
    func read(service: String, account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(service: service, account: account, returningData: true) as CFDictionary,
            &result
        )

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainDataStoreError.unexpectedResult
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainDataStoreError.status(status)
        }
    }

    func save(_ data: Data, service: String, account: String) throws {
        var attributes = query(service: service, account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                query(service: service, account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainDataStoreError.status(updateStatus)
            }
        default:
            throw KeychainDataStoreError.status(addStatus)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainDataStoreError.status(status)
        }
    }

    private func query(
        service: String,
        account: String,
        returningData: Bool = false
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

private enum KeychainDataStoreError: Error {
    case status(OSStatus)
    case unexpectedResult
}

actor KeychainAPIKeyRepository: APIKeyRepository {
    static let defaultService = "gad.MeetingNotch.transcription-api-keys"
    static let openAIService = "gad.MeetingNotch.openai-api-key"
    static let account = "elevenlabs-api-key"
    static let legacyElevenLabsAccount = "elevenLabs"

    private let store: any KeychainDataStore
    private let service: String

    init(
        store: any KeychainDataStore = SystemKeychainDataStore(),
        service: String = defaultService
    ) {
        self.store = store
        self.service = service
    }

    func apiKey() throws -> String? {
        do {
            if let data = try store.read(service: service, account: Self.account) {
                return try decodedAPIKey(from: data)
            }

            guard let legacyData = try store.read(
                service: service,
                account: Self.legacyElevenLabsAccount
            ) else {
                return nil
            }
            let legacyKey = try decodedAPIKey(from: legacyData)

            // Save-first keeps the old credential intact if migration cannot complete.
            try store.save(
                Data(legacyKey.utf8),
                service: service,
                account: Self.account
            )
            try? store.delete(service: service, account: Self.legacyElevenLabsAccount)
            return legacyKey
        } catch let error as APIKeyRepositoryError {
            throw error
        } catch {
            throw sanitizedFailure(error, operation: .read)
        }
    }

    func saveAPIKey(_ apiKey: String) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw APIKeyRepositoryError.emptyAPIKey
        }

        do {
            try store.save(Data(normalizedKey.utf8), service: service, account: Self.account)
            try? store.delete(service: service, account: Self.legacyElevenLabsAccount)
        } catch {
            throw sanitizedFailure(error, operation: .save)
        }
    }

    func deleteAPIKey() throws {
        var firstError: Error?
        for account in [Self.account, Self.legacyElevenLabsAccount] {
            do {
                try store.delete(service: service, account: account)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw sanitizedFailure(firstError, operation: .delete)
        }
    }

    private func decodedAPIKey(from data: Data) throws -> String {
        guard let apiKey = String(data: data, encoding: .utf8) else {
            throw APIKeyRepositoryError.invalidStoredValue
        }
        return apiKey
    }

    private func sanitizedFailure(
        _ error: Error,
        operation: APIKeyRepositoryOperation
    ) -> APIKeyRepositoryError {
        if case KeychainDataStoreError.status(let status) = error {
            return .keychainFailure(operation: operation, status: status)
        }
        return .keychainFailure(operation: operation, status: nil)
    }
}
