import XCTest
@testable import MeetingNotch

final class NotchPresentationTests: XCTestCase {
    func testRecordingOutranksMeetingAndTasks() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))

        let status = NotchStatusResolver.compactStatus(
            flow: .recording(startedAt: startedAt),
            nextMeeting: meeting,
            activeTaskCount: 4
        )

        XCTAssertEqual(status, .recording(startedAt: startedAt))
    }

    func testEveryProcessingPhaseOutranksMeetingAndTasks() {
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))
        let cases: [(MeetingFlowState, NotchCompactStatus)] = [
            (.preparingRecording, .processing(.preparing)),
            (.finalizingAudio, .processing(.finalizing)),
            (.uploading(progress: 0.42), .processing(.uploading(progress: 0.42))),
            (.transcribing, .processing(.transcribing)),
            (.summarizing, .processing(.summarizing))
        ]

        for (flow, expected) in cases {
            XCTAssertEqual(
                NotchStatusResolver.compactStatus(
                    flow: flow,
                    nextMeeting: meeting,
                    activeTaskCount: 4
                ),
                expected
            )
        }
    }

    func testFailureAndCompletionOutrankMeetingAndTasks() {
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .failed(.network("Bağlantı yok")),
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .failed
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .completed(meetingID: UUID()),
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .completed
        )
    }

    func testMeetingOutranksTasksAndTasksOutrankIdle() {
        let startDate = Date(timeIntervalSince1970: 200)
        let meeting = makeMeeting(startDate: startDate)

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .upcoming(startDate: startDate)
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: nil,
                activeTaskCount: 4
            ),
            .tasks(count: 4)
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: nil,
                activeTaskCount: 0
            ),
            .idle
        )
    }

    func testPanelUsesPreferredSizeOnLargeScreenAndStaysWithinSmallScreen() {
        XCTAssertEqual(
            NotchPanelLayout(availableSize: CGSize(width: 1_440, height: 900)),
            NotchPanelLayout(width: 420, maximumContentHeight: 500)
        )

        let constrained = NotchPanelLayout(availableSize: CGSize(width: 360, height: 500))
        XCTAssertEqual(constrained.width, 328)
        XCTAssertEqual(constrained.maximumContentHeight, 350)
        XCTAssertLessThanOrEqual(constrained.width + 32, 360)
        XCTAssertLessThanOrEqual(constrained.maximumContentHeight + 150, 500)
    }

    func testOnlyCompletionResetsAfterTransientPresentation() {
        let completed = MeetingFlowState.completed(meetingID: UUID())
        let failed = MeetingFlowState.failed(.network("Bağlantı yok"))

        XCTAssertTrue(NotchTransientStatusPolicy.shouldPresent(completed))
        XCTAssertTrue(NotchTransientStatusPolicy.shouldResetAfterTimeout(completed))
        XCTAssertTrue(NotchTransientStatusPolicy.shouldPresent(failed))
        XCTAssertFalse(NotchTransientStatusPolicy.shouldResetAfterTimeout(failed))
        XCTAssertFalse(NotchTransientStatusPolicy.shouldPresent(.transcribing))
    }

    func testReducedMotionProfileRemovesPerceptibleTransitionDurations() {
        let standard = NotchMotionProfile.resolved(reducesMotion: false)
        let reduced = NotchMotionProfile.resolved(reducesMotion: true)

        XCTAssertEqual(standard.openingDuration, 0.28)
        XCTAssertEqual(standard.closingDuration, 0.2)
        XCTAssertEqual(standard.conversionDuration, 0.3)
        XCTAssertTrue(reduced.reducesMotion)
        XCTAssertLessThanOrEqual(reduced.openingDuration, 0.01)
        XCTAssertLessThanOrEqual(reduced.closingDuration, 0.01)
        XCTAssertLessThanOrEqual(reduced.conversionDuration, 0.01)
    }

    private func makeMeeting(startDate: Date) -> Meeting {
        Meeting(
            title: "Planlama",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            externalIdentifier: "planlama"
        )
    }
}
