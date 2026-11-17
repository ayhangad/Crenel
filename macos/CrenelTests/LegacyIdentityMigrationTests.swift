import Foundation
import XCTest
@testable import Crenel

final class LegacyIdentityMigrationTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "LegacyIdentityMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "LegacyIdentityMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func testMovesFolderCopiesMissingDefaultsMovesKeysAndRemovesOldHostManifest() throws {
        let support = root.appending(path: "Support", directoryHint: .isDirectory)
        let legacyMeeting = support.appending(path: "MeetingNotch/Meetings/a.json")
        try FileManager.default.createDirectory(at: legacyMeeting.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacyMeeting)
        let hosts = root.appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
        let oldManifest = hosts.appending(path: "com.gad.meetingnotch.browser_audio.json")
        try Data("{}".utf8).write(to: oldManifest)
        defaults.set("kept", forKey: "existing")
        let keychain = RecordingKeychainMigrator()

        let migration = LegacyIdentityMigration(
            applicationSupport: support,
            homeDirectory: root,
            defaults: defaults,
            legacyDefaults: { ["existing": "old", "leadTime": 300] },
            keychain: keychain
        )
        migration.run()

        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appending(path: "Crenel/Meetings/a.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appending(path: "MeetingNotch").path))
        XCTAssertEqual(defaults.string(forKey: "existing"), "kept")
        XCTAssertEqual(defaults.integer(forKey: "leadTime"), 300)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldManifest.path))
        XCTAssertTrue(keychain.moves.contains(where: {
            $0 == ("gad.MeetingNotch.openai-api-key", "gad.Crenel.openai-api-key")
        }))
        XCTAssertTrue(defaults.bool(forKey: LegacyIdentityMigration.completedKey))
    }

    func testNeverOverwritesExistingCrenelFolderAndRunsOnce() throws {
        let support = root.appending(path: "Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support.appending(path: "MeetingNotch"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support.appending(path: "Crenel"), withIntermediateDirectories: true)
        let keychain = RecordingKeychainMigrator()
        let migration = LegacyIdentityMigration(
            applicationSupport: support,
            homeDirectory: root,
            defaults: defaults,
            legacyDefaults: { nil },
            keychain: keychain
        )

        migration.run()
        let firstRunMoves = keychain.moves.count
        migration.run()

        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appending(path: "MeetingNotch").path))
        XCTAssertEqual(keychain.moves.count, firstRunMoves)
    }
}

private final class RecordingKeychainMigrator: LegacyKeychainMigrating, @unchecked Sendable {
    private(set) var moves: [(String, String)] = []

    func move(fromService: String, toService: String) {
        moves.append((fromService, toService))
    }
}
