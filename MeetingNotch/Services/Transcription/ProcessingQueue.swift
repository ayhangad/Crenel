import Foundation

actor ProcessingQueue {
    private let repository: any ProcessingJobRepository
    private var jobs: [ProcessingJob]?
    private var loadTask: Task<[ProcessingJob], Error>?

    init(repository: any ProcessingJobRepository = FileProcessingJobRepository()) {
        self.repository = repository
    }

    func restore(now: Date = Date()) async throws -> [ProcessingJob] {
        var restored = try await repository.loadAll()
        var changed = false

        for index in restored.indices where restored[index].state == .running {
            restored[index].state = .queued
            restored[index].updatedAt = now
            restored[index].nextAttemptAt = nil
            changed = true
        }

        jobs = restored
        if changed {
            try await repository.replaceAll(restored)
        }
        return sorted(restored)
    }

    @discardableResult
    func enqueue(
        meetingID: UUID,
        now: Date = Date()
    ) async throws -> ProcessingJob {
        var current = try await loadedJobs()
        if let existing = current.first(where: { $0.meetingID == meetingID }) {
            return existing
        }

        let job = ProcessingJob(meetingID: meetingID, createdAt: now)
        current.append(job)
        try await persist(current)
        return job
    }

    func allJobs() async throws -> [ProcessingJob] {
        sorted(try await loadedJobs())
    }

    func claimNext(now: Date = Date()) async throws -> ProcessingJob? {
        var current = try await loadedJobs()
        guard let index = current.indices
            .filter({ current[$0].state == .queued })
            .filter({ current[$0].nextAttemptAt.map { $0 <= now } ?? true })
            .min(by: { current[$0].createdAt < current[$1].createdAt }) else {
            return nil
        }

        current[index].state = .running
        current[index].attemptCount += 1
        current[index].updatedAt = now
        current[index].nextAttemptAt = nil
        try await persist(current)
        return current[index]
    }

    @discardableResult
    func markFailed(
        meetingID: UUID,
        error: TranscriptionServiceError,
        retryAt: Date? = nil,
        now: Date = Date()
    ) async throws -> ProcessingJob? {
        var current = try await loadedJobs()
        guard let index = current.firstIndex(where: { $0.meetingID == meetingID }) else {
            return nil
        }
        current[index].state = .failed
        current[index].lastFailure = .init(error)
        current[index].nextAttemptAt = retryAt
        current[index].updatedAt = now
        try await persist(current)
        return current[index]
    }

    @discardableResult
    func retry(meetingID: UUID, now: Date = Date()) async throws -> ProcessingJob? {
        var current = try await loadedJobs()
        guard let index = current.firstIndex(where: { $0.meetingID == meetingID }),
              current[index].state == .failed else {
            return nil
        }
        current[index].state = .queued
        current[index].lastFailure = nil
        current[index].nextAttemptAt = nil
        current[index].updatedAt = now
        try await persist(current)
        return current[index]
    }

    @discardableResult
    func retryFailed(
        failure: ProcessingJob.FailureKind,
        now: Date = Date()
    ) async throws -> [ProcessingJob] {
        var current = try await loadedJobs()
        let indices = current.indices.filter {
            current[$0].state == .failed
                && current[$0].lastFailure == failure
        }
        guard !indices.isEmpty else { return [] }

        for index in indices {
            current[index].state = .queued
            current[index].lastFailure = nil
            current[index].nextAttemptAt = nil
            current[index].updatedAt = now
        }
        try await persist(current)
        return sorted(indices.map { current[$0] })
    }

    func complete(meetingID: UUID) async throws {
        try await remove(meetingID: meetingID)
    }

    func remove(meetingID: UUID) async throws {
        var current = try await loadedJobs()
        let count = current.count
        current.removeAll { $0.meetingID == meetingID }
        guard current.count != count else { return }
        try await persist(current)
    }

    func removeAll() async throws {
        _ = try await loadedJobs()
        try await persist([])
    }

    private func loadedJobs() async throws -> [ProcessingJob] {
        if let jobs { return jobs }
        let task: Task<[ProcessingJob], Error>
        if let loadTask {
            task = loadTask
        } else {
            let repository = self.repository
            let newTask = Task { try await repository.loadAll() }
            loadTask = newTask
            task = newTask
        }
        do {
            let loaded = try await task.value
            if jobs == nil {
                jobs = loaded
            }
            loadTask = nil
            return jobs ?? loaded
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func persist(_ updated: [ProcessingJob]) async throws {
        let previous = jobs
        jobs = updated
        do {
            try await repository.replaceAll(updated)
        } catch {
            if jobs == updated {
                jobs = previous
            }
            throw error
        }
    }

    private func sorted(_ jobs: [ProcessingJob]) -> [ProcessingJob] {
        jobs.sorted { $0.createdAt < $1.createdAt }
    }
}
