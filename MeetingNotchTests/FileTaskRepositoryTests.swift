import Foundation
import XCTest
@testable import MeetingNotch

final class FileTaskRepositoryTests: XCTestCase {
    private var root: URL!
    private var repository: FileTaskRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "TaskRepositoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        repository = FileTaskRepository(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPrepareCreatesTaskDirectory() async throws {
        try await repository.prepare()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appending(path: "Tasks").path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSaveLoadsActiveAndArchivedTasksAfterRestart() async throws {
        let active = TaskItem(
            id: UUID(),
            title: "Takip e-postasını gönder",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let archived = TaskItem(
            id: UUID(),
            title: "Kararı paylaş",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            completedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )

        try await repository.save(active)
        try await repository.save(archived)

        let restartedRepository = FileTaskRepository(rootURL: root)
        let loaded = try await restartedRepository.loadAll()
        XCTAssertEqual(loaded, [active, archived])

        let data = try Data(contentsOf: root.appending(path: "Tasks/tasks.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 3)
    }

    func testSaveUpdatesExistingTaskWithoutChangingItsPosition() async throws {
        let first = TaskItem(title: "İlk", createdAt: Date(timeIntervalSince1970: 1))
        let second = TaskItem(title: "İkinci", createdAt: Date(timeIntervalSince1970: 2))
        try await repository.save(first)
        try await repository.save(second)

        var completed = first
        completed.title = "İlk — güncel"
        completed.setStatus(.completed, at: Date(timeIntervalSince1970: 3))
        try await repository.save(completed)

        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded, [completed, second])
    }

    func testDeletePersistsAndMissingDeleteIsIdempotent() async throws {
        let kept = TaskItem(title: "Kalacak")
        let deleted = TaskItem(title: "Silinecek")
        try await repository.save(kept)
        try await repository.save(deleted)

        try await repository.delete(id: deleted.id)
        try await repository.delete(id: UUID())

        let restartedRepository = FileTaskRepository(rootURL: root)
        let loaded = try await restartedRepository.loadAll()
        XCTAssertEqual(loaded, [kept])
    }

    func testConcurrentSavesAreSerializedWithoutLosingTasks() async throws {
        let tasks = (0..<24).map { index in
            TaskItem(
                title: "Görev \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in tasks {
                group.addTask {
                    try await self.repository.save(task)
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await repository.loadAll()
        XCTAssertEqual(Set(loaded.map(\.id)), Set(tasks.map(\.id)))
        XCTAssertEqual(loaded.count, tasks.count)
    }

    func testCorruptStoreMovesToRecoveryWithoutDeletingBytes() async throws {
        try await repository.prepare()
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: root.appending(path: "Tasks/tasks.json"))

        do {
            _ = try await repository.loadAll()
            XCTFail("Bozuk görev dosyasının hata üretmesi bekleniyordu.")
        } catch let error as TaskRepositoryError {
            guard case .corruptStore(let recoveryURL) = error else {
                return XCTFail("Beklenmeyen hata: \(error)")
            }
            let recoveredURL = try XCTUnwrap(recoveryURL)
            XCTAssertEqual(try Data(contentsOf: recoveredURL), corruptData)
            XCTAssertTrue(recoveredURL.lastPathComponent.hasPrefix("Corrupt-Tasks-"))
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appending(path: "Tasks/tasks.json").path
        ))
    }

    func testUnsupportedSchemaIsPreservedInPlace() async throws {
        try await repository.prepare()
        let storeURL = root.appending(path: "Tasks/tasks.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 99,
            "tasks": []
        ])
        try data.write(to: storeURL)

        do {
            _ = try await repository.loadAll()
            XCTFail("Desteklenmeyen sürümün hata üretmesi bekleniyordu.")
        } catch let error as TaskRepositoryError {
            XCTAssertEqual(error, .unsupportedSchema(99))
        }

        XCTAssertEqual(try Data(contentsOf: storeURL), data)
    }

    func testSameTitleTasksKeepDistinctStableIdentifiers() async throws {
        let first = TaskItem(title: "Aynı görev")
        let second = TaskItem(title: "Aynı görev")

        try await repository.save(first)
        try await repository.save(second)

        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.map(\.title), ["Aynı görev", "Aynı görev"])
        XCTAssertEqual(Set(loaded.map(\.id)).count, 2)
    }

    func testTaskTitleNormalizationPreservesEmojiAndBoundsLongInput() {
        XCTAssertNil(TaskItem.normalizedTitle("  \n\t  "))
        XCTAssertEqual(TaskItem.normalizedTitle("  🚀 Özel & görev  "), "🚀 Özel & görev")

        let longTitle = String(repeating: "ğ", count: TaskItem.maximumTitleLength + 100)
        XCTAssertEqual(
            TaskItem.normalizedTitle(longTitle)?.count,
            TaskItem.maximumTitleLength
        )
    }

    func testRapidCompletionUpdatesPersistWithoutLosingTasks() async throws {
        let tasks = (0..<20).map { TaskItem(title: "Hızlı \($0)") }
        for task in tasks {
            try await repository.save(task)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, task) in tasks.enumerated() {
                group.addTask {
                    var completed = task
                    completed.setStatus(
                        .completed,
                        at: Date(timeIntervalSince1970: TimeInterval(index + 1))
                    )
                    try await self.repository.save(completed)
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, tasks.count)
        XCTAssertFalse(loaded.contains(where: \.isArchived))
        XCTAssertTrue(loaded.allSatisfy { $0.status == .completed })
    }

    func testVersionOneCompletionDocumentMigratesToTaskStatusAndArchiveTimestamp() async throws {
        try await repository.prepare()
        let taskID = UUID()
        let completedAt = Date(timeIntervalSince1970: 2_000)
        let legacyDocument: [String: Any] = [
            "schemaVersion": 1,
            "tasks": [[
                "id": taskID.uuidString,
                "title": "Eski tamamlanmış görev",
                "createdAt": 1_000.0,
                "completedAt": completedAt.timeIntervalSinceReferenceDate
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyDocument)
        try data.write(to: root.appending(path: "Tasks/tasks.json"))

        let loaded = try await repository.loadAll()

        let task = try XCTUnwrap(loaded.first)
        XCTAssertEqual(task.id, taskID)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.completedAt, completedAt)
        // Completed tasks are no longer archived implicitly.
        XCTAssertNil(task.archivedAt)

        let migratedData = try Data(contentsOf: root.appending(path: "Tasks/tasks.json"))
        let migratedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        XCTAssertEqual(migratedJSON["schemaVersion"] as? Int, 3)
    }
}
