import Foundation

struct AppStorageLayout: Sendable {
    let root: URL
    let meetings: URL
    let tasks: URL
    let temporary: URL
    let recovery: URL
    let processingQueue: URL

    init(root: URL) {
        self.root = root
        meetings = root.appending(path: "Meetings", directoryHint: .isDirectory)
        tasks = root.appending(path: "Tasks", directoryHint: .isDirectory)
        temporary = root.appending(path: "Temporary", directoryHint: .isDirectory)
        recovery = root.appending(path: "Recovery", directoryHint: .isDirectory)
        processingQueue = root.appending(path: "ProcessingQueue", directoryHint: .isDirectory)
    }

    static func applicationSupport(
        fileManager: FileManager = .default,
        rootOverride: URL? = nil
    ) throws -> AppStorageLayout {
        if let rootOverride {
            return AppStorageLayout(root: rootOverride)
        }

        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AppStorageLayout(
            root: applicationSupport.appending(path: "Crenel", directoryHint: .isDirectory)
        )
    }

    func createDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, meetings, tasks, temporary, recovery, processingQueue] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
