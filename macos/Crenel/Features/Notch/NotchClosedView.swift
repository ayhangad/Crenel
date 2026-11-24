import SwiftUI

/// What the strip's buttons do. The app wires these to the same actions the panel uses.
struct NotchStripActions {
    /// Join ↩ on "Starting now".
    var joinMeeting: (URL) -> Void = { _ in }
    /// Later esc on "Starting now".
    var dismissStartingMeeting: (Meeting) -> Void = { _ in }
    /// Record ↩ on "Record this call?".
    var startRecording: () -> Void = {}
    /// Not now esc on "Record this call?".
    var dismissPrompt: () -> Void = {}
    /// Keep esc on "The call seems to have ended" / "Call ended".
    var continueRecording: () -> Void = {}
    /// Stop ↩ on the same.
    var confirmMeetingEnded: () -> Void = {}
    /// Open ↩ on the result strip.
    var openStoredMeeting: (StoredMeeting) -> Void = { _ in }
    /// Later esc on the result strip.
    var dismissResult: () -> Void = {}
    /// Retry ↩ (or the failure's own fix) on the failure strip.
    var recoverFromFailure: (AppFailure) -> Void = { _ in }
    /// Settings on a dictation strip that needs a permission.
    var openSettings: () -> Void = {}
    /// Download on a dictation strip that needs the speech model.
    var downloadSpeechModel: () -> Void = {}
    /// Requests the permission a dictation failure names.
    var allowDictationAccess: (DictationFailure) -> Void = { _ in }
    /// Undo ⌘Z on "Inserted", while the result can still be taken back.
    var undoDictation: () -> Void = {}
    /// Restart ↩ on "Crenel 1.2 is ready".
    var restartToUpdate: () -> Void = {}
    /// Later esc on the same.
    var dismissUpdateReady: () -> Void = {}
    /// OK esc on "Update installs after this call".
    var acknowledgeUpdateDuringRecording: () -> Void = {}
    /// What's new ↩ on "You're on Crenel 1.2".
    var showReleaseNotes: (AppUpdateVersion) -> Void = { _ in }
}

/// The closed notch for one state: two equal ears beside the camera — what on the left,
/// the one number on the right — and, for strip states, one 38 pt line under them.
struct NotchClosedView: View {
    let state: NotchClosedState
    var now = Date()
    /// 0…1, for the ladder: the recording level or the dictation level.
    var level: Double = 0
    /// The app dictation is typing into, when it is known.
    var targetAppName: String?
    var actions = NotchStripActions()
    /// False inside the open panel, where only the strip's line is shown under the band.
    var showsEars = true

    @Environment(\.crenelNotchMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !showsEars {
                if state.isStrip { NotchStripLine(scanning: isWorking) { strip } }
            } else if case .idle = state {
                // Nothing to say: exactly the hardware notch.
                Color.clear.frame(width: metrics.hardware.width, height: metrics.hardware.height)
            } else if state.isStrip {
                VStack(spacing: 0) {
                    ears(totalWidth: Hud.Notch.stripWidth)
                    Group {
                        if let liveText {
                            NotchLiveDictation(text: liveText, level: level)
                        } else {
                            NotchStripLine(scanning: isWorking) { strip }
                        }
                    }
                    .padding(.horizontal, Hud.Notch.stripInset)
                    .padding(.bottom, Hud.Notch.stripBottom)
                }
                .frame(width: Hud.Notch.stripWidth)
                .animation(reduceMotion ? nil : Hud.Motion.shape, value: liveText != nil)
            } else {
                ears(totalWidth: nil)
            }
        }
        .crenelNotchClosedTraits(state.traits(now: now))
    }

    private func ears(totalWidth: CGFloat?) -> some View {
        NotchFlankLayout(gap: metrics.earGap, totalWidth: totalWidth) {
            HStack(spacing: Hud.Notch.earGap) { leading }
                .padding(.leading, Hud.Notch.earPadding)
                .padding(.trailing, Hud.Notch.earInnerPadding)
            HStack(spacing: Hud.Notch.earGap) { trailing }
                .padding(.trailing, Hud.Notch.earPadding)
                .padding(.leading, Hud.Notch.earInnerPadding)
        }
        .frame(height: metrics.hardware.height > 0 ? metrics.hardware.height : Hud.Notch.compactHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Left ear — what it is

    @ViewBuilder
    private var leading: some View {
        switch state {
        case .idle:
            EmptyView()
        case .standby, .tasks, .updatePending:
            HudMark().accessibilityHidden(true)
        case .updating(let progress):
            HudIcon(.download, size: 14)
                .foregroundStyle(progress == nil ? Hud.Ink.ok : Hud.Ink.ink2)
                .hudLoop(progress == nil ? .breathe : .steady)
            word(progress == nil ? String(localized: "Preparing") : String(localized: "Update"), lit: false)
        case .updateReady:
            HudLamp(.teal, form: .dot)
            word(String(localized: "Update ready"), lit: true)
        case .restarting:
            HudMark().accessibilityHidden(true)
            word(String(localized: "Restarting"), lit: true)
        case .updated:
            HudMark().accessibilityHidden(true)
            word(String(localized: "Updated"), lit: true)
        case .meeting(let agenda):
            let ear = NotchMeetingEar(agenda, now: now)
            switch ear.kind {
            case .urgent:
                HudTelltale(agenda.item.notchGlyph, .amber, size: 14)
                title(agenda.item.title, lit: true)
            case .live:
                HudLamp(.amber, form: .dot)
                title(agenda.item.title, lit: true)
            case .later, .hour, .otherDay:
                HudIcon(agenda.item.notchGlyph, size: 14).foregroundStyle(Hud.Ink.ink3)
                title(agenda.item.title, lit: false)
            }
        case .meetingStarting(let meeting):
            HudTelltale(meeting.notchGlyph, .amber, size: 14)
            title(meeting.title, lit: true)
        case .callDetected(let clientID, _):
            HudTelltale(.video, .amber, size: 14)
            title(NotchClosedText.clientName(clientID), lit: true)
        case .recording(let recording, _):
            HudLamp(.red, form: .dot, loop: .pulse)
            HudSegmentDigits(HudFormat.elapsed(now.timeIntervalSince(recording.startedAt)), height: 13)
        case .processing(let stage):
            HudIcon(.transcript, size: 14).foregroundStyle(Hud.Ink.ink2).hudLoop(.breathe)
            word(stage.shortTitle, lit: false)
        case .focus(let task):
            HudStateMark(state: .inProgress, size: 14)
            title(task.title, lit: true)
        case .dictationListening:
            HudTelltale(.mic, .white, size: 14)
            word(String(localized: "Listening"), lit: true)
        case .dictationWorking:
            HudIcon(.mic, size: 14).foregroundStyle(Hud.Ink.ink2).hudLoop(.breathe)
            word(String(localized: "Writing"), lit: false)
        case .dictationInserted(let summary):
            HudIcon(.mic, size: 14).foregroundStyle(Hud.Ink.ink2)
            word(summary.earWord, lit: false)
        case .dictationFailed(let failure):
            let words = NotchClosedText.dictationFailure(failure)
            if words.accessWord != nil || failure == .microphoneUnavailable {
                HudTelltale(.mic, .red, paren: true)
            } else {
                HudIcon(.mic, size: 14).foregroundStyle(Hud.Ink.ink2)
            }
            word(words.reason, lit: true)
        case .ready(let meeting, _):
            HudIcon(.transcript, size: 14).foregroundStyle(Hud.Ink.ink1)
            title(meeting?.title ?? String(localized: "Meeting"), lit: true)
        case .failed(let failure, let meetingTitle, _):
            HudStatusShape(.err, size: HudStatusShape.ear)
            title(meetingTitle ?? failure.title, lit: true)
        }
    }

    // MARK: Right ear — the one number

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .idle:
            EmptyView()
        case .standby(.nextEvent(let meeting)):
            Text(NotchClosedText.dayWord(meeting.startDate)).hud(.meta).fixedSize()
            HudSegmentDigits(HudFormat.clock(meeting.startDate), height: 13, color: Hud.Ink.ink2)
        case .updating(let progress):
            if let progress {
                HudReadout("\(Int((progress * 100).rounded(.down)))", unit: "%", cells: 2)
            } else {
                HudBusy()
            }
        case .updateReady(let version), .updated(let version):
            HudSegmentDigits(version.shortVersion, height: 13, color: Hud.Ink.ok)
        case .updatePending:
            HudLamp(.teal, form: .dot)
            Text("Update").hud(.meta).fixedSize()
        case .restarting:
            HudBusy()
        case .standby(.dictationKey(let key)):
            HudIcon(.mic, size: 14).foregroundStyle(Hud.Ink.ink3)
            Text(verbatim: key).hud(.meta, Hud.Ink.ink2).fixedSize()
        case .meeting(let agenda):
            let ear = NotchMeetingEar(agenda, now: now)
            switch ear.kind {
            case .later:
                // Today: how long is left, not when it starts.
                HudSegmentDigits(HudFormat.remaining(minutes: ear.minutes), height: 13)
                    .accessibilityLabel("Starts in \(ear.minutes / 60) hours \(ear.minutes % 60) minutes")
            case .otherDay:
                Text(NotchClosedText.dayWord(agenda.item.startDate)).hud(.meta).fixedSize()
                HudSegmentDigits(HudFormat.clock(agenda.item.startDate), height: 13, color: Hud.Ink.ink2)
            case .hour:
                HudReadout("\(ear.minutes)", unit: "min", cells: 2)
            case .urgent:
                HudReadout("\(ear.minutes)", unit: "min", cells: 2, color: Hud.Ink.signal)
            case .live:
                HudReadout("\(ear.minutes)", unit: "left", cells: 2, color: Hud.Ink.signal)
            }
        case .meetingStarting(let meeting):
            let minutes = max(0, Int((meeting.startDate.timeIntervalSince(now) / 60).rounded(.up)))
            HudReadout("\(minutes)", unit: "min", cells: 2, color: Hud.Ink.signal)
        case .callDetected:
            HudLamp(.amber, loop: .blink)
            word(String(localized: "On a call"), lit: true)
        case .recording(let recording, let prompt):
            switch recording.microphoneState {
            case .open:
                EmptyView()
            case .closed:
                HudIcon(.micOff, size: 14).foregroundStyle(Hud.Ink.ink3)
            case .unknown:
                HudTelltale(.mic, .amber, paren: true)
                    .help("Mute state unknown")
            }
            HudLadder(level: level, quiet: prompt != nil)
        case .processing(let stage):
            HudCells(states: Self.cells(count: 4, current: stage.stepIndex))
        case .focus(let task):
            let value = NotchClosedText.focusValue(now.timeIntervalSince(task.startedAt ?? now))
            HudReadout(value.digits, unit: LocalizedStringKey(value.unit), cells: 2)
        case .tasks(let count):
            HudReadout("\(count)", unit: count == 1 ? "task" : "tasks", cells: 2)
        case .dictationListening:
            HudLadder(level: level)
        case .dictationWorking(let step, _):
            HudCells(states: Self.cells(count: 3, current: step))
        case .dictationInserted(let summary):
            if let destination = summary.destinationWord(fallback: targetAppName) {
                HudLamp(.teal)
                word(destination, lit: true)
            }
        case .dictationFailed(let failure):
            if let accessWord = NotchClosedText.dictationFailure(failure).accessWord {
                HudStatusWord(.off(blocking: true), accessWord, color: Hud.Ink.ink1).fixedSize()
            }
        case .ready:
            HudLamp(.teal)
            word(String(localized: "Ready"), lit: true)
        case .failed:
            word(String(localized: "Failed"), lit: true)
        }
    }

    // MARK: Strip — one sentence, one meta, at most two buttons

    @ViewBuilder
    private var strip: some View {
        switch state {
        case .meetingStarting(let meeting):
            sentence(String(localized: "Starting now"), meta: NotchClosedText.venue(meeting))
            Spacer(minLength: 0)
            NotchStripKey("Later", key: "esc", size: .small) { actions.dismissStartingMeeting(meeting) }
                .keyboardShortcut(.cancelAction)
            NotchStripKey("Join", key: "↩", kind: .primary, size: .small) {
                if let url = meeting.meetingURL { actions.joinMeeting(url) }
                actions.dismissStartingMeeting(meeting)
            }
            .keyboardShortcut(.defaultAction)

        case .callDetected(_, let title):
            sentence(String(localized: "Record this call?"), meta: title)
            Spacer(minLength: 0)
            NotchStripKey("Not now", key: "esc", size: .small, action: actions.dismissPrompt)
                .keyboardShortcut(.cancelAction)
            NotchStripKey("Record", lamp: .red, key: "↩", kind: .primary, size: .small, action: actions.startRecording)
                .keyboardShortcut(.defaultAction)

        case .recording(_, .updateWaiting):
            sentence(String(localized: "Update installs after this call"), meta: nil)
            Spacer(minLength: 0)
            NotchStripKey("OK", key: "esc", size: .small, action: actions.acknowledgeUpdateDuringRecording)
                .keyboardShortcut(.cancelAction)

        case .updateReady(let version):
            sentence(String(localized: "Crenel \(version.shortVersion) is ready"),
                     meta: version.releaseNotesURL == nil ? nil : String(localized: "What’s new"))
            Spacer(minLength: 0)
            NotchStripKey("Later", key: "esc", size: .small, action: actions.dismissUpdateReady)
                .keyboardShortcut(.cancelAction)
            NotchStripKey("Restart", key: "↩", kind: .primary, size: .small, action: actions.restartToUpdate)
                .keyboardShortcut(.defaultAction)

        case .updated(let version):
            HudLamp(.teal, fires: true)
            sentence(String(localized: "You’re on Crenel \(version.shortVersion)"),
                     meta: version.changeCount.map { $0 == 1 ? String(localized: "1 change") : String(localized: "\($0) changes") })
            Spacer(minLength: 0)
            if version.releaseNotesURL != nil {
                NotchStripKey("What’s new", key: "↩", kind: .primary, size: .small) { actions.showReleaseNotes(version) }
                    .keyboardShortcut(.defaultAction)
            }

        case .recording(_, .ended):
            sentence(String(localized: "The call seems to have ended"), meta: nil)
            Spacer(minLength: 0)
            recordingEndButtons

        case .recording(_, .autoStop(let deadline)):
            let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
            sentence(String(localized: "Call ended"), meta: String(localized: "stops in"))
            HudReadout("\(seconds)", unit: "s", cells: 2, color: Hud.Ink.live)
                .accessibilityLabel("Recording stops in \(seconds) seconds")
            Spacer(minLength: 0)
            recordingEndButtons

        case .dictationListening(let text):
            NotchStreamText(text: text, showsCaret: true)
            destination

        case .dictationWorking(_, let text):
            NotchStreamText(text: text, showsCaret: false, dimmed: true)
            destination

        case .dictationInserted(let summary):
            NotchStreamText(text: summary.text, showsCaret: false)
                .padding(.trailing, summary.canUndo ? 0 : 8)
            if summary.canUndo {
                NotchStripKey("Undo", key: "⌘Z", size: .small, action: actions.undoDictation)
                    .keyboardShortcut("z", modifiers: .command)
            }

        case .dictationFailed(let failure):
            let words = NotchClosedText.dictationFailure(failure)
            sentence(words.sentence, meta: nil)
            Spacer(minLength: 0)
            switch words.fix {
            case .settings:
                NotchStripKey("Settings", glyph: .sliders, size: .small, action: actions.openSettings)
            case .allowAccess:
                NotchStripKey("Allow", kind: .primary, size: .small) { actions.allowDictationAccess(failure) }
            case .downloadModel:
                NotchStripKey("Download", size: .small, action: actions.downloadSpeechModel)
            case .none:
                EmptyView()
            }

        case .ready(let meeting, let actionItems):
            sentence(NotchClosedText.readySentence(actionItems: actionItems), meta: meeting.map(NotchClosedText.duration))
            Spacer(minLength: 0)
            NotchStripKey("Later", key: "esc", size: .small, action: actions.dismissResult)
                .keyboardShortcut(.cancelAction)
            if let meeting {
                NotchStripKey("Open", key: "↩", kind: .primary, size: .small) { actions.openStoredMeeting(meeting) }
                    .keyboardShortcut(.defaultAction)
            }

        case .failed(let failure, let meetingTitle, let audioSaved):
            // The ear already carries the failure's title when there is no meeting.
            sentence(meetingTitle == nil ? failure.message : failure.title,
                     meta: audioSaved ? String(localized: "audio is saved") : nil)
            Spacer(minLength: 0)
            if failure.recoveryAction == .openSystemSettings {
                NotchStripKey("Settings", glyph: .sliders, size: .small) { actions.recoverFromFailure(failure) }
            } else if failure.isRetryable {
                NotchStripKey("Retry", key: "↩", kind: .primary, size: .small) { actions.recoverFromFailure(failure) }
                    .keyboardShortcut(.defaultAction)
            } else {
                NotchStripKey(failure.recoveryButtonTitle, key: "↩", kind: .primary, size: .small) {
                    actions.recoverFromFailure(failure)
                }
                .keyboardShortcut(.defaultAction)
            }

        case .idle, .standby, .meeting, .recording(_, nil), .processing, .focus, .tasks,
             .updating, .updatePending, .restarting:
            EmptyView()
        }
    }

    @ViewBuilder
    private var recordingEndButtons: some View {
        NotchStripKey("Keep", key: "esc", size: .small, action: actions.continueRecording)
            .keyboardShortcut(.cancelAction)
        NotchStripKey("Stop", glyph: .stop, key: "↩", kind: .primary, size: .small, action: actions.confirmMeetingEnded)
            .keyboardShortcut(.defaultAction)
    }

    /// Where the dictated words are going.
    @ViewBuilder
    private var destination: some View {
        if let targetAppName, !targetAppName.isEmpty {
            Text(targetAppName).hud(.meta).lineLimit(1).fixedSize().padding(.trailing, 8)
        }
    }

    // MARK: Pieces

    /// Listening with more words than one line holds: the strip grows into the live size.
    private var liveText: String? {
        guard case .dictationListening(let text) = state,
              NotchLiveDictation.needsLiveSize(text) else { return nil }
        return text
    }

    private var isWorking: Bool {
        if case .dictationWorking = state { return true }
        return false
    }

    /// A title in the left ear: at most 118 pt, truncated.
    private func title(_ text: String, lit: Bool) -> some View {
        Text(text)
            .hud(.label, lit ? Hud.Ink.ink1 : Hud.Ink.ink2)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Hud.Notch.earTitleMax, alignment: .leading)
            .layoutPriority(-1)
    }

    /// A short fixed word in an ear.
    private func word(_ text: String, lit: Bool) -> some View {
        Text(text).hud(.label, lit ? Hud.Ink.ink1 : Hud.Ink.ink2).lineLimit(1).fixedSize()
    }

    @ViewBuilder
    private func sentence(_ text: String, meta: String?) -> some View {
        Text(text).hud(.body, Hud.Ink.ink1).lineLimit(1).layoutPriority(1)
        if let meta, !meta.isEmpty {
            Text(meta).hud(.meta).lineLimit(1).layoutPriority(-1)
        }
    }

    /// Station cells: passed ones dim, the live one blinks, the rest ghosts.
    static func cells(count: Int, current: Int) -> [HudCells.Cell] {
        (0..<count).map { $0 < current ? .done : ($0 == current ? .current : .off) }
    }

    private var accessibilityText: String {
        switch state {
        case .idle: ""
        case .standby(.nextEvent(let meeting)):
            "Next: \(meeting.title), \(NotchClosedText.dayWord(meeting.startDate)) \(HudFormat.clock(meeting.startDate))"
        case .standby(.dictationKey(let key)): "Hold \(key) to dictate"
        case .updating(let progress):
            progress.map { "Downloading update, \(Int($0 * 100)) percent" } ?? "Preparing update"
        case .updateReady(let version): "Crenel \(version.shortVersion) is ready to install"
        case .updatePending(let version): "Crenel \(version.shortVersion) installs on restart"
        case .restarting: "Restarting to update"
        case .updated(let version): "Updated to Crenel \(version.shortVersion)"
        case .meeting(let agenda): NotchAgendaFormatter.accessibilityText(for: agenda)
        case .meetingStarting(let meeting): "\(meeting.title), starting now"
        case .callDetected(let clientID, _): "\(NotchClosedText.clientName(clientID)), on a call"
        case .recording(let recording, _):
            NotchAccessibilityContract.recordingDurationLabel(HudFormat.elapsed(now.timeIntervalSince(recording.startedAt)))
                + ". " + NotchAccessibilityContract.microphoneGateLabel(recording.microphoneState)
        case .processing(let stage): "Processing: \(stage.shortTitle)"
        case .focus(let task): "Working on \(task.title)"
        case .tasks(let count): "\(count) open tasks"
        case .dictationListening: "Dictation listening"
        case .dictationWorking: "Dictation writing"
        case .dictationInserted(let summary): summary.message
        case .dictationFailed(let failure): failure.message
        case .ready(let meeting, let actionItems):
            "\(meeting?.title ?? "Meeting"), \(NotchClosedText.readySentence(actionItems: actionItems).lowercased())"
        case .failed(let failure, let title, _): "\(title ?? failure.title), failed"
        }
    }
}

// MARK: - Strip line

/// A key on the strip: a `HudButton` that keeps its full width — the sentence beside it
/// gives way, never the button.
struct NotchStripKey: View {
    private let button: HudButton

    init(_ title: LocalizedStringKey, glyph: HudGlyph? = nil, lamp: Hud.LampColor? = nil, key: String? = nil,
         kind: HudButtonStyle.Kind = .secondary, size: HudButtonStyle.Size = .small, action: @escaping () -> Void) {
        button = HudButton(title, glyph: glyph, lamp: lamp, key: key, kind: kind, size: size, action: action)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, glyph: HudGlyph? = nil, lamp: Hud.LampColor? = nil, key: String? = nil,
                            kind: HudButtonStyle.Kind = .secondary, size: HudButtonStyle.Size = .small,
                            action: @escaping () -> Void) {
        button = HudButton(title, glyph: glyph, lamp: lamp, key: key, kind: kind, size: size, action: action)
    }

    var body: some View {
        button.fixedSize().layoutPriority(2)
    }
}

/// The one line under the ears (`.strip`): 38 pt, radius 12, a sentence on the left and
/// the buttons at the trailing edge.
struct NotchStripLine<Content: View>: View {
    /// A scanner sweeps the line while its text is being worked on.
    var scanning = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudStrip()
            .hudScanner(scanning, radius: Hud.Notch.stripRadius)
    }
}

/// The live size of dictation: between the strip and the open panel. The orb breathes
/// with the voice on the left; the transcript runs up to three lines, newest at the
/// bottom, the oldest words leaving at the top.
struct NotchLiveDictation: View {
    let text: String
    var level: Double = 0

    static let maxLines = 3
    /// About what one strip line holds beside the destination app.
    static let oneLineCharacters = 46

    static func needsLiveSize(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count > oneLineCharacters
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CrenelOrb(top: .white, bottom: Hud.Ink.ink3, level: level, density: 12)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .background(Circle().fill(Hud.Ink.field))
            Text("\(Self.tail(text)) \(Text(verbatim: "▏").foregroundStyle(Hud.Ink.ink2))")
                .hud(.body, Hud.Ink.ink1)
                .lineLimit(Self.maxLines)
                .truncationMode(.head)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10).padding(.trailing, 10).padding(.vertical, 9)
        .frame(minHeight: Hud.Notch.stripHeight)
        .background(RoundedRectangle(cornerRadius: Hud.Notch.stripRadius, style: .continuous).fill(Hud.Ink.field))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    /// The last words that fit in three lines: whole words, so the head never starts mid-word.
    static func tail(_ text: String, limit: Int = oneLineCharacters * maxLines) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let suffix = trimmed.suffix(limit)
        guard let space = suffix.firstIndex(of: " ") else { return "…" + suffix }
        return "…" + suffix[suffix.index(after: space)...]
    }
}

/// Dictated words as they arrive (`.stream`): pinned to the right, the oldest fading out
/// on the left, a lit caret after the newest.
struct NotchStreamText: View {
    let text: String
    var showsCaret = false
    /// The text dims while it is being cleaned up.
    var dimmed = false

    var body: some View {
        // The row keeps its width; the words overflow to the left and are clipped there.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                HStack(alignment: .center, spacing: 3) {
                    Text(text)
                        .hud(.body, dimmed ? Hud.Ink.ink3 : Hud.Ink.ink1)
                        .lineLimit(1)
                        .fixedSize()
                    if showsCaret { HudCaret() }
                }
            }
            .clipped()
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

// MARK: - Helpers

private extension Meeting {
    /// The kind of thing it is: a call, a place, or just a calendar item.
    var notchGlyph: HudGlyph {
        if meetingURL != nil { return .video }
        if location?.isEmpty == false { return .place }
        return .calendar
    }
}

private extension DictationResultSummary {
    var earWord: String {
        switch delivery {
        case .insertedViaAccessibility, .insertedViaPaste: String(localized: "Inserted")
        case .replacedSelection: String(localized: "Replaced")
        case .taskCreated: String(localized: "Task added")
        }
    }

    /// Where the words went: the app's name, or Tasks.
    func destinationWord(fallback: String?) -> String? {
        if delivery == .taskCreated { return String(localized: "Tasks") }
        if let appName, !appName.isEmpty { return appName }
        return fallback
    }
}
