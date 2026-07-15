import Foundation

protocol ProcessingJobRepository: Sendable {
    func prepare() async throws
    func loadAll() async throws -> [ProcessingJob]
    func replaceAll(_ jobs: [ProcessingJob]) async throws
}

enum ProcessingJobRepositoryError: Error, Equatable {
    case unsupportedSchema(Int)
    case duplicateJobID(UUID)
    case duplicateMeetingID(UUID)
    case corruptStore
}

actor FileProcessingJobRepository: ProcessingJobRepository {
    private struct StoreDocument: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var jobs: [ProcessingJob]

        init(schemaVersion: Int = currentSchemaVersion, jobs: [ProcessingJob]) {
            self.schemaVersion = schemaVersion
            self.jobs = jobs
        }
    }

    private let fileManager: FileManager
    private let layout: AppStorageLayout
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var storeURL: URL {
        layout.processingQueue.appending(path: "queue.json")
    }

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        layout = AppStorageLayout(
            root: rootURL ?? defaultRoot.appending(path: "MeetingNotch", directoryHint: .isDirectory)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func prepare() throws {
        try layout.createDirectories(fileManager: fileManager)
    }

    func loadAll() throws -> [ProcessingJob] {
        try prepare()
        guard fileManager.fileExists(atPath: storeURL.path) else { return [] }

        do {
            let document = try decoder.decode(
                StoreDocument.self,
                from: Data(contentsOf: storeURL)
            )
            guard document.schemaVersion == StoreDocument.currentSchemaVersion else {
                throw ProcessingJobRepositoryError.unsupportedSchema(document.schemaVersion)
            }
            try validate(document.jobs)
            return document.jobs
        } catch let error as ProcessingJobRepositoryError {
            throw error
        } catch {
            moveCorruptStoreToRecovery()
            throw ProcessingJobRepositoryError.corruptStore
        }
    }

    func replaceAll(_ jobs: [ProcessingJob]) throws {
        try prepare()
        try validate(jobs)
        let data = try encoder.encode(StoreDocument(jobs: jobs))
        try data.write(to: storeURL, options: .atomic)
    }

    private func validate(_ jobs: [ProcessingJob]) throws {
        var jobIDs = Set<UUID>()
        var meetingIDs = Set<UUID>()
        for job in jobs {
            guard jobIDs.insert(job.id).inserted else {
                throw ProcessingJobRepositoryError.duplicateJobID(job.id)
            }
            guard meetingIDs.insert(job.meetingID).inserted else {
                throw ProcessingJobRepositoryError.duplicateMeetingID(job.meetingID)
            }
        }
    }

    private func moveCorruptStoreToRecovery() {
        let destination = layout.recovery.appending(
            path: "Corrupt-ProcessingQueue-\(UUID().uuidString.prefix(8)).json"
        )
        do {
            try fileManager.moveItem(at: storeURL, to: destination)
        } catch {
            AppLogger.persistenceFailed(operation: "recover-processing-queue", error: error)
        }
    }
}
