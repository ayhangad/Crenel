import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the Today tab asks for the Recordings list (failed and stopped
    /// results). The notch shell shows the list.
    static let crenelShowRecordings = Notification.Name("Crenel.showRecordings")
}

/// Gauges and meters sweep once when the panel opens from closed, not when the Today
/// tab comes back from Tasks or from a meeting's detail.
enum TodayIgnition {
    static var suppressNext = false
}

// MARK: - Today tab

/// The Today tab of the open notch: Today while nothing runs, then Recording,
/// Processing and the Result.
struct MeetingStatusView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCancelConfirmation = false
    @State private var resultStats: MeetingResultStats?
    /// True only right after the panel opened from closed (set by the notch shell).
    @Environment(\.notchPanelIgnites) private var panelIgnites
    @State private var localIgnite = !TodayIgnition.suppressNext
    private var ignite: Bool { panelIgnites && localIgnite }
    let onRequestCalendarAccess: () -> Void
    let onOpenMeetingURL: (URL) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onToggleMeetingMicrophone: () -> Void
    let onDismissMeetingPrompt: () -> Void
    let onContinueRecording: () -> Void
    let onConfirmMeetingEnded: () -> Void
    let onCancelFlow: () -> Void
    let onRecoverFromFailure: (AppFailure) -> Void
    let onOpenStoredMeeting: (StoredMeeting) -> Void
    let onRelaunchApplication: () -> Void
    /// Shows the Recordings list; posts `.crenelShowRecordings` when nil.
    let onShowRecordings: (() -> Void)?
    /// Reads the finished meeting's numbers; the meeting store when nil.
    let loadResultStats: ((StoredMeeting) async -> MeetingResultStats?)?

    init(
        onRequestCalendarAccess: @escaping () -> Void,
        onOpenMeetingURL: @escaping (URL) -> Void,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onToggleMeetingMicrophone: @escaping () -> Void,
        onDismissMeetingPrompt: @escaping () -> Void,
        onContinueRecording: @escaping () -> Void,
        onConfirmMeetingEnded: @escaping () -> Void,
        onCancelFlow: @escaping () -> Void,
        onRecoverFromFailure: @escaping (AppFailure) -> Void,
        onOpenStoredMeeting: @escaping (StoredMeeting) -> Void,
        onRelaunchApplication: @escaping () -> Void,
        onShowRecordings: (() -> Void)? = nil,
        loadResultStats: ((StoredMeeting) async -> MeetingResultStats?)? = nil
    ) {
        self.onRequestCalendarAccess = onRequestCalendarAccess
        self.onOpenMeetingURL = onOpenMeetingURL
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onToggleMeetingMicrophone = onToggleMeetingMicrophone
        self.onDismissMeetingPrompt = onDismissMeetingPrompt
        self.onContinueRecording = onContinueRecording
        self.onConfirmMeetingEnded = onConfirmMeetingEnded
        self.onCancelFlow = onCancelFlow
        self.onRecoverFromFailure = onRecoverFromFailure
        self.onOpenStoredMeeting = onOpenStoredMeeting
        self.onRelaunchApplication = onRelaunchApplication
        self.onShowRecordings = onShowRecordings
        self.loadResultStats = loadResultStats
    }

    var body: some View {
        let memory = appState.todayFlowMemory

        Group {
            if showsCancelConfirmation, Self.isCancellable(appState.meetingFlow.phase) {
                CancelConfirmationSurface(
                    title: cancelConfirmationTitle,
                    message: cancelConfirmationMessage,
                    confirmTitle: cancelConfirmationButtonTitle,
                    onKeep: { showsCancelConfirmation = false },
                    onConfirm: {
                        showsCancelConfirmation = false
                        onCancelFlow()
                    }
                )
            } else {
            switch appState.meetingFlow {
            case .idle, .upcomingMeeting:
                TodaySurface(
                    events: agenda,
                    emptyMessage: CalendarEmptyPresentation.message(enabled: appState.isCalendarEnabled,
                        access: appState.calendarAccessState, snapshot: appState.calendarIntegrationSnapshot),
                    canRequestCalendarAccess: appState.isCalendarEnabled && appState.calendarAccessState != .authorized,
                    onRequestCalendarAccess: onRequestCalendarAccess,
                    onOpenMeetingURL: onOpenMeetingURL,
                    onStartRecording: onStartRecording,
                    calendar: TodayCalendarState(enabled: appState.isCalendarEnabled, access: appState.calendarAccessState,
                                                 snapshot: appState.calendarIntegrationSnapshot),
                    meetBridge: meetBridge,
                    ignite: ignite
                )

            case .preparingRecording:
                PreparingSurface(onCancel: { showsCancelConfirmation = true })

            case .recording(let startedAt):
                LiveRecordingSurface(
                    memory: memory,
                    startedAt: startedAt,
                    ignite: ignite,
                    onToggleMicrophone: onToggleMeetingMicrophone,
                    onStop: onStopRecording,
                    onDelete: { showsCancelConfirmation = true }
                )

            case .finalizingAudio:
                ProcessingSurface(station: .saving, title: memory.recordingMeeting?.title, recorded: memory.recordedDuration)

            case .uploading(let progress):
                processing(.uploading, uploadProgress: progress)

            case .transcribing:
                processing(.transcribing)

            case .summarizing:
                processing(.summarizing)

            case .completed:
                let meeting = appState.completedMeeting
                ReadySurface(
                    title: meeting?.title,
                    recorded: meeting.map { $0.endedAt.timeIntervalSince($0.startedAt) },
                    stats: resultStats,
                    onDone: appState.resetFlow,
                    onOpen: meeting.map { meeting in { onOpenStoredMeeting(meeting) } }
                )

            case .failed(let failure):
                failed(failure)

            case .cancelled:
                stopped(after: memory.phaseBeforeCancel)
            }
            }
        }
        // Asked inside the notch: a system alert attached to the non-activating notch panel
        // could open out of reach of the pointer or vanish when the panel folded, so Stop
        // and Cancel looked like they did nothing.
        .onChange(of: appState.meetingFlow.phase) { _, phase in
            if !Self.isCancellable(phase) { showsCancelConfirmation = false }
        }
        .task(id: appState.completedMeeting?.id) {
            resultStats = nil
            guard let meeting = appState.completedMeeting else { return }
            resultStats = await (loadResultStats ?? Self.storedResultStats)(meeting)
        }
        .modifier(SuppressIgnitionWhenHidden())
        .onDisappear {
            // Leaving for Tasks or a meeting's detail is not closing the panel.
            TodayIgnition.suppressNext = appState.selectedTab != .meetings || appState.presentedMeetingDetail != nil
        }
        .animation(reduceMotion ? nil : Hud.Motion.change, value: appState.meetingFlow.phase)
    }

    /// Today and the next few days, the next meeting first even if it starts later.
    private var agenda: [Meeting] {
        var items = appState.upcomingMeetings
        if let nextMeeting = appState.nextMeeting, !items.contains(where: { $0.id == nextMeeting.id }) {
            items.append(nextMeeting)
        }
        let sorted = items.sorted { lhs, rhs in
            (lhs.isAllDay ? 1 : 0, lhs.startDate) < (rhs.isAllDay ? 1 : 0, rhs.startDate)
        }
        return Array(sorted.prefix(8))
    }

    /// The Meet bridge only matters while a Meet call is detected.
    private var meetBridge: TodayMeetBridge {
        guard appState.meetingSessionDetection?.session.clientID == .googleMeetChrome else { return .none }
        switch appState.browserAudioConnectionStatus {
        case .unavailable: return .unavailable
        case .waitingForMeetTab: return .waiting
        case .tabConnected, .recording: return .none
        }
    }

    // MARK: Processing

    private func processing(_ station: ProcessingSurface.Station, uploadProgress: Double? = nil) -> some View {
        let meeting = processedMeeting
        return ProcessingSurface(
            station: station,
            title: meeting?.title,
            recorded: meeting.map { $0.endedAt.timeIntervalSince($0.startedAt) },
            uploadProgress: uploadProgress,
            onStop: { showsCancelConfirmation = true }
        )
    }

    /// The meeting the worker is on: the running job's, else the last one saved.
    private var processedMeeting: StoredMeeting? {
        if let job = appState.processingJobs.first(where: { $0.state == .running }),
           let meeting = appState.storedMeetings.first(where: { $0.id == job.meetingID }) {
            return meeting
        }
        return appState.lastStoredMeeting
    }

    private static func storedResultStats(_ meeting: StoredMeeting) async -> MeetingResultStats? {
        // Tests never read the user's meeting store.
        guard NSClassFromString("XCTestCase") == nil else { return nil }
        guard let transcription = try? await FileMeetingRepository().loadTranscription(for: meeting.id) else { return nil }
        return MeetingResultStats(transcription: transcription)
    }

    // MARK: Result

    private func failed(_ failure: AppFailure) -> some View {
        let isPermission = failure.category == .permission
        let secondary: FlowOutcomeSurface.Action?
        let primary: FlowOutcomeSurface.Action
        if isPermission, failure.recoveryAction == .openSystemSettings {
            secondary = .init(title: String(localized: "System Settings"), glyph: .link) { onRecoverFromFailure(failure) }
            primary = .init(title: String(localized: "Relaunch"), run: onRelaunchApplication)
        } else {
            secondary = isPermission ? nil : .init(title: String(localized: "Recordings"), glyph: .tape, run: showRecordings)
            primary = .init(title: failure.recoveryButtonTitle) { onRecoverFromFailure(failure) }
        }
        return FlowOutcomeSurface(
            status: isPermission ? .off : .err,
            tint: Hud.Ink.live,
            title: failure.title,
            message: failure.message,
            secondary: secondary,
            primary: primary
        )
    }

    private func stopped(after phase: MeetingFlowState.Phase?) -> some View {
        let done = FlowOutcomeSurface.Action(title: String(localized: "Done"), run: appState.resetFlow)
        switch phase {
        case .uploading, .transcribing, .summarizing:
            return FlowOutcomeSurface(
                status: .stop,
                title: String(localized: "Processing stopped"),
                message: String(localized: "The audio is kept. You can process it later from Recordings."),
                secondary: .init(title: String(localized: "Recordings"), glyph: .tape) {
                    appState.resetFlow()
                    showRecordings()
                },
                primary: done
            )
        case .recording, .finalizingAudio:
            return FlowOutcomeSurface(
                status: .stop,
                title: String(localized: "Recording deleted"),
                message: String(localized: "Mic and system audio were deleted."),
                primary: done
            )
        default:
            return FlowOutcomeSurface(status: .stop, title: String(localized: "Stopped"), primary: done)
        }
    }

    private func showRecordings() {
        if let onShowRecordings {
            onShowRecordings()
        } else {
            NotificationCenter.default.post(name: .crenelShowRecordings, object: nil)
        }
    }

    // MARK: Cancel confirmation

    static func isCancellable(_ phase: MeetingFlowState.Phase) -> Bool {
        switch phase {
        case .preparingRecording, .recording, .uploading, .transcribing, .summarizing: true
        default: false
        }
    }

    private var cancelConfirmationTitle: String {
        switch appState.meetingFlow.phase {
        case .recording:
            "Delete recording?"
        case .uploading, .transcribing, .summarizing:
            "Stop processing?"
        default:
            "Cancel recording setup?"
        }
    }

    private var cancelConfirmationButtonTitle: String {
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            "Stop processing"
        case .recording:
            "Delete recording"
        default:
            "Cancel setup"
        }
    }

    private var cancelConfirmationMessage: String {
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            "The audio is kept. You can process it later from Recordings."
        case .recording:
            "This recording isn’t saved yet. Mic and system audio will be deleted permanently."
        default:
            "Temporary recording files will be deleted."
        }
    }
}

// MARK: - Cancel confirmation

/// Stop or delete, confirmed in place. Esc keeps going, Return confirms.
struct CancelConfirmationSurface: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onKeep: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HudStatusShape(.warn)
                Text(verbatim: title).hud(.body, Hud.Ink.ink1)
            }
            Text(verbatim: message).hud(.meta, Hud.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HudActions {
                HudButton("Keep", key: "esc", size: .small, action: onKeep)
                    .hudShortcut(.cancelAction)
                HudButton(confirmTitle, key: "↩", kind: .danger, size: .small, action: onConfirm)
                    .hudShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Recording, live

/// The recording surface fed from the app: levels, the mic gate, and the level history
/// the Today tab keeps while the panel is closed.
private struct LiveRecordingSurface: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var memory: TodayFlowMemory
    let startedAt: Date
    let ignite: Bool
    let onToggleMicrophone: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let gate = appState.meetingMicrophoneGate
        let capture = appState.recordingCaptureStatus
        let clientName = RecordingSurface.clientName(appState.meetingSessionDetection?.session.clientID)
        let event = memory.recordingMeeting
        RecordingSurface(
            startedAt: startedAt,
            title: event?.title,
            plannedLength: event.flatMap { $0.isAllDay ? nil : $0.endDate.timeIntervalSince($0.startDate) },
            microphone: gate?.state,
            microphoneLevel: Double(capture.microphone.level),
            callLevel: Double(capture.systemAudio.level),
            callFailed: capture.systemAudio.connectionState == .pipelineStalled,
            levels: memory.levels,
            muteFollows: appState.accessibilityPermissionGranted ? clientName : nil,
            warnings: RecordingSurface.warnings(gate: gate, clientName: clientName, capture: capture,
                                                safetyMessage: appState.recordingSafetyMessage),
            ignite: ignite,
            onToggleMicrophone: onToggleMicrophone,
            onStop: onStop,
            onDelete: onDelete
        )
    }
}

// MARK: - Prompts

/// A detected meeting or an ending one: one row on a faint surface, the answer on the
/// right. The panel no longer shows it — the prompt is a strip under the closed notch —
/// but the row is kept for call sites that still want it.
struct MeetingLifecyclePromptView: View {
    let prompt: MeetingLifecyclePrompt
    let onStartRecording: () -> Void
    let onDismiss: () -> Void
    let onContinueRecording: () -> Void
    let onConfirmEnd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Hud.Space.x3) {
            HudIcon(glyph).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).hud(.body)
                Text(detail).hud(.meta, Hud.Ink.text3).lineLimit(1)
            }
            Spacer(minLength: Hud.Space.x2)

            if case .autoStop(_, _, let deadline) = prompt {
                AutoStopCountdownView(deadline: deadline)
            }

            switch prompt {
            case .recordingOffer:
                Button("Not now", action: onDismiss)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                Button(action: onStartRecording) {
                    HStack(spacing: 6) {
                        Circle().fill(Hud.Ink.live).frame(width: 7, height: 7)
                        Text("Record")
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .primary))
            case .endConfirmation, .autoStop:
                Button("Keep", action: onContinueRecording)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                Button("Stop", action: onConfirmEnd)
                    .buttonStyle(HudButtonStyle(kind: .primary))
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(minHeight: Hud.Size.row + 4)
        .background(RoundedRectangle(cornerRadius: Hud.Size.corner + 2, style: .continuous).fill(Hud.Ink.hover))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var title: String {
        switch prompt {
        case .recordingOffer(_, let clientID): clientName(clientID)
        case .endConfirmation: String(localized: "Meeting may have ended")
        case .autoStop: String(localized: "Meeting ended")
        }
    }

    private var detail: String {
        switch prompt {
        case .recordingOffer: String(localized: "Record this meeting?")
        case .endConfirmation: String(localized: "Stop the recording?")
        case .autoStop: String(localized: "Recording stops soon")
        }
    }

    private var glyph: HudGlyph {
        switch prompt {
        case .recordingOffer: .video
        case .endConfirmation, .autoStop: .stop
        }
    }

    private var tint: Color {
        switch prompt {
        case .recordingOffer: Hud.Ink.signal
        case .endConfirmation: Hud.Ink.text2
        case .autoStop: Hud.Ink.live
        }
    }

    private func clientName(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: String(localized: "Meeting detected")
        }
    }
}

private struct AutoStopCountdownView: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            Text("\(seconds) s")
                .hud(.value, Hud.Ink.live)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("Recording stops in \(seconds) seconds")
        }
    }
}

struct RecordingRecoveryNoticeView: View {
    let summary: RecordingRecoverySummary
    let onOpenRecovery: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Hud.Space.x3) {
            HudIcon(.history).foregroundStyle(summary.preservedCount > 0 ? Hud.Ink.signal : Hud.Ink.text2)
            VStack(alignment: .leading, spacing: 2) {
                if summary.recoveredCount > 0 {
                    Text("\(summary.recoveredCount) recordings recovered").hud(.body)
                }
                if summary.preservedCount > 0 {
                    Text("\(summary.preservedCount) kept in Recovery").hud(.meta, Hud.Ink.text3)
                }
            }
            Spacer(minLength: Hud.Space.x2)
            if summary.preservedCount > 0 {
                Button("Show", action: onOpenRecovery)
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .help("Show Recovery folder")
            }
            Button(action: onDismiss) {
                HudIcon(.close, size: Hud.Size.smallIcon)
            }
            .buttonStyle(HudButtonStyle(kind: .icon))
            .accessibilityLabel("Dismiss recovery notice")
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(minHeight: Hud.Size.row)
        .background(RoundedRectangle(cornerRadius: Hud.Size.corner + 2, style: .continuous).fill(Hud.Ink.hover))
    }
}

/// Hidden behind another tab is not closing the panel: the gauges should not sweep again
/// when Today shows. A modifier of its own, so Today does not re-render on the switch.
private struct SuppressIgnitionWhenHidden: ViewModifier {
    @Environment(\.hudVisibility) private var visibility
    private var hidden: Bool { visibility?.isHidden ?? false }

    func body(content: Content) -> some View {
        content.onChange(of: hidden) { _, hidden in if hidden { TodayIgnition.suppressNext = true } }
    }
}
