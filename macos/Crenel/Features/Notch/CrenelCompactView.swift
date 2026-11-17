import AppKit
import SwiftUI

/// The closed notch. Two equal ears flank the camera housing — what on the left, the one
/// number on the right — and the notch is only as wide as the current state needs. With
/// nothing to say it is exactly the hardware notch. Prompts, live dictation and results
/// drop one line under the ears (a strip) instead of opening the panel.
struct CrenelCompactView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var memory: NotchStripMemory
    private let actions: NotchStripActions

    init(actions: NotchStripActions = NotchStripActions(), memory: NotchStripMemory? = nil) {
        self.actions = actions
        self.memory = memory ?? .shared
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = appState.closedNotchState(
                now: context.date,
                dismissedStartingMeetingID: memory.dismissedStartingMeetingID
            )
            NotchClosedView(
                state: state,
                now: context.date,
                level: level(for: state),
                targetAppName: targetAppName(for: state),
                actions: resolvedActions
            )
            // Content appears after the shape has started to move.
            .id(state.identity)
            .transition(.asymmetric(
                insertion: .opacity.animation(reduceMotion ? .linear(duration: 0.01) : Hud.Motion.content),
                removal: .opacity.animation(.easeOut(duration: 0.06))
            ))
        }
    }

    /// The strip's own choices live here; everything else is the app's.
    private var resolvedActions: NotchStripActions {
        var resolved = actions
        let later = actions.dismissStartingMeeting
        resolved.dismissStartingMeeting = { meeting in
            memory.dismissedStartingMeetingID = meeting.id
            later(meeting)
        }
        let dismissResult = actions.dismissResult
        resolved.dismissResult = {
            appState.resetFlow()
            dismissResult()
        }
        let openSettings = actions.openSettings
        resolved.openSettings = {
            NotificationCenter.default.post(name: .openDesktopSettings, object: nil)
            openSettings()
        }
        let download = actions.downloadSpeechModel
        resolved.downloadSpeechModel = {
            crenelActions.dictation.prepareSpeechAssets()
            download()
        }
        let undo = actions.undoDictation
        resolved.undoDictation = {
            crenelActions.dictation.undoLast()
            undo()
        }
        return resolved
    }

    private func level(for state: NotchClosedState) -> Double {
        switch state {
        case .recording:
            Double(max(appState.recordingCaptureStatus.microphone.level, appState.recordingCaptureStatus.systemAudio.level))
        case .dictationListening:
            Double(appState.dictationLevel)
        default:
            0
        }
    }

    /// The notch never activates, so the frontmost app is where dictation types.
    private func targetAppName(for state: NotchClosedState) -> String? {
        switch state {
        case .dictationListening, .dictationWorking, .dictationInserted:
            let app = NSWorkspace.shared.frontmostApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            return app?.localizedName
        default:
            return nil
        }
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        HudFormat.elapsed(interval)
    }
}

/// Answers given on a strip that must outlive the closed view (it is rebuilt every time
/// the panel closes).
@MainActor
final class NotchStripMemory: ObservableObject {
    static let shared = NotchStripMemory()

    /// "Later" (or Join) was pressed on this meeting's "Starting now" strip.
    @Published var dismissedStartingMeetingID: UUID?
}

/// Steps of a pipeline as short capsules: done steps grey, the current one longer and
/// white, the rest a faint track.
struct HudStepMeter: View {
    let steps: Int
    let current: Int
    /// 0…1 inside the current step, when known.
    var progress: Double?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<steps, id: \.self) { index in
                ZStack(alignment: .leading) {
                    Capsule().fill(index < current ? Hud.Ink.text2 : Hud.Ink.track)
                    if index == current {
                        Capsule().fill(Hud.Ink.text1)
                            .frame(width: progress.map { max(4, 12 * $0) })
                    }
                }
                .frame(width: index == current ? 12 : 4, height: 4)
            }
        }
        .animation(Hud.Motion.change, value: current)
        .animation(Hud.Motion.change, value: progress)
        .accessibilityHidden(true)
    }
}

/// Slow opacity breathing for work in progress.
struct HudBreathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.phaseAnimator(reduceMotion ? [1.0] : [0.45, 1.0]) { view, phase in
            view.opacity(phase)
        } animation: { _ in .easeInOut(duration: 0.9) }
    }
}

extension AppState {
    func compactNotchStatus(now: Date) -> NotchCompactStatus {
        NotchStatusResolver.compactStatus(
            flow: meetingFlow,
            nextMeeting: nextMeeting,
            activeTaskCount: activeTaskCount,
            meetingDetection: meetingSessionDetection,
            microphoneGate: meetingMicrophoneGate,
            agendaItems: upcomingMeetings,
            focusedTask: focusedTask,
            dictation: dictationState,
            now: now
        )
    }

    /// The closed notch's state: the compact status, plus the prompts, dictation text and
    /// results that turn it into a strip.
    func closedNotchState(now: Date, dismissedStartingMeetingID: UUID? = nil) -> NotchClosedState {
        var failure: AppFailure?
        if case .failed(let flowFailure) = meetingFlow { failure = flowFailure }
        var detectedTitle: String?
        if case .recordingOffer = meetingLifecyclePrompt {
            detectedTitle = RecordingMeetingContext.resolve(
                meetings: upcomingMeetings + (nextMeeting.map { [$0] } ?? []),
                session: meetingSessionDetection?.session,
                now: now
            )?.title
        }
        return NotchClosedResolver.state(NotchClosedInput(
            status: compactNotchStatus(now: now),
            prompt: meetingLifecyclePrompt,
            detectedMeetingTitle: detectedTitle,
            partialTranscript: dictationPartialTranscript,
            failure: failure,
            completedMeeting: completedMeeting,
            completedActionItems: completedActionItemCount,
            lastStoredMeeting: lastStoredMeeting,
            dismissedStartingMeetingID: dismissedStartingMeetingID,
            upcomingItems: upcomingMeetings,
            dictationKeyHint: dictationKeyHint,
            update: updatePhase,
            updateNotices: updateNotices,
            justUpdatedTo: justUpdatedTo,
            now: now
        ))
    }
}

extension NotchCompactStatus {
    /// Changes only when the kind of status changes, not every tick of a countdown.
    var identity: String {
        switch self {
        case .dictation(let state):
            switch state {
            case .listening: "dictation.listening"
            case .transcribing, .refining, .inserting: "dictation.working"
            case .inserted: "dictation.inserted"
            case .failed: "dictation.failed"
            case .idle: "dictation.idle"
            }
        case .recording: "recording"
        case .processing(let stage):
            if case .uploading = stage { "processing.upload" } else { "processing.\(stage.shortTitle)" }
        case .completed: "completed"
        case .failed: "failed"
        case .agenda(let agenda): "agenda.\(agenda.item.id)"
        case .focus(let task): "focus.\(task.id)"
        case .tasks: "tasks"
        case .idle: "idle"
        }
    }
}

extension NotchCompactStatus.ProcessingStage {
    /// The step word in the left ear.
    var shortTitle: String {
        switch self {
        case .preparing: "Preparing"
        case .finalizing: "Saving"
        case .uploading: "Uploading"
        case .transcribing: "Transcribing"
        case .summarizing: "Summarizing"
        }
    }
}

extension NotchCompactStatus.ProcessingStage {
    /// Which of the four stations is live: Saved, Uploaded, Transcribing, Notes.
    var stepIndex: Int {
        switch self {
        case .preparing, .finalizing: 0
        case .uploading: 1
        case .transcribing: 2
        case .summarizing: 3
        }
    }

    var stepProgress: Double? {
        if case .uploading(let progress) = self { return progress }
        return nil
    }
}

extension NotchAgendaStatus {
    /// Amber when it needs you: starting within ten minutes, or under way.
    var isUrgent: Bool {
        switch phase {
        case .ongoing: true
        case .upcoming(let startsIn): startsIn <= 10 * 60
        }
    }

    /// Minutes while under an hour; the day or a duration further out.
    var compactValue: String {
        switch phase {
        case .ongoing(let remaining):
            return "\(max(1, Int((remaining / 60).rounded(.up)))) min"
        case .upcoming(let startsIn):
            if startsIn <= 60 * 60 { return "\(max(1, Int((startsIn / 60).rounded(.up)))) min" }
            if !Calendar.current.isDateInToday(item.startDate) { return HudFormat.day(item.startDate, now: Date()) }
            return NotchAgendaFormatter.durationText(startsIn)
        }
    }

    var tint: Color { isUrgent ? Hud.Ink.signal : Hud.Ink.text2 }

    /// Ongoing: elapsed share of the event. Upcoming: how close the start is within the
    /// last hour.
    func ringProgress(now: Date) -> Double {
        switch phase {
        case .ongoing:
            let duration = max(60, item.endDate.timeIntervalSince(item.startDate))
            return min(1, max(0, now.timeIntervalSince(item.startDate) / duration))
        case .upcoming(let startsIn):
            return min(1, max(0.04, 1 - startsIn / 3_600))
        }
    }
}
