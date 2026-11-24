import Foundation

enum MeetingFlowState: Equatable {
    case idle
    case upcomingMeeting(Meeting)
    case preparingRecording
    case recording(startedAt: Date)
    case finalizingAudio
    case uploading(progress: Double)
    case transcribing
    case summarizing
    case completed(meetingID: UUID)
    case cancelled
    case failed(AppFailure)

    enum Phase: String, Equatable {
        case idle
        case upcomingMeeting
        case preparingRecording
        case recording
        case finalizingAudio
        case uploading
        case transcribing
        case summarizing
        case completed
        case cancelled
        case failed
    }

    /// A new recording can start from anything but a recording already under way.
    var canStartRecording: Bool {
        switch self {
        case .preparingRecording, .recording, .finalizingAudio:
            false
        case .idle, .upcomingMeeting, .uploading, .transcribing, .summarizing, .completed, .cancelled, .failed:
            true
        }
    }

    var phase: Phase {
        switch self {
        case .idle: .idle
        case .upcomingMeeting: .upcomingMeeting
        case .preparingRecording: .preparingRecording
        case .recording: .recording
        case .finalizingAudio: .finalizingAudio
        case .uploading: .uploading
        case .transcribing: .transcribing
        case .summarizing: .summarizing
        case .completed: .completed
        case .cancelled: .cancelled
        case .failed: .failed
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var requiresTerminationConfirmation: Bool {
        switch self {
        case .preparingRecording, .recording, .finalizingAudio, .uploading, .transcribing, .summarizing:
            true
        default:
            false
        }
    }
}

enum MeetingFlowEvent: Equatable {
    case detectedUpcomingMeeting(Meeting)
    case dismissedUpcomingMeeting
    case requestedRecording
    case recordingStarted(at: Date)
    case requestedStop
    case localRecordingSaved(sessionID: UUID)
    case processingStarted
    case audioFinalized
    case uploadProgress(Double)
    case uploadCompleted
    case transcriptionCompleted
    case summaryCompleted(meetingID: UUID)
    case cancel
    case fail(AppFailure)
    case retry
    case reset

    var name: String {
        switch self {
        case .detectedUpcomingMeeting: "detectedUpcomingMeeting"
        case .dismissedUpcomingMeeting: "dismissedUpcomingMeeting"
        case .requestedRecording: "requestedRecording"
        case .recordingStarted: "recordingStarted"
        case .requestedStop: "requestedStop"
        case .localRecordingSaved: "localRecordingSaved"
        case .processingStarted: "processingStarted"
        case .audioFinalized: "audioFinalized"
        case .uploadProgress: "uploadProgress"
        case .uploadCompleted: "uploadCompleted"
        case .transcriptionCompleted: "transcriptionCompleted"
        case .summaryCompleted: "summaryCompleted"
        case .cancel: "cancel"
        case .fail: "fail"
        case .retry: "retry"
        case .reset: "reset"
        }
    }
}

struct InvalidMeetingFlowTransition: Error, Equatable {
    let phase: MeetingFlowState.Phase
    let eventName: String
}

struct MeetingFlowMachine {
    private(set) var state: MeetingFlowState
    private var retryState: MeetingFlowState?

    init(initialState: MeetingFlowState = .idle) {
        self.state = initialState
    }

    mutating func send(_ event: MeetingFlowEvent) throws {
        let previousState = state

        switch (state, event) {
        case (.idle, .detectedUpcomingMeeting(let meeting)),
             (.upcomingMeeting, .detectedUpcomingMeeting(let meeting)):
            state = .upcomingMeeting(meeting)

        case (.upcomingMeeting, .dismissedUpcomingMeeting):
            state = .idle

        case (_, .requestedRecording) where state.canStartRecording:
            // Recording is never blocked by what the panel shows: a finished, failed or
            // cancelled flow, or an earlier meeting still processing in the queue.
            state = .preparingRecording
            retryState = nil

        case (.preparingRecording, .recordingStarted(let startedAt)):
            state = .recording(startedAt: startedAt)

        case (.recording, .requestedStop):
            state = .finalizingAudio

        case (.finalizingAudio, .localRecordingSaved(let sessionID)):
            state = .completed(meetingID: sessionID)

        case (.idle, .processingStarted),
             (.completed, .processingStarted),
             (.cancelled, .processingStarted):
            state = .uploading(progress: 0)

        case (.finalizingAudio, .audioFinalized):
            state = .uploading(progress: 0)

        case (.uploading, .uploadProgress(let progress)):
            state = .uploading(progress: min(max(progress, 0), 1))

        case (.uploading, .uploadCompleted):
            state = .transcribing

        case (.transcribing, .transcriptionCompleted):
            state = .summarizing

        case (.summarizing, .summaryCompleted(let meetingID)):
            state = .completed(meetingID: meetingID)

        case (.failed, .retry) where retryState != nil:
            state = retryState ?? .idle
            retryState = nil

        case (.completed, .reset), (.cancelled, .reset), (.failed, .reset):
            state = .idle
            retryState = nil

        case (_, .cancel) where state.requiresTerminationConfirmation:
            state = .cancelled
            retryState = nil

        case (_, .fail(let failure)) where canFail(from: state):
            retryState = failure.isRetryable ? previousState : nil
            state = .failed(failure)

        default:
            throw InvalidMeetingFlowTransition(phase: state.phase, eventName: event.name)
        }
    }

    private func canFail(from state: MeetingFlowState) -> Bool {
        switch state {
        case .preparingRecording, .recording, .finalizingAudio, .uploading, .transcribing, .summarizing:
            true
        default:
            false
        }
    }
}
