import SwiftUI

/// The closed notch. Status flanks the camera housing: a glyph or living visual on the
/// left, a value on the right. With nothing to say it is exactly the hardware notch.
struct CrenelCompactView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelNotchMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = appState.compactNotchStatus(now: context.date)
            content(status, now: context.date)
                .animation(Crenel.Motion.resolve(Crenel.Motion.bouncy, reduceMotion: reduceMotion), value: status.identity)
        }
    }

    @ViewBuilder
    private func content(_ status: NotchCompactStatus, now: Date) -> some View {
        if case .idle = status {
            Color.clear
                .frame(width: metrics.hardware.width, height: metrics.hardware.height)
        } else {
            NotchFlankLayout(gap: metrics.hasPhysicalNotch ? metrics.hardware.width + 12 : 14) {
                leading(status, now: now)
                    .id(status.identity)
                    .transition(.crenelPixel)
                trailing(status, now: now)
                    .id(status.identity)
                    .transition(.crenelPixel)
            }
            .padding(.horizontal, 18)
            .frame(height: metrics.hardware.height)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Leading

    @ViewBuilder
    private func leading(_ status: NotchCompactStatus, now: Date) -> some View {
        switch status {
        case .dictation(let state):
            switch state {
            case .listening:
                CrenelMerlonMeter(level: Double(appState.dictationLevel), tint: Crenel.Palette.dictation, columns: 5, rows: 4, pixel: 3)
            case .transcribing, .refining, .inserting:
                CrenelSpinner(tint: Crenel.Palette.dictation)
            case .inserted:
                glyph(.check, Crenel.Palette.success)
            case .failed:
                glyph(.warning, Crenel.Palette.warning)
            case .idle:
                EmptyView()
            }
        case .recording(let recording):
            HStack(spacing: 8) {
                CrenelBlink(tint: Crenel.Palette.record, size: 13.5)
                CrenelIcon(recording.microphoneState == .open ? .mic : .micOff, size: 13.5)
                    .foregroundStyle(recording.microphoneState == .open ? Crenel.Palette.textPrimary : Crenel.Palette.textTertiary)
                    .accessibilityLabel(NotchAccessibilityContract.microphoneGateLabel(recording.microphoneState))
            }
        case .processing(let stage):
            if case .uploading(let progress) = stage {
                CrenelPixelMeter(progress: progress, tint: Crenel.Palette.agent, segments: 6, height: 5)
                    .frame(width: 44)
            } else {
                CrenelSpinner(tint: Crenel.Palette.agent)
            }
        case .completed:
            glyph(.check, Crenel.Palette.success)
        case .failed:
            glyph(.warning, Crenel.Palette.danger)
        case .agenda(let agenda):
            HStack(spacing: 8) {
                glyph(agenda.item.kind == .onlineMeeting ? .video : .calendar, agenda.tint)
                label(agenda.item.title)
            }
        case .focus(let task):
            HStack(spacing: 8) {
                TaskStateGlyph(status: .inProgress, size: 13.5)
                label(task.title)
            }
        case .tasks:
            glyph(.tasks, Crenel.Palette.tasks)
        case .idle:
            EmptyView()
        }
    }

    // MARK: Trailing

    @ViewBuilder
    private func trailing(_ status: NotchCompactStatus, now: Date) -> some View {
        switch status {
        case .dictation(let state):
            switch state {
            case .listening:
                value("dinliyor", Crenel.Palette.dictation)
            case .transcribing, .refining, .inserting:
                value(DictationStatusText.title(for: state).lowercased(with: Locale(identifier: "tr_TR")), Crenel.Palette.dictation)
            case .inserted:
                value("eklendi", Crenel.Palette.success)
            case .failed(let failure):
                value(DictationStatusText.short(for: failure).lowercased(with: Locale(identifier: "tr_TR")), Crenel.Palette.warning)
                    .help(failure.message)
            case .idle:
                EmptyView()
            }
        case .recording(let recording):
            value(Self.elapsed(now.timeIntervalSince(recording.startedAt)), Crenel.Palette.record)
                .contentTransition(.numericText())
                .accessibilityLabel(NotchAccessibilityContract.recordingDurationLabel(Self.elapsed(now.timeIntervalSince(recording.startedAt))))
        case .processing(let stage):
            if case .uploading(let progress) = stage {
                value(progress.formatted(.percent.precision(.fractionLength(0))), Crenel.Palette.agent)
            } else {
                value(stage.shortTitle.lowercased(with: Locale(identifier: "tr_TR")), Crenel.Palette.agent)
            }
        case .completed:
            value("hazır", Crenel.Palette.success)
        case .failed:
            value("hata", Crenel.Palette.danger)
        case .agenda(let agenda):
            value(NotchAgendaFormatter.compactText(for: agenda), agenda.tint)
                .contentTransition(.numericText())
                .accessibilityLabel(NotchAgendaFormatter.accessibilityText(for: agenda))
        case .focus(let task):
            value(NotchAgendaFormatter.durationText(max(60, now.timeIntervalSince(task.startedAt ?? now))), Crenel.Palette.focus)
        case .tasks(let count):
            value("\(count)", Crenel.Palette.tasks)
                .accessibilityLabel("\(count) açık görev")
        case .idle:
            EmptyView()
        }
    }

    // MARK: Pieces

    private func glyph(_ glyph: CrenelGlyph, _ tint: Color) -> some View {
        CrenelIcon(glyph, size: 13.5)
            .foregroundStyle(tint)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Crenel.Palette.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: 130, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func value(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(Crenel.TextStyle.numeral.font)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
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
        case .preparing: "Hazırlanıyor"
        case .finalizing: "Kaydediliyor"
        case .uploading: "Yükleniyor"
        case .transcribing: "Yazıya çevriliyor"
        case .summarizing: "Özetleniyor"
        }
    }
}

extension NotchAgendaStatus {
    var tint: Color {
        switch urgency {
        case .imminent: Crenel.Palette.danger
        case .soon: Crenel.Palette.warning
        case .calm: Crenel.Palette.calendar
        }
    }

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
