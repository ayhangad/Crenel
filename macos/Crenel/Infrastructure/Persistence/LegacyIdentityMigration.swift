import Foundation
import Security

/// The app shipped its early builds under an older bundle identifier and storage name.
/// On first launch as `gad.Crenel` this carries that data over once: the Application
/// Support folder (meetings, tasks, recovery, queue), user defaults, the API keys in
/// Keychain, and the Chrome native-host manifest that pointed at the old host name.
/// The old identifiers live only here.
struct LegacyIdentityMigration {
    static let legacyBundleIdentifier = "gad.MeetingNotch"
    static let legacyFolderName = "MeetingNotch"
    static let legacyNativeHostName = "com.gad.meetingnotch.browser_audio"
    static let completedKey = "legacyIdentityMigrationCompleted"
    static let keychainServiceSuffixes = [
        "transcription-api-keys",
        "openai-api-key",
        "anthropic-api-key",
        "google-calendar-oauth"
    ]

    var fileManager: FileManager = .default
    var applicationSupport: URL
    var homeDirectory: URL
    var defaults: UserDefaults
    var legacyDefaults: () -> [String: Any]?
    var keychain: any LegacyKeychainMigrating

    static func live() -> LegacyIdentityMigration? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return LegacyIdentityMigration(
            applicationSupport: support,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            defaults: .standard,
            legacyDefaults: { UserDefaults.standard.persistentDomain(forName: legacyBundleIdentifier) },
            keychain: SystemLegacyKeychainMigrator()
        )
    }

    /// Runs at most once per user account; each step is best effort and never overwrites
    /// data that already exists under the new identity.
    static func runIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil,
              let migration = live() else { return }
        migration.run()
    }

    func run() {
        // The folder move is safe to repeat: an early build could create an empty Crenel
        // folder before this migration existed, which made the first run skip the move.
        moveStorageFolder()
        guard !defaults.bool(forKey: Self.completedKey) else { return }
        copyDefaults()
        moveKeychainItems()
        removeLegacyNativeHostManifest()
        defaults.set(true, forKey: Self.completedKey)
    }

    func moveStorageFolder() {
        let legacy = applicationSupport.appending(path: Self.legacyFolderName, directoryHint: .isDirectory)
        let current = applicationSupport.appending(path: "Crenel", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        if fileManager.fileExists(atPath: current.path) {
            // Only empty folders: nothing under the new name to keep.
            guard !containsFiles(current) else { return }
            guard (try? fileManager.removeItem(at: current)) != nil else { return }
        }
        try? fileManager.moveItem(at: legacy, to: current)
    }

    private func containsFiles(_ folder: URL) -> Bool {
        guard let items = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return true
        }
        for case let url as URL in items {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory { return true }
        }
        return false
    }

    func copyDefaults() {
        guard let values = legacyDefaults() else { return }
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    func moveKeychainItems() {
        for suffix in Self.keychainServiceSuffixes {
            keychain.move(
                fromService: "\(Self.legacyBundleIdentifier).\(suffix)",
                toService: "gad.Crenel.\(suffix)"
            )
        }
    }

    func removeLegacyNativeHostManifest() {
        let manifest = homeDirectory
            .appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
            .appending(path: "\(Self.legacyNativeHostName).json")
        try? fileManager.removeItem(at: manifest)
    }
}

protocol LegacyKeychainMigrating: Sendable {
    func move(fromService: String, toService: String)
}

struct SystemLegacyKeychainMigrator: LegacyKeychainMigrating {
    private let store: any KeychainDataStore = SystemKeychainDataStore()

    func move(fromService: String, toService: String) {
        for account in accounts(service: fromService) {
            guard let data = try? store.read(service: fromService, account: account) else { continue }
            if (try? store.read(service: toService, account: account)) == nil {
                guard (try? store.save(data, service: toService, account: account)) != nil else { continue }
            }
            try? store.delete(service: fromService, account: account)
        }
    }

    private func accounts(service: String) -> [String] {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
