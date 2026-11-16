import SwiftUI

/// The closed notch. Two equal ears flank the camera housing — a mark on the left, a
/// value on the right, each centred in its ear — and the notch is only as wide as the
/// current state needs. With nothing to say it is exactly the hardware notch.
struct CrenelCompactView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelNotchMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = appState.compactNotchStatus(now: context.date)
            content(status, now: context.date)
                .animation(reduceMotion ? nil : Hud.Motion.change, value: status.identity)
        }
    }

    @ViewBuilder
    private func content(_ status: NotchCompactStatus, now: Date) -> some View {
        if case .idle = status {
            Color.clear
                .frame(width: metrics.hardware.width, height: metrics.hardware.height)
        } else {
            HudEarsLayout(gap: metrics.hasPhysicalNotch ? metrics.hardware.width : Hud.Space.x3, padding: Hud.Space.x4) {
                leading(status, now: now)
                    .id("leading." + status.identity)
                    .transition(.opacity)
                trailing(status, now: now)
                    .id("trailing." + status.identity)
                    .transition(.opacity)
            }
            .frame(height: metrics.hardware.height)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Leading — what it is

    @ViewBuilder
    private func leading(_ status: NotchCompactStatus, now: Date) -> some View {
        switch status {
        case .dictation(let state):
            switch state {
            case .listening:
                HudIcon(.mic).foregroundStyle(Hud.Ink.text1)
            case .transcribing, .refining, .inserting:
                HudIcon(.mic).foregroundStyle(Hud.Ink.text2).modifier(HudBreathing())
            case .inserted:
                HudIcon(.mic).foregroundStyle(Hud.Ink.text2)
            case .failed:
                HudIcon(.mic).foregroundStyle(Hud.Ink.live)
            case .idle:
                EmptyView()
            }
        case .recording(let recording):
            HStack(spacing: 7) {
                HudPulse(color: Hud.Ink.live)
                Text(HudFormat.elapsed(now.timeIntervalSince(recording.startedAt)))
                    .hud(.label)
                    .contentTransition(.numericText())
                    .accessibilityLabel(NotchAccessibilityContract.recordingDurationLabel(HudFormat.elapsed(now.timeIntervalSince(recording.startedAt))))
            }
        case .processing:
            HudIcon(.transcript).foregroundStyle(Hud.Ink.text2).modifier(HudBreathing())
                .accessibilityLabel("Processing")
        case .completed:
            HudIcon(.transcript).foregroundStyle(Hud.Ink.text1)
        case .failed:
            HudIcon(.transcript).foregroundStyle(Hud.Ink.live)
        case .agenda(let agenda):
            HStack(spacing: 7) {
                MeetingKindIcon(meeting: agenda.item, tint: agenda.isUrgent ? Hud.Ink.signal : Hud.Ink.text3)
                if agenda.phase.isOngoing {
                    title(agenda.item.title)
                } else {
                    Text(HudFormat.clock(agenda.item.startDate)).hud(.label)
                }
            }
        case .focus(let task):
            HStack(spacing: 7) {
                HudStateMark(state: .inProgress, size: 12)
                title(task.title)
            }
        case .tasks:
            HudIcon(.queue).foregroundStyle(Hud.Ink.text2)
        case .idle:
            EmptyView()
        }
    }

    // MARK: Trailing — how it is going

    @ViewBuilder
    private func trailing(_ status: NotchCompactStatus, now: Date) -> some View {
        switch status {
        case .dictation(let state):
            switch state {
            case .listening:
                CrenelLevelBars(level: Double(appState.dictationLevel), tint: Hud.Ink.text1, height: 14)
            case .transcribing, .refining, .inserting:
                HudStepMeter(steps: 3, current: state == .transcribing ? 0 : (state == .refining ? 1 : 2))
                    .help(DictationStatusText.title(for: state))
            case .inserted:
                Text("Inserted").hud(.label, Hud.Ink.ok)
            case .failed(let failure):
                Text(DictationStatusText.short(for: failure)).hud(.label, Hud.Ink.live)
                    .lineLimit(1).fixedSize()
                    .help(failure.message)
            case .idle:
                EmptyView()
            }
        case .recording(let recording):
            HStack(spacing: 6) {
                if recording.microphoneState != .open {
                    CrenelIcon(.micOff, size: Hud.Size.smallIcon)
                        .foregroundStyle(recording.microphoneState == .unknown ? Hud.Ink.signal : Hud.Ink.text3)
                        .accessibilityLabel(NotchAccessibilityContract.microphoneGateLabel(recording.microphoneState))
                }
                CrenelLevelBars(level: recordingLevel, tint: Hud.Ink.text1, height: 14)
            }
        case .processing(let stage):
            HudStepMeter(steps: 4, current: stage.stepIndex, progress: stage.stepProgress)
                .help(stage.shortTitle)
        case .completed:
            Text("Ready").hud(.label, Hud.Ink.ok)
        case .failed:
            Text("Failed").hud(.label, Hud.Ink.live)
        case .agenda(let agenda):
            Text(agenda.compactValue)
                .hud(.label, agenda.isUrgent ? Hud.Ink.signal : Hud.Ink.text2)
                .lineLimit(1).fixedSize()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel(NotchAgendaFormatter.accessibilityText(for: agenda))
        case .focus(let task):
            Text(NotchAgendaFormatter.durationText(max(60, now.timeIntervalSince(task.startedAt ?? now))))
                .hud(.label, Hud.Ink.text2)
                .lineLimit(1).fixedSize()
        case .tasks(let count):
            Text("\(count)").hud(.label, Hud.Ink.text2)
                .contentTransition(.numericText())
                .accessibilityLabel("\(count) open tasks")
        case .idle:
            EmptyView()
        }
    }

    // MARK: Pieces

    private var recordingLevel: Double {
        Double(max(appState.recordingCaptureStatus.microphone.level, appState.recordingCaptureStatus.systemAudio.level))
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .hud(.label)
            .lineLimit(1)
            .frame(maxWidth: 110, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        HudFormat.elapsed(interval)
    }
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
