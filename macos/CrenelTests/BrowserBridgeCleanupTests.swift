import XCTest
@testable import Crenel

final class BrowserBridgeCleanupTests: XCTestCase {
    func testRemovesTheOldChromeNativeHostManifest() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let hosts = home.appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
        let manifest = hosts.appending(path: "\(BrowserBridgeCleanup.hostName).json")
        let other = hosts.appending(path: "com.example.other.json")
        try Data("{}".utf8).write(to: manifest)
        try Data("{}".utf8).write(to: other)

        BrowserBridgeCleanup.removeLeftovers(homeDirectory: home)

        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }
}
