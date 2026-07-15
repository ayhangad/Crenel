import Foundation

protocol TaskRepository: Sendable {
    func prepare() async throws
    func loadAll() async throws -> [TaskItem]
    func save(_ task: TaskItem) async throws
    func delete(id: UUID) async throws
}

enum TaskRepositoryError: LocalizedError, Equatable {
    case duplicateTaskID(UUID)
    case unsupportedSchema(Int)
    case corruptStore(recoveryURL: URL?)

    var errorDescription: String? {
        switch self {
        case .duplicateTaskID:
            "Görev verileri aynı kimliğe sahip birden fazla kayıt içeriyor."
        case .unsupportedSchema(let version):
            "Görev verisi sürümü desteklenmiyor: \(version)."
        case .corruptStore(let recoveryURL):
            if let recoveryURL {
                "Görev verisi okunamadı ve kurtarma alanına taşındı: \(recoveryURL.lastPathComponent)."
            } else {
                "Görev verisi okunamadı; özgün dosya silinmeden korundu."
            }
        }
    }
}

actor FileTaskRepository: TaskRepository {
    private struct StoreDocument: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var tasks: [TaskItem]

        init(
            schemaVersion: Int = currentSchemaVersion,
            tasks: [TaskItem] = []
        ) {
            self.schemaVersion = schemaVersion
            self.tasks = tasks
        }
    }

    private let fileManager: FileManager
    private let layout: AppStorageLayout
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var storeURL: URL {
        layout.tasks.appending(path: "tasks.json")
    }

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        layout = AppStorageLayout(
            root: rootURL ?? defaultRoot.appending(path: "MeetingNotch", directoryHint: .isDirectory)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        self.decoder = decoder
    }

    func prepare() throws {
        try layout.createDirectories(fileManager: fileManager)
    }

    func loadAll() throws -> [TaskItem] {
        try prepare()
        return try loadDocument().tasks
    }

    func save(_ task: TaskItem) throws {
        try prepare()
        var document = try loadDocument()
        if let index = document.tasks.firstIndex(where: { $0.id == task.id }) {
            document.tasks[index] = task
        } else {
            document.tasks.append(task)
        }
        try validateUniqueIDs(document.tasks)
        try write(document)
    }

    func delete(id: UUID) throws {
        try prepare()
        var document = try loadDocument()
        let originalCount = document.tasks.count
        document.tasks.removeAll { $0.id == id }
        guard document.tasks.count != originalCount else { return }
        try write(document)
    }

    private func loadDocument() throws -> StoreDocument {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return StoreDocument()
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let document = try decoder.decode(StoreDocument.self, from: data)
            guard document.schemaVersion == StoreDocument.currentSchemaVersion else {
                throw TaskRepositoryError.unsupportedSchema(document.schemaVersion)
            }
            try validateUniqueIDs(document.tasks)
            return document
        } catch let error as TaskRepositoryError {
            throw error
        } catch {
            let recoveryURL = moveCorruptStoreToRecovery()
            throw TaskRepositoryError.corruptStore(recoveryURL: recoveryURL)
        }
    }

    private func write(_ document: StoreDocument) throws {
        let data = try encoder.encode(document)
        try data.write(to: storeURL, options: .atomic)
    }

    private func validateUniqueIDs(_ tasks: [TaskItem]) throws {
        var ids = Set<UUID>()
        for task in tasks where !ids.insert(task.id).inserted {
            throw TaskRepositoryError.duplicateTaskID(task.id)
        }
    }

    private func moveCorruptStoreToRecovery() -> URL? {
        let destination = layout.recovery.appending(
            path: "Corrupt-Tasks-\(UUID().uuidString.prefix(8)).json"
        )
        do {
            try fileManager.moveItem(at: storeURL, to: destination)
            return destination
        } catch {
            AppLogger.persistenceFailed(
                operation: "recover-task-store",
                message: error.localizedDescription
            )
            return nil
        }
    }
}
