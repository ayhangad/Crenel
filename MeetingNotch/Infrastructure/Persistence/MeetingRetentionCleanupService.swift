import Foundation

struct MeetingRetentionCleanupReport: Equatable, Sendable {
    let inspectedCount: Int
    let expiredMeetingIDs: [UUID]
    let deletedMeetingIDs: [UUID]
    let failedMeetingIDs: [UUID]

    static let disabled = MeetingRetentionCleanupReport(
        inspectedCount: 0,
        expiredMeetingIDs: [],
        deletedMeetingIDs: [],
        failedMeetingIDs: []
    )
}

struct MeetingRetentionCleanupService: Sendable {
    private let repository: any MeetingRetentionRepository

    init(repository: any MeetingRetentionRepository) {
        self.repository = repository
    }

    func cleanup(
        policy: MeetingRetentionPolicy,
        now: Date = .now
    ) async throws -> MeetingRetentionCleanupReport {
        guard let cutoffDate = policy.cutoffDate(relativeTo: now) else {
            return .disabled
        }

        let meetings = try await repository.loadAll()
        let expiredMeetings = meetings
            .filter { $0.endedAt <= cutoffDate }
            .sorted { $0.endedAt < $1.endedAt }
        var deletedMeetingIDs: [UUID] = []
        var failedMeetingIDs: [UUID] = []

        for meeting in expiredMeetings {
            do {
                try Task.checkCancellation()
                try await repository.delete(id: meeting.id)
                deletedMeetingIDs.append(meeting.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedMeetingIDs.append(meeting.id)
            }
        }

        return MeetingRetentionCleanupReport(
            inspectedCount: meetings.count,
            expiredMeetingIDs: expiredMeetings.map(\.id),
            deletedMeetingIDs: deletedMeetingIDs,
            failedMeetingIDs: failedMeetingIDs
        )
    }
}
