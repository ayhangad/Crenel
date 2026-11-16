import XCTest
@testable import MeetingNotch

@MainActor
final class AppStateTests: XCTestCase {
    func testAudioCapturePermissionsAreUpdatedForTheUI() {
        let state = AppState()
        let permissions = AudioCapturePermissionSnapshot(
            microphone: .authorized,
            systemAudio: .denied
        )

        state.updateAudioCapturePermissions(permissions)

        XCTAssertEqual(state.audioCapturePermissions, permissions)
    }

    func testMicrophoneDevicesAndSelectionArePublishedForSettings() {
        let state = AppState()
        let device = MicrophoneDevice(id: "usb", name: "USB Mikrofon", isSystemDefault: false)

        state.updateAvailableMicrophones([device])
        state.updateSelectedMicrophoneID(device.id)

        XCTAssertEqual(state.availableMicrophones, [device])
        XCTAssertEqual(state.selectedMicrophoneID, device.id)
    }

    func testNotchPinCanBeToggled() {
        let state = AppState()

        XCTAssertTrue(state.toggleNotchPin())
        XCTAssertTrue(state.isNotchPinned)
        XCTAssertFalse(state.toggleNotchPin())
        XCTAssertFalse(state.isNotchPinned)
    }

    func testPanelTabsCanBeSelectedCyclicallyFromKeyboardCommands() {
        let state = AppState()

        state.selectPanelTab(offset: 1)
        XCTAssertEqual(state.selectedTab, .tasks)

        state.selectPanelTab(offset: 1)
        XCTAssertEqual(state.selectedTab, .meetings)

        state.selectPanelTab(offset: -1)
        XCTAssertEqual(state.selectedTab, .tasks)
    }

    func testPanelAvailableSizeRejectsInvalidValues() {
        let state = AppState()
        let original = state.notchPanelAvailableSize

        state.updateNotchPanelAvailableSize(CGSize(width: 0, height: 500))
        XCTAssertEqual(state.notchPanelAvailableSize, original)

        state.updateNotchPanelAvailableSize(CGSize(width: 800, height: 600))
        XCTAssertEqual(state.notchPanelAvailableSize, CGSize(width: 800, height: 600))
    }

    func testNotchPresentationPublishesPhysicalNotchAppearanceWithAvailableSize() {
        let state = AppState()

        state.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )

        XCTAssertEqual(state.notchPanelAvailableSize, CGSize(width: 1_440, height: 900))
        XCTAssertTrue(state.notchPanelHasPhysicalNotch)

        state.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_920, height: 1_080),
            hasPhysicalNotch: false
        )

        XCTAssertEqual(state.notchPanelAvailableSize, CGSize(width: 1_920, height: 1_080))
        XCTAssertFalse(state.notchPanelHasPhysicalNotch)
    }

    func testMeetingDetailDrillsDownInsideMeetingsTabAndClosesWhenMeetingIsRemoved() {
        let state = AppState()
        let meeting = StoredMeeting(
            id: UUID(),
            title: "Planlama",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            sourceMeeting: nil,
            audioFileName: "meeting.m4a"
        )
        let content = MeetingDetailContent(
            meeting: meeting,
            storedTranscription: nil,
            markdown: nil,
            audioURL: URL(fileURLWithPath: "/tmp/meeting.m4a")
        )
        state.selectedTab = .tasks

        state.presentMeetingDetail(content)

        XCTAssertEqual(state.selectedTab, .meetings)
        XCTAssertEqual(state.presentedMeetingDetail?.id, meeting.id)

        state.removeStoredMeeting(id: meeting.id)

        XCTAssertNil(state.presentedMeetingDetail)
    }

    func testRecordingPreparationStartsOnlyFromIdle() {
        let state = AppState()

        state.prepareForRecording()
        XCTAssertEqual(state.meetingFlow, .preparingRecording)

        state.prepareForRecording()
        XCTAssertEqual(state.meetingFlow, .preparingRecording)
    }

    func testCancellationAndResetReturnToIdle() {
        let state = AppState()
        state.prepareForRecording()

        state.cancelCurrentFlow()
        XCTAssertEqual(state.meetingFlow, .cancelled)

        state.resetFlow()
        XCTAssertEqual(state.meetingFlow, .idle)
    }

    func testFailureIsExposedForTheUI() {
        let state = AppState()
        let failure = AppFailure.network("İnternet bağlantınızı kontrol edin.")
        state.prepareForRecording()

        XCTAssertTrue(state.send(.fail(failure)))
        XCTAssertEqual(state.userFacingFailure, failure)
        XCTAssertEqual(state.meetingFlow, .failed(failure))
    }

    func testActiveFlowRequiresTerminationConfirmation() {
        let state = AppState()
        XCTAssertFalse(state.requiresTerminationConfirmation)

        state.prepareForRecording()
        XCTAssertTrue(state.requiresTerminationConfirmation)
    }

    func testMeetingReminderBecomesPrimaryFlowAndCanBeDismissed() {
        let state = AppState()
        let meeting = Meeting(
            title: "Daily",
            startDate: Date().addingTimeInterval(60),
            endDate: Date().addingTimeInterval(1_860),
            externalIdentifier: "daily"
        )
        let snapshot = MeetingReminderSnapshot(
            nextMeeting: meeting,
            level: .oneMinute,
            secondsUntilStart: 60
        )

        XCTAssertTrue(state.applyMeetingSnapshot(snapshot, shouldPresent: true))
        XCTAssertEqual(state.meetingFlow, .upcomingMeeting(meeting))

        state.dismissCurrentMeetingReminder()
        XCTAssertEqual(state.meetingFlow, .idle)
        XCTAssertFalse(state.applyMeetingSnapshot(snapshot, shouldPresent: true))
        XCTAssertEqual(state.meetingFlow, .idle)
    }

    func testCalendarWithoutReminderKeepsManualRecordingAvailable() {
        let state = AppState()
        state.updateCalendarAccessState(.denied)

        state.prepareForRecording()

        XCTAssertEqual(state.calendarAccessState, .denied)
        XCTAssertEqual(state.meetingFlow, .preparingRecording)
    }

    func testCalendarHealthAndUpcomingMeetingsArePublishedInStableOrder() {
        let state = AppState()
        let later = Meeting(
            title: "Sonra",
            startDate: Date(timeIntervalSince1970: 200),
            endDate: Date(timeIntervalSince1970: 300)
        )
        let earlier = Meeting(
            title: "Önce",
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200)
        )
        let snapshot = CalendarIntegrationSnapshot(
            sources: [CalendarSourceSummary(kind: .google, calendarCount: 2)],
            scannedEventCount: 4,
            matchedMeetingCount: 2,
            refreshedAt: Date(timeIntervalSince1970: 50)
        )

        state.updateCalendarIntegrationSnapshot(snapshot)
        state.updateCalendarRefreshState(isRefreshing: true)
        state.updateUpcomingMeetings([later, earlier])

        XCTAssertEqual(state.calendarIntegrationSnapshot, snapshot)
        XCTAssertTrue(state.isCalendarRefreshing)
        XCTAssertEqual(state.upcomingMeetings.map(\.title), ["Önce", "Sonra"])
    }

    func testJoinURLResolvesTheSelectedUpcomingMeetingInsteadOfAlwaysTheFirst() {
        let firstURL = URL(string: "https://meet.google.com/first-room")!
        let secondURL = URL(string: "https://meet.google.com/second-room")!
        let first = Meeting(
            title: "İlk",
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200),
            meetingURL: firstURL
        )
        let second = Meeting(
            title: "İkinci",
            startDate: Date(timeIntervalSince1970: 200),
            endDate: Date(timeIntervalSince1970: 300),
            meetingURL: secondURL
        )
        let state = AppState()
        state.updateUpcomingMeetings([first, second])

        XCTAssertEqual(state.upcomingMeeting(matching: secondURL), second)
        XCTAssertNil(state.upcomingMeeting(matching: URL(string: "https://example.com")!))
    }

    func testLocallySavedRecordingCompletesFlow() {
        let state = AppState()
        let session = RecordingSession(startedAt: .now)
        let result = RecordingCaptureResult(session: session, tracks: [])

        state.prepareForRecording()
        state.recordingStarted(session)
        state.stopRecording()
        state.recordingSaved(result)

        XCTAssertEqual(state.meetingFlow, .completed(meetingID: session.id))
        XCTAssertEqual(state.lastRecordingResult, result)
    }

    func testSafetyInterruptionAtomicallyWarnsAndMovesRecordingToFinalizing() {
        let state = AppState()
        let session = RecordingSession(startedAt: .now)
        state.prepareForRecording()
        state.recordingStarted(session)

        XCTAssertTrue(state.stopRecordingForSafety(message: "Disk kritik"))

        XCTAssertEqual(state.meetingFlow.phase, .finalizingAudio)
        XCTAssertEqual(state.recordingSafetyMessage, "Disk kritik")
        XCTAssertEqual(state.selectedTab, .meetings)
        XCTAssertFalse(state.stopRecordingForSafety(message: "İkinci uyarı"))
        XCTAssertEqual(state.recordingSafetyMessage, "Disk kritik")
    }

    func testCompletedMeetingResolvesByFlowIdentifier() {
        let state = AppState()
        let session = RecordingSession(startedAt: .now)
        let result = RecordingCaptureResult(session: session, tracks: [])
        let expected = StoredMeeting(
            id: session.id,
            title: "Doğru toplantı",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(60),
            sourceMeeting: nil,
            audioFileName: "audio.m4a"
        )
        let other = StoredMeeting(
            id: UUID(),
            title: "Başka toplantı",
            startedAt: session.startedAt.addingTimeInterval(120),
            endedAt: session.startedAt.addingTimeInterval(180),
            sourceMeeting: nil,
            audioFileName: "other.m4a"
        )

        state.replaceStoredMeetings([other])
        state.prepareForRecording()
        state.recordingStarted(session)
        state.stopRecording()
        state.recordingSaved(result, storedMeeting: expected)

        XCTAssertEqual(state.completedMeeting, expected)
    }

    func testTaskCollectionsAndCompactCountStayInSync() {
        let state = AppState()
        let first = TaskItem(title: "İlk", createdAt: Date(timeIntervalSince1970: 1))
        let second = TaskItem(title: "İkinci", createdAt: Date(timeIntervalSince1970: 2))

        state.replaceTasks([second, first])

        XCTAssertEqual(state.activeTasks.map(\.id), [first.id, second.id])
        XCTAssertEqual(state.activeTaskCount, 2)

        var completed = first
        completed.setStatus(.completed, at: Date(timeIntervalSince1970: 3))
        state.upsertTask(completed)

        XCTAssertEqual(state.activeTasks.map(\.id), [second.id])
        // Completing does not archive: the task stays visible until the day ends.
        XCTAssertFalse(completed.isArchived)
        XCTAssertEqual(state.activeTaskCount, 1)

        state.removeTask(id: second.id)
        XCTAssertEqual(state.activeTaskCount, 0)
    }

    func testResetPersistedContentClearsMeetingTaskAndQueueState() {
        let state = AppState()
        let meetingID = UUID()
        state.replaceStoredMeetings([
            StoredMeeting(
                id: meetingID,
                title: "Silinecek",
                startedAt: Date(timeIntervalSince1970: 1),
                endedAt: Date(timeIntervalSince1970: 2),
                sourceMeeting: nil,
                audioFileName: "audio.m4a"
            )
        ])
        state.replaceProcessingJobs([
            ProcessingJob(meetingID: meetingID)
        ])
        state.replaceTasks([TaskItem(title: "Silinecek görev")])

        state.resetPersistedContent()

        XCTAssertTrue(state.storedMeetings.isEmpty)
        XCTAssertTrue(state.processingJobs.isEmpty)
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertEqual(state.activeTaskCount, 0)
    }

    func testBrowserAudioConnectionStatusIsPublishedForVisibleFallbackUI() {
        let state = AppState()

        XCTAssertEqual(state.browserAudioConnectionStatus, .unavailable)
        state.updateBrowserAudioConnectionStatus(.waitingForMeetTab)
        XCTAssertEqual(state.browserAudioConnectionStatus, .waitingForMeetTab)
        state.updateBrowserAudioConnectionStatus(.tabConnected)
        XCTAssertEqual(state.browserAudioConnectionStatus, .tabConnected)
        state.updateBrowserAudioConnectionStatus(.recording)
        XCTAssertEqual(state.browserAudioConnectionStatus, .recording)
    }
}
