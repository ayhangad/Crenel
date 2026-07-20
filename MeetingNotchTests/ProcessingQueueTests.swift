import XCTest
@testable import MeetingNotch

final class ProcessingQueueTests: XCTestCase {
    func testEnqueueIsIdempotentForMeeting() async throws {
        let repository = InMemoryProcessingJobRepository()
        let queue = ProcessingQueue(repository: repository)
        let meetingID = UUID()

        let first = try await queue.enqueue(meetingID: meetingID, providerID: .openAI)
        let second = try await queue.enqueue(meetingID: meetingID, providerID: .elevenLabs)
        let jobs = try await queue.allJobs()

        XCTAssertEqual(first, second)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.providerID, .openAI)
    }

    func testJobCanOnlyBeClaimedOnce() async throws {
        let repository = InMemoryProcessingJobRepository()
        let queue = ProcessingQueue(repository: repository)
        _ = try await queue.enqueue(meetingID: UUID(), providerID: .openAI)

        async let first = queue.claimNext()
        async let second = queue.claimNext()
        let claims = try await [first, second].compactMap { $0 }

        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(claims.first?.state, .running)
        XCTAssertEqual(claims.first?.attemptCount, 1)
    }

    func testRestoreRequeuesInterruptedRunningJob() async throws {
        let original = ProcessingJob(
            meetingID: UUID(),
            providerID: .openAI,
            state: .running,
            attemptCount: 1
        )
        let repository = InMemoryProcessingJobRepository(jobs: [original])
        let queue = ProcessingQueue(repository: repository)
        let restoredAt = Date(timeIntervalSince1970: 2_000)

        let restored = try await queue.restore(now: restoredAt)

        XCTAssertEqual(restored.first?.state, .queued)
        XCTAssertEqual(restored.first?.idempotencyKey, original.idempotencyKey)
        XCTAssertEqual(restored.first?.attemptCount, 1)
        XCTAssertEqual(restored.first?.updatedAt, restoredAt)
    }

    func testFailedJobCanBeRetriedWithoutChangingIdentity() async throws {
        let repository = InMemoryProcessingJobRepository()
        let queue = ProcessingQueue(repository: repository)
        let meetingID = UUID()
        let original = try await queue.enqueue(meetingID: meetingID, providerID: .elevenLabs)
        _ = try await queue.claimNext()
        let failed = try await queue.markFailed(
            meetingID: meetingID,
            error: .rateLimited(retryAfter: 10)
        )

        XCTAssertEqual(failed?.state, .failed)
        XCTAssertEqual(failed?.lastFailure, .rateLimited)

        let retried = try await queue.retry(meetingID: meetingID)
        XCTAssertEqual(retried?.state, .queued)
        XCTAssertNil(retried?.lastFailure)
        XCTAssertEqual(retried?.idempotencyKey, original.idempotencyKey)
    }

    func testRetryFailedOnlyRequeuesMatchingProviderAndFailureInOneWrite() async throws {
        let matchingFirst = ProcessingJob(
            meetingID: UUID(),
            providerID: .elevenLabs,
            state: .failed,
            attemptCount: 1,
            lastFailure: .authentication
        )
        let matchingSecond = ProcessingJob(
            meetingID: UUID(),
            providerID: .elevenLabs,
            state: .failed,
            attemptCount: 2,
            lastFailure: .authentication
        )
        let otherFailure = ProcessingJob(
            meetingID: UUID(),
            providerID: .elevenLabs,
            state: .failed,
            lastFailure: .timeout
        )
        let otherProvider = ProcessingJob(
            meetingID: UUID(),
            providerID: .openAI,
            state: .failed,
            lastFailure: .authentication
        )
        let repository = InMemoryProcessingJobRepository(jobs: [
            matchingFirst, matchingSecond, otherFailure, otherProvider
        ])
        let queue = ProcessingQueue(repository: repository)
        let retriedAt = Date(timeIntervalSince1970: 3_000)

        let retried = try await queue.retryFailed(
            providerID: .elevenLabs,
            failure: .authentication,
            now: retriedAt
        )

        XCTAssertEqual(Set(retried.map(\.id)), Set([matchingFirst.id, matchingSecond.id]))
        XCTAssertTrue(retried.allSatisfy { $0.state == .queued })
        XCTAssertTrue(retried.allSatisfy { $0.lastFailure == nil })
        XCTAssertTrue(retried.allSatisfy { $0.updatedAt == retriedAt })
        let untouched = try await queue.allJobs().filter { !retried.map(\.id).contains($0.id) }
        XCTAssertTrue(untouched.allSatisfy { $0.state == .failed })
    }

    func testRemoveAllClearsMemoryAndPersistentRepository() async throws {
        let repository = InMemoryProcessingJobRepository()
        let queue = ProcessingQueue(repository: repository)
        _ = try await queue.enqueue(meetingID: UUID(), providerID: .elevenLabs)
        _ = try await queue.enqueue(meetingID: UUID(), providerID: .openAI)

        try await queue.removeAll()

        let queueJobs = try await queue.allJobs()
        let repositoryJobs = await repository.loadAll()
        XCTAssertTrue(queueJobs.isEmpty)
        XCTAssertTrue(repositoryJobs.isEmpty)
    }

    func testFileRepositoryPersistsQueueAtomically() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileProcessingJobRepository(rootURL: root)
        let job = ProcessingJob(
            meetingID: UUID(),
            providerID: .openAI,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        try await repository.replaceAll([job])
        let reloaded = try await FileProcessingJobRepository(rootURL: root).loadAll()

        XCTAssertEqual(reloaded, [job])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appending(path: "ProcessingQueue/queue.json").path
            )
        )
    }

    func testCorruptQueueIsPreservedInRecovery() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = AppStorageLayout(root: root)
        try layout.createDirectories()
        try Data("not-json".utf8).write(
            to: layout.processingQueue.appending(path: "queue.json"),
            options: .atomic
        )
        let repository = FileProcessingJobRepository(rootURL: root)

        do {
            _ = try await repository.loadAll()
            XCTFail("Bozuk kuyruk hata vermeliydi.")
        } catch {
            XCTAssertEqual(error as? ProcessingJobRepositoryError, .corruptStore)
        }

        let recoveryItems = try FileManager.default.contentsOfDirectory(
            at: layout.recovery,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(recoveryItems.count, 1)
        XCTAssertTrue(recoveryItems[0].lastPathComponent.hasPrefix("Corrupt-ProcessingQueue-"))
    }

    @MainActor
    func testAppStateShowsQueuedAndFailedJobsAfterReload() {
        let queuedMeeting = makeMeeting(id: UUID())
        let failedMeeting = makeMeeting(id: UUID())
        let state = AppState()
        state.replaceStoredMeetings([queuedMeeting, failedMeeting])
        state.replaceProcessingJobs([
            ProcessingJob(meetingID: queuedMeeting.id, providerID: .openAI),
            ProcessingJob(
                meetingID: failedMeeting.id,
                providerID: .openAI,
                state: .failed,
                lastFailure: .timeout
            )
        ])

        XCTAssertEqual(
            state.storedMeetings.first(where: { $0.id == queuedMeeting.id })?.processingStatus,
            .processing
        )
        XCTAssertEqual(
            state.storedMeetings.first(where: { $0.id == failedMeeting.id })?.processingStatus,
            .failed
        )
    }

    private func makeMeeting(id: UUID) -> StoredMeeting {
        StoredMeeting(
            id: id,
            title: "Test",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            sourceMeeting: nil,
            audioFileName: "recording.m4a"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MeetingNotch-QueueTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor InMemoryProcessingJobRepository: ProcessingJobRepository {
    private var jobs: [ProcessingJob]

    init(jobs: [ProcessingJob] = []) {
        self.jobs = jobs
    }

    func prepare() {}

    func loadAll() -> [ProcessingJob] {
        jobs
    }

    func replaceAll(_ jobs: [ProcessingJob]) {
        self.jobs = jobs
    }
}
