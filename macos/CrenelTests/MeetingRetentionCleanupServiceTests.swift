import Foundation
import XCTest
@testable import Crenel

final class MeetingRetentionCleanupServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testKeepForeverDoesNotLoadOrDeleteMeetings() async throws {
        let repository = RetentionMeetingRepository(meetings: [makeMeeting(ageInDays: 100)])
        let service = MeetingRetentionCleanupService(repository: repository)

        let report = try await service.cleanup(policy: .keepForever, now: now)
        let loadCount = await repository.loadCount
        let deletedIDs = await repository.deletedIDs

        XCTAssertEqual(report, .disabled)
        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(deletedIDs.isEmpty)
    }

    func testDeletesOnlyMeetingsAtOrBeyondSelectedAge() async throws {
        let recent = makeMeeting(ageInDays: 29)
        let boundary = makeMeeting(ageInDays: 30)
        let expired = makeMeeting(ageInDays: 45)
        let repository = RetentionMeetingRepository(meetings: [recent, boundary, expired])
        let service = MeetingRetentionCleanupService(repository: repository)
        let policy = try XCTUnwrap(MeetingRetentionPolicy(deletingAfterDays: 30))

        let report = try await service.cleanup(policy: policy, now: now)
        let remainingIDs = await repository.remainingIDs

        XCTAssertEqual(report.inspectedCount, 3)
        XCTAssertEqual(report.expiredMeetingIDs, [expired.id, boundary.id])
        XCTAssertEqual(report.deletedMeetingIDs, [expired.id, boundary.id])
        XCTAssertTrue(report.failedMeetingIDs.isEmpty)
        XCTAssertEqual(remainingIDs, Set([recent.id]))
    }

    func testDeletionFailureDoesNotPreventOtherExpiredMeetingsFromCleaning() async throws {
        let first = makeMeeting(ageInDays: 60)
        let failing = makeMeeting(ageInDays: 45)
        let last = makeMeeting(ageInDays: 31)
        let repository = RetentionMeetingRepository(
            meetings: [first, failing, last],
            failingIDs: [failing.id]
        )
        let service = MeetingRetentionCleanupService(repository: repository)
        let policy = try XCTUnwrap(MeetingRetentionPolicy(deletingAfterDays: 30))

        let report = try await service.cleanup(policy: policy, now: now)
        let remainingIDs = await repository.remainingIDs

        XCTAssertEqual(report.deletedMeetingIDs, [first.id, last.id])
        XCTAssertEqual(report.failedMeetingIDs, [failing.id])
        XCTAssertEqual(remainingIDs, Set([failing.id]))
    }

    func testPolicyRejectsNonPositiveDaysAndInvalidPersistedValue() throws {
        XCTAssertNil(MeetingRetentionPolicy(deletingAfterDays: 0))
        XCTAssertNil(MeetingRetentionPolicy(deletingAfterDays: -1))

        let invalidData = Data(#"{"days":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MeetingRetentionPolicy.self, from: invalidData))
    }

    func testPolicyRoundTripsSelectedDaysAndKeepForever() throws {
        let policies = [
            MeetingRetentionPolicy.keepForever,
            try XCTUnwrap(MeetingRetentionPolicy(deletingAfterDays: 90))
        ]

        for policy in policies {
            let data = try JSONEncoder().encode(policy)
            XCTAssertEqual(try JSONDecoder().decode(MeetingRetentionPolicy.self, from: data), policy)
        }
    }

    private func makeMeeting(ageInDays: Int) -> StoredMeeting {
        let endedAt = now.addingTimeInterval(-TimeInterval(ageInDays) * 24 * 60 * 60)
        return StoredMeeting(
            id: UUID(),
            title: "Meeting \(ageInDays)",
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            sourceMeeting: nil,
            audioFileName: "recording.m4a"
        )
    }
}

private actor RetentionMeetingRepository: MeetingRetentionRepository {
    private var meetings: [StoredMeeting]
    private let failingIDs: Set<UUID>
    private(set) var loadCount = 0
    private(set) var deletedIDs: [UUID] = []

    init(meetings: [StoredMeeting], failingIDs: Set<UUID> = []) {
        self.meetings = meetings
        self.failingIDs = failingIDs
    }

    var remainingIDs: Set<UUID> {
        Set(meetings.map(\.id))
    }

    func loadAll() throws -> [StoredMeeting] {
        loadCount += 1
        return meetings
    }

    func delete(id: UUID) throws {
        if failingIDs.contains(id) {
            throw TestFailure.deleteFailed
        }
        meetings.removeAll { $0.id == id }
        deletedIDs.append(id)
    }

    private enum TestFailure: Error {
        case deleteFailed
    }
}
