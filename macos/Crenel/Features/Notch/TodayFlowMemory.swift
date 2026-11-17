import Combine
import Foundation
import ObjectiveC

/// What the Today tab has to remember while the panel is closed: the level history of
/// the running recording (the chart recorder's two minutes), which calendar event is
/// being recorded, how long the recording was, and what the flow was doing before it
/// was cancelled.
///
/// It lives with the `AppState` (`appState.todayFlowMemory`) and starts listening the
/// first time it is asked for.
@MainActor
final class TodayFlowMemory: ObservableObject {
    /// One sample per second, oldest first, 0…1: the louder of the mic and the call.
    @Published private(set) var levels: [Double] = []
    /// The calendar event the running (or last) recording belongs to, if it is known.
    @Published private(set) var recordingMeeting: Meeting?
    /// Length of the last recording, set when it stops.
    @Published private(set) var recordedDuration: TimeInterval?
    /// The phase the flow was in when it was cancelled.
    @Published private(set) var phaseBeforeCancel: MeetingFlowState.Phase?

    /// Two minutes at one sample a second, plus what a 560 pt panel can show.
    static let capacity = 132

    private weak var appState: AppState?
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?
    private var bucketPeak: Double = 0
    private var recordingStartedAt: Date?
    private var lastPhase: MeetingFlowState.Phase = .idle

    init(appState: AppState) {
        self.appState = appState
        lastPhase = appState.meetingFlow.phase
        appState.$meetingFlow
            .sink { [weak self] flow in self?.flowChanged(to: flow) }
            .store(in: &subscriptions)
        appState.$recordingCaptureStatus
            .sink { [weak self] status in self?.observe(status) }
            .store(in: &subscriptions)
    }

    deinit {
        timer?.invalidate()
    }

    private func flowChanged(to flow: MeetingFlowState) {
        let phase = flow.phase
        defer { lastPhase = phase }

        if case .recording(let startedAt) = flow {
            guard recordingStartedAt != startedAt else { return }
            recordingStartedAt = startedAt
            levels = []
            bucketPeak = 0
            recordedDuration = nil
            phaseBeforeCancel = nil
            recordingMeeting = appState.flatMap { state in
                RecordingMeetingContext.resolve(
                    meetings: state.upcomingMeetings,
                    session: state.meetingSessionDetection?.session,
                    now: startedAt
                )
            }
            startSampling()
            return
        }

        stopSampling()
        if lastPhase == .recording, let recordingStartedAt, phase != .cancelled {
            recordedDuration = Date().timeIntervalSince(recordingStartedAt)
        }
        if phase == .cancelled, lastPhase != .cancelled {
            phaseBeforeCancel = lastPhase
        }
        if phase == .preparingRecording {
            recordingMeeting = nil
            recordedDuration = nil
        }
    }

    private func observe(_ status: RecordingCaptureStatus) {
        guard timer != nil else { return }
        let microphoneOpen = appState?.meetingMicrophoneGate?.permitsAudio ?? true
        let microphone = microphoneOpen ? Double(status.microphone.level) : 0
        let level = max(microphone, Double(status.systemAudio.level))
        bucketPeak = max(bucketPeak, min(1, max(0, level)))
    }

    private func startSampling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pushSample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopSampling() {
        timer?.invalidate()
        timer = nil
    }

    private func pushSample() {
        guard timer != nil else { return }
        levels.append(bucketPeak)
        bucketPeak = 0
        if levels.count > Self.capacity {
            levels.removeFirst(levels.count - Self.capacity)
        }
    }
}

private var todayFlowMemoryKey: UInt8 = 0

extension AppState {
    /// The Today tab's memory for this state object; created on first use.
    @MainActor var todayFlowMemory: TodayFlowMemory {
        if let memory = objc_getAssociatedObject(self, &todayFlowMemoryKey) as? TodayFlowMemory {
            return memory
        }
        let memory = TodayFlowMemory(appState: self)
        objc_setAssociatedObject(self, &todayFlowMemoryKey, memory, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return memory
    }
}
