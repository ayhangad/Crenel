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
            "Uygulama ayarları sürümü desteklenmiyor: \(version)."
        case .corruptStore(let recoveryKey):
            "Uygulama ayarları okunamadı ve \(recoveryKey) anahtarında korundu."
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
        guard let data = defaults.data(forKey: storageKey) else {
            return .default
        }

        do {
            let document = try decoder.decode(StoreDocument.self, from: data)
            guard StoreDocument.supportedSchemaVersions.contains(document.schemaVersion) else {
                throw AppSettingsRepositoryError.unsupportedSchema(document.schemaVersion)
            }
            if document.schemaVersion < StoreDocument.currentSchemaVersion {
                try save(document.preferences)
            }
            return document.preferences
        } catch let error as AppSettingsRepositoryError {
            throw error
        } catch {
            let recoveryKey = "\(recoveryKeyPrefix).\(UUID().uuidString)"
            defaults.set(data, forKey: recoveryKey)
            defaults.removeObject(forKey: storageKey)
            throw AppSettingsRepositoryError.corruptStore(recoveryKey: recoveryKey)
        }
    }

    func save(_ preferences: AppPreferences) throws {
        let data = try encoder.encode(StoreDocument(preferences: preferences))
        defaults.set(data, forKey: storageKey)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
    }
}
