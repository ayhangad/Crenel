import Foundation

/// Crenel no longer talks to a Chrome extension. Builds up to 1.3 registered a native
/// messaging host with Chrome and left a socket directory behind; remove both on launch so
/// Chrome stops pointing at a helper that no longer ships.
enum BrowserBridgeCleanup {
    static let hostName = "com.gad.crenel.browser_audio"

    static func removeLeftovers(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let manifest = homeDirectory
            .appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
            .appending(path: "\(hostName).json")
        try? fileManager.removeItem(at: manifest)
        let socketDirectory = fileManager.temporaryDirectory
            .appending(path: "crenel-browser-audio-\(getuid())", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: socketDirectory)
    }
}
