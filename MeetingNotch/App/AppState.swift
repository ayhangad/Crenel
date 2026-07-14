import Foundation

@MainActor
final class AppState: ObservableObject {
    enum PanelTab: String, CaseIterable, Identifiable {
        case meetings = "Toplantılar"
        case tasks = "Görevler"

        var id: Self { self }
    }

    @Published var selectedTab: PanelTab = .meetings
    @Published private(set) var meetingFlow: MeetingFlowState
    @Published private(set) var activeTaskCount = 0
    @Published private(set) var userFacingFailure: AppFailure?
    @Published private(set) var calendarAccessState: CalendarAccessState = .notDetermined
    @Published private(set) var nextMeeting: Meeting?
    @Published private(set) var meetingReminderLevel: MeetingReminderLevel = .none
    @Published private(set) var secondsUntilMeeting: TimeInterval?
    @Published private(set) var recordingCaptureStatus = RecordingCaptureStatus.idle
    @Published private(set) var lastRecordingResult: RecordingCaptureResult?

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

    func recordingSaved(_ result: RecordingCaptureResult) {
        lastRecordingResult = result
        recordingCaptureStatus = .idle
        send(.localRecordingSaved(sessionID: result.session.id))
    }

    func recordingFailed(_ failure: AppFailure) {
        recordingCaptureStatus = .idle
        send(.fail(failure))
    }

    func updateRecordingCaptureStatus(_ status: RecordingCaptureStatus) {
        recordingCaptureStatus = status
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
}
