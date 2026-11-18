import Foundation

/// Local JSON next to the task store holding Crenel-only metadata for reminders.
actor TaskSidecarFile {
    struct Document: Codable, Equatable {
        static let currentSchemaVersion = 1
        var schemaVersion = currentSchemaVersion
        var listIdentifier: String?
        // Read the original migration flag when upgrading a v1 sidecar.
        var migratedLocalStore = false
        var migratedTaskIDs: Set<UUID>?
        var entries: [String: TaskSidecarEntry] = [:]
    }

    private let url: URL
    private let fileManager: FileManager
    private var cached: Document?

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let layout = try AppStorageLayout.applicationSupport(fileManager: fileManager)
        return layout.tasks.appending(path: "reminders-sidecar.json")
    }

    func reset() throws {
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        cached = nil
    }

    func load() -> Document {
        if let cached { return cached }
        let document: Document
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Document.self, from: data) {
            document = decoded
        } else {
            document = Document()
        }
        cached = document
        return document
    }

    func update(_ change: (inout Document) -> Void) throws {
        var document = load()
        change(&document)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
        cached = document
    }
}

/// Tasks stored as Apple Reminders in a single list, plus a local sidecar for state
/// Reminders cannot express (in progress, manual order, meeting source).
actor RemindersTaskRepository: TaskRepository {
    static let defaultListTitle = "Crenel"

    private let store: any ReminderStore
    private let sidecar: TaskSidecarFile
    private let listTitle: String
    private let historyWindow: TimeInterval
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var listIdentifier: String?
    private var reminderIDsByTaskID: [UUID: String] = [:]

    init(
        store: any ReminderStore,
        sidecar: TaskSidecarFile,
        listTitle: String = defaultListTitle,
        historyWindow: TimeInterval = 30 * 24 * 60 * 60,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.sidecar = sidecar
        self.listTitle = listTitle
        self.historyWindow = historyWindow
        self.calendar = calendar
        self.now = now
    }

    private var resetGeneration: UInt64 = 0
    private var migration: Task<Int, Error>?
    private var migrationSequence: UInt64 = 0

    func reset() async throws {
        resetGeneration &+= 1
        migration?.cancel()
        migration = nil
        listIdentifier = nil
        reminderIDsByTaskID.removeAll()
        try await sidecar.reset()
    }

    func prepare() async throws {
        let generation = resetGeneration
        let stored = await sidecar.load().listIdentifier
        let identifier = try await store.prepareList(preferredIdentifier: stored, title: listTitle)
        guard generation == resetGeneration else { throw CancellationError() }
        listIdentifier = identifier
        if identifier != stored {
            try await sidecar.update { $0.listIdentifier = identifier }
        }
    }

    func loadAll() async throws -> [TaskItem] {
        let generation = resetGeneration
        let list = try await resolvedList()
        let records = try await store.fetch(
            listIdentifier: list,
            completedSince: now().addingTimeInterval(-historyWindow)
        )
        let entries = await sidecar.load().entries
        guard generation == resetGeneration else { throw CancellationError() }
        // Saves made in this session may not have reached the sidecar file yet.
        let knownTaskIDs = Dictionary(
            reminderIDsByTaskID.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<UUID>()
        var tasks: [TaskItem] = []
        for record in records {
            let entry = record.identifier.flatMap { identifier in
                entries[identifier] ?? knownTaskIDs[identifier].map { TaskSidecarEntry(taskID: $0) }
            }
            let task = ReminderTaskMapper.task(
                from: record,
                sidecar: entry,
                calendar: calendar,
                fallbackCreationDate: now()
            )
            guard seen.insert(task.id).inserted else { continue }
            if let identifier = record.identifier {
                reminderIDsByTaskID[task.id] = identifier
            }
            tasks.append(task)
        }
        return tasks
    }

    func save(_ task: TaskItem) async throws {
        let generation = resetGeneration
        let list = try await resolvedList()
        let knownIdentifier = task.reminderIdentifier ?? reminderIDsByTaskID[task.id]
        let identifier: String
        do {
            identifier = try await store.save(
                ReminderTaskMapper.record(from: task, identifier: knownIdentifier, calendar: calendar),
                listIdentifier: list
            )
        } catch ReminderStoreError.reminderNotFound {
            // Deleted on another device while edited here: recreate it.
            identifier = try await store.save(
                ReminderTaskMapper.record(from: task, identifier: nil, calendar: calendar),
                listIdentifier: list
            )
        }
        guard generation == resetGeneration else { throw CancellationError() }
        reminderIDsByTaskID[task.id] = identifier
        let entry = ReminderTaskMapper.sidecar(from: task)
        try await sidecar.update { document in
            if let knownIdentifier, knownIdentifier != identifier {
                document.entries[knownIdentifier] = nil
            }
            document.entries[identifier] = entry
        }
    }

    func delete(id: UUID) async throws {
        let generation = resetGeneration
        if reminderIDsByTaskID[id] == nil {
            _ = try await loadAll()
        }
        guard let identifier = reminderIDsByTaskID[id] else { return }
        let list = try await resolvedList()
        try await store.remove(identifier: identifier, listIdentifier: list)
        // "Delete all data" may have run meanwhile; don't write a fresh sidecar after it.
        guard generation == resetGeneration else { throw CancellationError() }
        reminderIDsByTaskID[id] = nil
        try await sidecar.update { $0.entries[identifier] = nil }
    }

    /// Imports newly eligible local tasks whenever Reminders becomes active.
    func migrateIfNeeded(from local: any TaskRepository) async throws -> Int {
        // EventKit awaits let a second activation enter this actor before the first one
        // has checkpointed its writes. Queue the rescan behind the previous import.
        let previous = migration
        let generation = resetGeneration
        migrationSequence &+= 1
        let sequence = migrationSequence
        let pending = Task {
            _ = await previous?.result
            guard generation == resetGeneration else { throw CancellationError() }
            return try await importLocalTasks(from: local, generation: generation)
        }
        migration = pending
        defer { if migrationSequence == sequence { migration = nil } }
        return try await pending.value
    }

    private func importLocalTasks(from local: any TaskRepository, generation: UInt64) async throws -> Int {
        let document = await sidecar.load()
        // An older completed migration recorded task identity in its entries.
        let imported = document.migratedTaskIDs ?? (document.migratedLocalStore
            ? Set(document.entries.values.map(\.taskID)) : [])
        let cutoff = now().addingTimeInterval(-historyWindow)
        let candidates = try await local.loadAll().filter { task in
            !imported.contains(task.id) && !task.isArchived && (!task.isCompleted || (task.completedAt ?? .distantPast) >= cutoff)
        }
        if !candidates.isEmpty {
            // A previous activation may have saved only a prefix before failing.
            _ = try await loadAll()
            // Include old completed reminders outside the normal display window.
            for (identifier, entry) in document.entries where reminderIDsByTaskID[entry.taskID] == nil {
                reminderIDsByTaskID[entry.taskID] = identifier
            }
        }
        for task in candidates {
            guard generation == resetGeneration else { throw CancellationError() }
            var copy = task
            copy.reminderIdentifier = nil
            try await save(copy)
        }
        guard generation == resetGeneration else { throw CancellationError() }
        if !candidates.isEmpty || document.migratedTaskIDs == nil {
            try await sidecar.update {
                var migrated = $0.migratedTaskIDs ?? imported
                migrated.formUnion(candidates.map(\.id))
                $0.migratedTaskIDs = migrated
            }
        }
        return candidates.count
    }

    private func resolvedList() async throws -> String {
        if let listIdentifier { return listIdentifier }
        try await prepare()
        guard let listIdentifier else { throw ReminderStoreError.listUnavailable }
        return listIdentifier
    }
}

enum TaskStorageBackend: String, Codable, Sendable {
    case reminders
    case local
}

/// What the task UI tells the user about where tasks live.
enum TaskStorageStatus: Equatable, Sendable {
    case reminders(listTitle: String)
    case localNotConnected
    case localDenied
    case localByChoice
    case localAfterError(String)

    var isReminders: Bool {
        if case .reminders = self { return true }
        return false
    }
}

/// Routes task persistence to Apple Reminders when allowed, otherwise to the local file.
actor TaskRepositoryRouter: TaskRepository {
    private let local: any TaskRepository
    private let reminders: RemindersTaskRepository
    private let store: any ReminderStore
    private(set) var backend: TaskStorageBackend = .local

    init(local: any TaskRepository, reminders: RemindersTaskRepository, store: any ReminderStore) {
        self.local = local
        self.reminders = reminders
        self.store = store
    }

    func reset() async throws {
        backend = .local
        try await reminders.reset()
    }

    /// Picks the backend without prompting. Call at launch and when the preference changes.
    func activate(preferReminders: Bool) async -> TaskStorageStatus {
        guard preferReminders else {
            backend = .local
            return .localByChoice
        }
        switch await store.accessState() {
        case .notDetermined:
            backend = .local
            return .localNotConnected
        case .denied, .restricted:
            backend = .local
            return .localDenied
        case .authorized:
            do {
                try await reminders.prepare()
                _ = try await reminders.migrateIfNeeded(from: local)
                backend = .reminders
                return .reminders(listTitle: RemindersTaskRepository.defaultListTitle)
            } catch {
                backend = .local
                AppLogger.persistenceFailed(operation: "activate-reminders", error: error)
                return .localAfterError(
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't open Reminders."
                )
            }
        }
    }

    /// Asks for Reminders access (user action) and switches when granted.
    func connectReminders() async -> TaskStorageStatus {
        do {
            _ = try await store.requestAccess()
        } catch {
            return .localAfterError("Couldn't request Reminders access.")
        }
        return await activate(preferReminders: true)
    }

    func prepare() async throws {
        try await current.prepare()
    }

    func loadAll() async throws -> [TaskItem] {
        try await current.loadAll()
    }

    func save(_ task: TaskItem) async throws {
        try await current.save(task)
    }

    func delete(id: UUID) async throws {
        try await current.delete(id: id)
    }

    func importAction(_ action: ActionItem, meetingID: UUID) async throws -> TaskItem {
        try await current.importAction(action, meetingID: meetingID)
    }

    private var current: any TaskRepository {
        backend == .reminders ? reminders : local
    }
}
