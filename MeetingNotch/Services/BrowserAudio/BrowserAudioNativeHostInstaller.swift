import Foundation

enum BrowserAudioNativeHostInstallerError: Error {
    case embeddedHostMissing
}

struct BrowserAudioNativeHostInstaller {
    static let hostName = "com.gad.meetingnotch.browser_audio"
    static let executableName = "MeetingNotchBrowserAudioHost"

    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func install(bundleURL: URL) throws -> URL {
        let executableURL = bundleURL
            .appending(path: "Contents/Library/LaunchServices", directoryHint: .isDirectory)
            .appending(path: Self.executableName)
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw BrowserAudioNativeHostInstallerError.embeddedHostMissing
        }

        let directory = homeDirectory
            .appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let manifestURL = directory.appending(path: "\(Self.hostName).json")
        let manifest: [String: Any] = [
            "name": Self.hostName,
            "description": "MeetingNotch Google Meet tab audio bridge",
            "path": executableURL.path,
            "type": "stdio",
            "allowed_origins": [BrowserAudioProtocol.expectedExtensionOrigin]
        ]
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: manifestURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
        return manifestURL
    }
}
