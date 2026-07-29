import Foundation

@MainActor
final class AppState: ObservableObject {
    enum PanelTab: String, CaseIterable, Identifiable {
        case meetings = "Toplantılar"
        case tasks = "Görevler"

        var id: Self { self }
    }

    @Published var selectedTab: PanelTab = .meetings
    @Published private(set) var isNotchPinned = false
    @Published private(set) var notchPanelAvailableSize = CGSize(width: 1_024, height: 768)
    @Published private(set) var meetingFlow: MeetingFlowState
    @Published private(set) var activeTaskCount = 0
    @Published private(set) var userFacingFailure: AppFailure?
    @Published private(set) var calendarAccessState: CalendarAccessState = .notDetermined
    @Published private(set) var audioCapturePermissions = AudioCapturePermissionSnapshot(
        microphone: .notDetermined,
        systemAudio: .notDetermined
    )
    @Published private(set) var nextMeeting: Meeting?
    @Published private(set) var meetingReminderLevel: MeetingReminderLevel = .none
    @Published private(set) var secondsUntilMeeting: TimeInterval?
    @Published private(set) var recordingCaptureStatus = RecordingCaptureStatus.idle
    @Published private(set) var availableMicrophones: [MicrophoneDevice] = []
    @Published private(set) var selectedMicrophoneID: String?
    @Published private(set) var lastRecordingResult: RecordingCaptureResult?
    @Published private(set) var storedMeetings: [StoredMeeting] = []
    @Published private(set) var lastStoredMeeting: StoredMeeting?
    @Published private(set) var recordingRecoverySummary: RecordingRecoverySummary?
    @Published private(set) var processingJobs: [ProcessingJob] = []
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var presentedMeetingDetail: MeetingDetailContent?

    private var flowMachine: MeetingFlowMachine
    private var suppressedReminderKey: String?

    init(initialFlow: MeetingFlowState = .idle) {
        let flowMachine = MeetingFlowMachine(initialState: initialFlow)
        self.flowMachine = flowMachine
        self.meetingFlow = flowMachine.state

        if case .failed(let failure) = initialFlow {
            userFacingFailure = failure
        }
    }

    @discardableResult
    func send(_ event: MeetingFlowEvent) -> Bool {
        let previousPhase = meetingFlow.phase

        do {
            try flowMachine.send(event)
            meetingFlow = flowMachine.state
            syncFailureFromFlow()
            AppLogger.transitioned(from: previousPhase, to: meetingFlow.phase)
            return true
        } catch let error as InvalidMeetingFlowTransition {
            AppLogger.rejected(eventName: error.eventName, phase: error.phase)
            return false
        } catch {
            return false
        }
    }

    @discardableResult
    func prepareForRecording() -> Bool {
        send(.requestedRecording)
    }

    @discardableResult
    func stopRecording() -> Bool {
        send(.requestedStop)
    }

    func recordingStarted(_ session: RecordingSession) {
        send(.recordingStarted(at: session.startedAt))
    }

    func recordingSaved(_ result: RecordingCaptureResult, storedMeeting: StoredMeeting? = nil) {
        lastRecordingResult = result
        if let storedMeeting {
            lastStoredMeeting = storedMeeting
            storedMeetings.removeAll { $0.id == storedMeeting.id }
            storedMeetings.insert(storedMeeting, at: 0)
        }
        recordingCaptureStatus = .idle
        send(.localRecordingSaved(sessionID: result.session.id))
    }

    func replaceStoredMeetings(_ meetings: [StoredMeeting]) {
        storedMeetings = meetings.sorted { $0.startedAt > $1.startedAt }
        applyProcessingStatuses()
    }

    func removeStoredMeeting(id: UUID) {
        storedMeetings.removeAll { $0.id == id }
        processingJobs.removeAll { $0.meetingID == id }
        if lastStoredMeeting?.id == id {
            lastStoredMeeting = nil
        }
        if presentedMeetingDetail?.id == id {
            presentedMeetingDetail = nil
        }
    }

    func presentMeetingDetail(_ content: MeetingDetailContent) {
        selectedTab = .meetings
        presentedMeetingDetail = content
    }

    func dismissMeetingDetail() {
        presentedMeetingDetail = nil
    }

    func replaceProcessingJobs(_ jobs: [ProcessingJob]) {
        processingJobs = jobs.sorted { $0.createdAt < $1.createdAt }
        applyProcessingStatuses()
    }

    func upsertProcessingJob(_ job: ProcessingJob) {
        processingJobs.removeAll { $0.meetingID == job.meetingID }
        processingJobs.append(job)
        processingJobs.sort { $0.createdAt < $1.createdAt }
        applyProcessingStatuses()
    }

    func processingStarted(_ job: ProcessingJob) {
        upsertProcessingJob(job)
        send(.processingStarted)
    }

    func processingBeganTranscribing() {
        guard case .uploading = meetingFlow else { return }
        send(.uploadCompleted)
    }

    func processingBeganSummarizing() {
        if case .uploading = meetingFlow {
            send(.uploadCompleted)
        }
        guard case .transcribing = meetingFlow else { return }
        send(.transcriptionCompleted)
    }

    func processingCompleted(_ meeting: StoredMeeting) {
        processingJobs.removeAll { $0.meetingID == meeting.id }
        storedMeetings.removeAll { $0.id == meeting.id }
        storedMeetings.append(meeting)
        storedMeetings.sort { $0.startedAt > $1.startedAt }
        if lastStoredMeeting?.id == meeting.id {
            lastStoredMeeting = meeting
        }

        if case .uploading = meetingFlow {
            send(.uploadCompleted)
        }
        if case .transcribing = meetingFlow {
            send(.transcriptionCompleted)
        }
        if case .summarizing = meetingFlow {
            send(.summaryCompleted(meetingID: meeting.id))
        }
    }

    func processingFailed(_ job: ProcessingJob, error: TranscriptionServiceError) {
        upsertProcessingJob(job)
        switch meetingFlow {
        case .uploading, .transcribing, .summarizing:
            send(.fail(error.appFailure))
        default:
            break
        }
    }

    func applyRecordingRecoveryReport(_ report: RecordingRecoveryReport) {
        recordingRecoverySummary = report.hasResults ? RecordingRecoverySummary(report: report) : nil
    }

    func dismissRecordingRecoverySummary() {
        recordingRecoverySummary = nil
    }

    func selectPanelTab(offset: Int) {
        let tabs = PanelTab.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedTab), !tabs.isEmpty else { return }
        let destination = (currentIndex + offset % tabs.count + tabs.count) % tabs.count
        selectedTab = tabs[destination]
    }

    func updateNotchPanelAvailableSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        notchPanelAvailableSize = size
    }

    @discardableResult
    func toggleNotchPin() -> Bool {
        isNotchPinned.toggle()
        return isNotchPinned
    }

    func recordingFailed(_ failure: AppFailure) {
        recordingCaptureStatus = .idle
        send(.fail(failure))
    }

    func updateRecordingCaptureStatus(_ status: RecordingCaptureStatus) {
        recordingCaptureStatus = status
    }

    func updateAvailableMicrophones(_ devices: [MicrophoneDevice]) {
        availableMicrophones = devices
    }

    func updateSelectedMicrophoneID(_ deviceID: String?) {
        selectedMicrophoneID = deviceID
    }

    func updateTranscriptionUploadProgress(_ progress: Double) {
        send(.uploadProgress(progress))
    }

    func cancelCurrentFlow() {
        recordingCaptureStatus = .idle
        send(.cancel)
    }

    func recoverFromFailure() {
        guard let failure = userFacingFailure else { return }
        send(failure.isRetryable ? .retry : .reset)
    }

    func resetFlow() {
        send(.reset)
    }

    func updateCalendarAccessState(_ state: CalendarAccessState) {
        calendarAccessState = state
    }

    func updateAudioCapturePermissions(_ permissions: AudioCapturePermissionSnapshot) {
        audioCapturePermissions = permissions
    }

    func replaceTasks(_ tasks: [TaskItem]) {
        self.tasks = tasks
        refreshTaskCount()
    }

    func upsertTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        refreshTaskCount()
    }

    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        refreshTaskCount()
    }

    func resetPersistedContent() {
        storedMeetings = []
        lastStoredMeeting = nil
        lastRecordingResult = nil
        processingJobs = []
        tasks = []
        recordingRecoverySummary = nil
        presentedMeetingDetail = nil
        refreshTaskCount()
        if !meetingFlow.requiresTerminationConfirmation {
            send(.reset)
        }
    }

    var activeTasks: [TaskItem] {
        tasks
            .filter { !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var archivedTasks: [TaskItem] {
        tasks
            .filter(\.isArchived)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var completedMeeting: StoredMeeting? {
        guard case .completed(let meetingID) = meetingFlow else { return nil }
        return storedMeetings.first { $0.id == meetingID }
    }

    @discardableResult
    func applyMeetingSnapshot(
        _ snapshot: MeetingReminderSnapshot,
        shouldPresent: Bool
    ) -> Bool {
        nextMeeting = snapshot.nextMeeting
        meetingReminderLevel = snapshot.level
        secondsUntilMeeting = snapshot.secondsUntilStart

        guard let meeting = snapshot.nextMeeting, snapshot.level != .none else {
            if case .upcomingMeeting = meetingFlow {
                send(.dismissedUpcomingMeeting)
            }
            suppressedReminderKey = nil
            return false
        }

        guard snapshot.presentationKey != suppressedReminderKey else {
            return false
        }

        switch meetingFlow {
        case .idle, .upcomingMeeting:
            send(.detectedUpcomingMeeting(meeting))
            return shouldPresent
        default:
            return false
        }
    }

    func dismissCurrentMeetingReminder() {
        let snapshot = MeetingReminderSnapshot(
            nextMeeting: nextMeeting,
            level: meetingReminderLevel,
            secondsUntilStart: secondsUntilMeeting
        )
        suppressedReminderKey = snapshot.presentationKey
        send(.dismissedUpcomingMeeting)
    }

    var requiresTerminationConfirmation: Bool {
        meetingFlow.requiresTerminationConfirmation
    }

    private func syncFailureFromFlow() {
        if case .failed(let failure) = meetingFlow {
            userFacingFailure = failure
        } else {
            userFacingFailure = nil
        }
    }

    private func applyProcessingStatuses() {
        let jobsByMeetingID = Dictionary(
            processingJobs.map { ($0.meetingID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in storedMeetings.indices {
            guard let job = jobsByMeetingID[storedMeetings[index].id] else { continue }
            storedMeetings[index].processingStatus = job.state == .failed ? .failed : .processing
        }
        if let lastStoredMeeting,
           let updated = storedMeetings.first(where: { $0.id == lastStoredMeeting.id }) {
            self.lastStoredMeeting = updated
        }
        if let detail = presentedMeetingDetail,
           let updated = storedMeetings.first(where: { $0.id == detail.id }) {
            presentedMeetingDetail = MeetingDetailContent(
                meeting: updated,
                storedTranscription: detail.storedTranscription,
                markdown: detail.markdown,
                audioURL: detail.audioURL
            )
        }
    }

    private func refreshTaskCount() {
        activeTaskCount = tasks.lazy.filter { !$0.isArchived }.count
    }
}
