import Foundation

protocol AppSettingsRepository: Sendable {
    func load() async throws -> AppPreferences
    func save(_ preferences: AppPreferences) async throws
    func reset() async
}

enum AppSettingsRepositoryError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case corruptStore(recoveryKey: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported settings version: \(version)."
        case .corruptStore(let recoveryKey):
            "Couldn’t read settings; saved a copy under \(recoveryKey)."
        }
    }
}

actor UserDefaultsAppSettingsRepository: AppSettingsRepository {
    private struct StoreDocument: Codable {
        static let currentSchemaVersion = 2
        static let supportedSchemaVersions = 1...currentSchemaVersion

        let schemaVersion: Int
        let preferences: AppPreferences

        init(
            schemaVersion: Int = currentSchemaVersion,
            preferences: AppPreferences
        ) {
            self.schemaVersion = schemaVersion
            self.preferences = preferences
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let recoveryKeyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "app.preferences",
        recoveryKeyPrefix: String = "recovery.app-preferences"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.recoveryKeyPrefix = recoveryKeyPrefix
    }

    func load() throws -> AppPreferences {
        guard let data = defaults.object(forKey: storageKey) else { return .default }
        let document = try readDocument(data)
        if document.schemaVersion < StoreDocument.currentSchemaVersion {
            try write(document.preferences)
        }
        return document.preferences
    }

    private func readDocument(_ value: Any) throws -> StoreDocument {
        struct Header: Decodable { let schemaVersion: Int }
        do {
            guard let data = value as? Data else {
                throw CocoaError(.coderReadCorrupt)
            }
            let header = try decoder.decode(Header.self, from: data)
            guard StoreDocument.supportedSchemaVersions.contains(header.schemaVersion) else {
                throw AppSettingsRepositoryError.unsupportedSchema(header.schemaVersion)
            }
            return try decoder.decode(StoreDocument.self, from: data)
        } catch let error as AppSettingsRepositoryError {
            throw error
        } catch {
            let recoveryKey = "\(recoveryKeyPrefix).original"
            defaults.set(value, forKey: recoveryKey)
            throw AppSettingsRepositoryError.corruptStore(recoveryKey: recoveryKey)
        }
    }

    func save(_ preferences: AppPreferences) throws {
        if let existing = defaults.object(forKey: storageKey) {
            _ = try readDocument(existing)
        }
        try write(preferences)
    }

    private func write(_ preferences: AppPreferences) throws {
        let data = try encoder.encode(StoreDocument(preferences: preferences))
        defaults.set(data, forKey: storageKey)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: "\(recoveryKeyPrefix).original")
    }
}
