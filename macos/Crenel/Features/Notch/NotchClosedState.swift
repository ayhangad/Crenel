import Foundation

/// What the closed notch shows: one state per block of the prototype's `tpl-closed`.
/// Compact states are two ears; strip states add one line under them.
enum NotchClosedState: Equatable {
    enum RecordingPrompt: Equatable {
        /// "The call seems to have ended" — Keep · Stop.
        case ended
        /// "Call ended, stops in N s" — red fuse, then the recording stops on its own.
        case autoStop(deadline: Date)
        /// "Update installs after this call" · OK: an update is ready, but a recording
        /// never restarts Crenel.
        case updateWaiting
    }

    /// Nothing to say: exactly the hardware notch. Only when there is no later event and
    /// no dictation key to point at.
    case idle
    /// Nothing today, but the notch still answers one question: the mark on the left, and
    /// on the right the next event on another day or the key that starts dictation.
    case standby(NotchStandby)
    /// An update downloading (0…1) or being prepared (nil): quiet ears and a teal fuse.
    case updating(progress: Double?)
    /// Strip: "Crenel 1.2 is ready" · Later · Restart.
    case updateReady(AppUpdateVersion)
    /// Ears only, after Later: the mark and a teal lamp.
    case updatePending(AppUpdateVersion)
    /// The moment before Crenel quits to be replaced.
    case restarting
    /// Strip, after relaunching on a new version: "You're on Crenel 1.2" · What's new.
    case updated(AppUpdateVersion)
    /// Next or current calendar item: later today, within the hour, 10 min or less, in
    /// progress, or on another day.
    case meeting(NotchAgendaStatus)
    /// Strip: "Starting now" · Later · Join.
    case meetingStarting(Meeting)
    /// Strip: "Record this call?" · Not now · Record.
    case callDetected(clientID: MeetingClientID?, title: String?)
    case recording(NotchCompactStatus.RecordingStatus, prompt: RecordingPrompt?)
    case processing(NotchCompactStatus.ProcessingStage)
    case focus(TaskItem)
    case tasks(count: Int)
    /// Strip: the words as they are spoken.
    case dictationListening(text: String)
    /// Strip: the text dims under a scanner. `step` 0…2: transcribing, refining, inserting.
    case dictationWorking(step: Int, text: String)
    /// Strip: what was written and where.
    case dictationInserted(DictationResultSummary)
    /// Strip: a short reason and one fix.
    case dictationFailed(DictationFailure)
    /// Strip: "Notes and 3 action items" · Later · Open. `actionItems` is nil when unknown.
    case ready(StoredMeeting?, actionItems: Int?)
    /// Strip: reason · Retry.
    case failed(AppFailure, title: String?, audioSaved: Bool)

    /// Strip states drop one line under the ears and never open the panel on hover.
    var isStrip: Bool {
        switch self {
        case .idle, .standby, .meeting, .processing, .focus, .tasks, .updating, .updatePending, .restarting:
            false
        case .updateReady, .updated:
            true
        case .recording(_, let prompt):
            prompt != nil
        case .meetingStarting, .callDetected, .dictationListening, .dictationWorking, .dictationInserted,
             .dictationFailed, .ready, .failed:
            true
        }
    }

    /// Changes only when the kind of state changes, not on every tick of a countdown.
    var identity: String {
        switch self {
        case .idle: "idle"
        case .standby(let standby): "standby.\(standby.kind)"
        case .updating(let progress): progress == nil ? "update.preparing" : "update.downloading"
        case .updateReady: "update.ready"
        case .updatePending: "update.pending"
        case .restarting: "update.restarting"
        case .updated: "update.updated"
        case .meeting(let agenda): "meeting.\(agenda.item.id).\(NotchMeetingEar(agenda).kind)"
        case .meetingStarting(let meeting): "starting.\(meeting.id)"
        case .callDetected: "call"
        case .recording(_, let prompt):
            switch prompt {
            case nil: "recording"
            case .ended: "recording.ended"
            case .autoStop: "recording.autostop"
            case .updateWaiting: "recording.update"
            }
        case .processing(let stage): "processing.\(stage.stepIndex)"
        case .focus(let task): "focus.\(task.id)"
        case .tasks: "tasks"
        case .dictationListening: "dictation.listening"
        case .dictationWorking: "dictation.working"
        case .dictationInserted: "dictation.inserted"
        case .dictationFailed: "dictation.failed"
        case .ready: "ready"
        case .failed: "failed"
        }
    }
}

/// What the idle notch points at.
enum NotchStandby: Equatable {
    /// The next timed event, more than the agenda's horizon away (usually another day).
    case nextEvent(Meeting)
    /// The key that starts dictation: "fn", "⌥", "⌘".
    case dictationKey(String)

    var kind: String {
        switch self {
        case .nextEvent(let meeting): "event.\(meeting.id)"
        case .dictationKey: "dictation"
        }
    }
}

// MARK: - Resolving

/// Everything the closed notch needs to pick its state. Pure, so every state can be
/// tested and rendered without a running app.
struct NotchClosedInput {
    var status: NotchCompactStatus
    var prompt: MeetingLifecyclePrompt?
    /// Calendar title of the call the recording offer is about, when it is known.
    var detectedMeetingTitle: String?
    var partialTranscript = ""
    var failure: AppFailure?
    var completedMeeting: StoredMeeting?
    /// Action items in the completed meeting's notes, when they are known.
    var completedActionItems: Int?
    var lastStoredMeeting: StoredMeeting?
    /// "Later" was pressed on this meeting's "Starting now" strip.
    var dismissedStartingMeetingID: UUID?
    /// Calendar items, for the idle notch's next event beyond the agenda's horizon.
    var upcomingItems: [Meeting] = []
    /// The key that starts dictation, when dictation is on.
    var dictationKeyHint: String?
    var update: AppUpdatePhase = .idle
    var updateNotices = AppUpdateNotices()
    /// Just relaunched on a new version.
    var justUpdatedTo: AppUpdateVersion?
    var now = Date()
}

enum NotchClosedResolver {
    /// The "Starting now" strip shows from a minute before the start until this long after.
    static let startingWindowAfterStart: TimeInterval = 2 * 60

    static func state(_ input: NotchClosedInput) -> NotchClosedState {
        // Dictation is short-lived and needs immediate feedback, so it wins.
        if case .dictation(let dictation) = input.status {
            switch dictation {
            case .listening: return .dictationListening(text: input.partialTranscript)
            case .transcribing: return .dictationWorking(step: 0, text: input.partialTranscript)
            case .refining: return .dictationWorking(step: 1, text: input.partialTranscript)
            case .inserting: return .dictationWorking(step: 2, text: input.partialTranscript)
            case .inserted(let summary): return .dictationInserted(summary)
            case .failed(let failure): return .dictationFailed(failure)
            case .idle: return .idle
            }
        }

        if case .recording(let recording) = input.status {
            switch input.prompt {
            case .endConfirmation: return .recording(recording, prompt: .ended)
            case .autoStop(_, _, let deadline): return .recording(recording, prompt: .autoStop(deadline: deadline))
            case .recordingOffer, nil:
                if case .ready(let version) = input.update, !input.updateNotices.recordingDismissed(version) {
                    return .recording(recording, prompt: .updateWaiting)
                }
                return .recording(recording, prompt: nil)
            }
        }

        // Restart was chosen: nothing else matters for the second Crenel has left.
        if case .restarting = input.update { return .restarting }

        // A call was detected: the question stays until it is answered or the call ends.
        if case .recordingOffer(_, let clientID) = input.prompt {
            return .callDetected(clientID: clientID, title: input.detectedMeetingTitle)
        }

        switch input.status {
        case .dictation, .recording:
            return .idle
        case .idle:
            if let notice = updateNotice(input) { return notice }
            if let quiet = updateQuiet(input) { return quiet }
            return standby(input).map(NotchClosedState.standby) ?? .idle
        case .processing(let stage):
            return .processing(stage)
        case .completed:
            return .ready(input.completedMeeting, actionItems: input.completedActionItems)
        case .failed:
            guard let failure = input.failure else { return .idle }
            // Only failures after the recording was stored can promise the audio is safe.
            let afterSaving = failure.isAfterRecordingSaved && input.lastStoredMeeting != nil
            return .failed(
                failure,
                title: afterSaving ? input.lastStoredMeeting?.title : nil,
                audioSaved: afterSaving
            )
        case .agenda(let agenda):
            if isStartingNow(agenda, dismissedID: input.dismissedStartingMeetingID, now: input.now) {
                return .meetingStarting(agenda.item)
            }
            if let notice = updateNotice(input) { return notice }
            return .meeting(agenda)
        case .focus(let task):
            if let notice = updateNotice(input) { return notice }
            return .focus(task)
        case .tasks(let count):
            if let notice = updateNotice(input) { return notice }
            if let quiet = updateQuiet(input) { return quiet }
            return .tasks(count: count)
        }
    }

    /// Strips about updates: "Updated" after a relaunch, then "ready" until Later.
    static func updateNotice(_ input: NotchClosedInput) -> NotchClosedState? {
        if let version = input.justUpdatedTo { return .updated(version) }
        if case .ready(let version) = input.update, !input.updateNotices.readyDismissed(version) {
            return .updateReady(version)
        }
        return nil
    }

    /// Quiet update ears, only where the notch has nothing more useful to say.
    static func updateQuiet(_ input: NotchClosedInput) -> NotchClosedState? {
        switch input.update {
        case .downloading(_, let progress): .updating(progress: progress)
        case .preparing: .updating(progress: nil)
        case .ready(let version): .updatePending(version)
        case .idle, .restarting: nil
        }
    }

    /// Nothing today and no tasks: the next timed event, else the dictation key.
    static func standby(_ input: NotchClosedInput) -> NotchStandby? {
        let next = input.upcomingItems
            .filter { !$0.isAllDay && $0.startDate > input.now }
            .min { $0.startDate < $1.startDate }
        if let next { return .nextEvent(next) }
        if let key = input.dictationKeyHint { return .dictationKey(key) }
        return nil
    }

    /// A meeting with a link, about to start or just started, that was not put off.
    static func isStartingNow(_ agenda: NotchAgendaStatus, dismissedID: UUID?, now: Date) -> Bool {
        let meeting = agenda.item
        guard meeting.meetingURL != nil, meeting.isMeetingLike, meeting.id != dismissedID else { return false }
        switch agenda.phase {
        case .upcoming(let startsIn):
            return startsIn <= 60
        case .ongoing:
            return now.timeIntervalSince(meeting.startDate) <= startingWindowAfterStart
        }
    }
}

private extension AppFailure {
    /// Upload, transcription and summary failures happen after the audio was written.
    var isAfterRecordingSaved: Bool {
        switch category {
        case .network, .provider, .decoding: true
        case .permission, .recording, .fileSystem, .unknown: false
        }
    }
}

// MARK: - Meeting ears

/// How a calendar item reads in the ears: which of the five meeting states it is, the
/// one number, and how much fuse is left.
struct NotchMeetingEar: Equatable {
    enum Kind: String, Equatable {
        /// Today, more than an hour away: time left ("2h 37m").
        case later
        /// Within the hour: minutes, white fuse.
        case hour
        /// 10 minutes or less: amber minutes, amber fuse over the last 10 minutes.
        case urgent
        /// In progress: minutes left, fuse is the remaining share.
        case live
        /// Another day: day word and start time.
        case otherDay
    }

    let kind: Kind
    /// Whole minutes: until the start (rounded up), or left of a meeting in progress.
    let minutes: Int
    let fuse: CrenelNotchFuse?

    init(_ agenda: NotchAgendaStatus, calendar: Calendar = .current, now: Date = Date()) {
        switch agenda.phase {
        case .ongoing(let remaining):
            kind = .live
            minutes = max(0, Int((remaining / 60).rounded(.up)))
            let duration = max(60, agenda.item.endDate.timeIntervalSince(agenda.item.startDate))
            fuse = CrenelNotchFuse(fraction: min(1, max(0, remaining / duration)), tone: .amber)
        case .upcoming(let startsIn):
            minutes = max(0, Int((startsIn / 60).rounded(.up)))
            if startsIn <= 10 * 60 {
                kind = .urgent
                fuse = CrenelNotchFuse(fraction: min(1, max(0, startsIn / 600)), tone: .amber)
            } else if startsIn <= 60 * 60 {
                kind = .hour
                fuse = CrenelNotchFuse(fraction: min(1, max(0, startsIn / 3_600)), tone: .white)
            } else if calendar.isDate(agenda.item.startDate, inSameDayAs: now) {
                kind = .later
                fuse = nil
            } else {
                kind = .otherDay
                fuse = nil
            }
        }
    }
}

extension NotchClosedState {
    /// The bottom edge as a fuse for this state, if it has one.
    func fuse(now: Date) -> CrenelNotchFuse? {
        switch self {
        case .meeting(let agenda):
            return NotchMeetingEar(agenda, now: now).fuse
        case .meetingStarting(let meeting):
            // Full while it counts down the last minute, then burns with the meeting.
            let elapsed = now.timeIntervalSince(meeting.startDate)
            guard elapsed > 0 else { return CrenelNotchFuse(fraction: 1, tone: .amber) }
            let duration = max(60, meeting.endDate.timeIntervalSince(meeting.startDate))
            return CrenelNotchFuse(fraction: min(1, max(0, 1 - elapsed / duration)), tone: .amber)
        case .updating(let progress):
            return CrenelNotchFuse(fraction: progress ?? 1, tone: .teal)
        case .restarting:
            return CrenelNotchFuse(fraction: 1, tone: .teal)
        case .recording(_, .autoStop(let deadline)):
            let total = max(1, MeetingSessionLifecyclePolicy.autoStopCountdown)
            return CrenelNotchFuse(fraction: min(1, max(0, deadline.timeIntervalSince(now) / total)), tone: .red)
        default:
            return nil
        }
    }

    func traits(now: Date) -> CrenelNotchClosedTraits {
        CrenelNotchClosedTraits(isStrip: isStrip, fuse: fuse(now: now))
    }
}

// MARK: - Words

enum NotchClosedText {
    static func clientName(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: String(localized: "Call")
        }
    }

    /// The call service or the place, in one or two words.
    static func venue(_ meeting: Meeting) -> String? {
        if let host = meeting.meetingURL?.host()?.lowercased() {
            if host.contains("meet.google") { return "Google Meet" }
            if host.contains("zoom") { return "Zoom" }
            if host.contains("teams") { return "Teams" }
            if host.contains("webex") { return "Webex" }
            return String(localized: "Video call")
        }
        if let location = meeting.location, !location.isEmpty { return location }
        return meeting.calendarTitle
    }

    /// "Wed" — the day word beside a start time on another day.
    static func dayWord(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// The ready strip's sentence: "Notes and 3 action items", "Notes and 1 action item",
    /// or "Notes are ready" when there are none or the count is unknown.
    static func readySentence(actionItems: Int?) -> String {
        switch actionItems ?? 0 {
        case ...0: String(localized: "Notes are ready")
        case 1: String(localized: "Notes and 1 action item")
        case let count: String(localized: "Notes and \(count) action items")
        }
    }

    /// Whole minutes of a stored meeting: "48 min".
    static func duration(_ meeting: StoredMeeting) -> String {
        let minutes = max(1, Int((meeting.endedAt.timeIntervalSince(meeting.startedAt) / 60).rounded()))
        return String(localized: "\(minutes) min")
    }

    /// Time spent on a task: minutes under 100, then hours and minutes.
    static func focusValue(_ interval: TimeInterval) -> (digits: String, unit: String) {
        let minutes = max(1, Int(interval / 60))
        if minutes < 100 { return ("\(minutes)", "min") }
        return (String(format: "%d:%02d", minutes / 60, minutes % 60), "h")
    }

    struct DictationFailureWords: Equatable {
        enum Fix: Equatable {
            case none
            case settings
            case downloadModel
        }

        /// Left ear.
        let reason: String
        /// Right ear, with the "access off" octagon; nil when it is not a permission.
        let accessWord: String?
        /// The strip's sentence.
        let sentence: String
        let fix: Fix
    }

    static func dictationFailure(_ failure: DictationFailure) -> DictationFailureWords {
        switch failure {
        case .microphonePermissionDenied:
            .init(reason: String(localized: "Can’t hear you"), accessWord: String(localized: "Mic off"),
                  sentence: String(localized: "Crenel needs the microphone"), fix: .settings)
        case .microphoneUnavailable:
            .init(reason: String(localized: "Can’t hear you"), accessWord: nil,
                  sentence: failure.message, fix: .settings)
        case .inputMonitoringPermissionMissing:
            .init(reason: String(localized: "Needs access"), accessWord: String(localized: "Access off"),
                  sentence: String(localized: "The shortcut needs Input Monitoring"), fix: .settings)
        case .accessibilityPermissionMissing:
            .init(reason: String(localized: "Copied"), accessWord: String(localized: "Access off"),
                  sentence: String(localized: "Crenel needs Accessibility to type for you"), fix: .settings)
        case .speechAssetsMissing:
            .init(reason: String(localized: "Downloading model"), accessWord: nil,
                  sentence: String(localized: "The speech model isn’t on this Mac yet"), fix: .downloadModel)
        case .speechAssetsDownloading:
            .init(reason: String(localized: "Downloading model"), accessWord: nil,
                  sentence: String(localized: "Try again when the download finishes"), fix: .none)
        case .clipboardSnapshotUnavailable, .targetChanged, .noFocusedTextField, .insertionFailed:
            .init(reason: String(localized: "Copied"), accessWord: nil, sentence: failure.message, fix: .none)
        case .tooShort, .noSpeechDetected:
            .init(reason: String(localized: "No speech"), accessWord: nil, sentence: failure.message, fix: .none)
        case .unsupportedLocale, .secureTextField, .sessionTooLong, .audioOverrun, .transcriptionFailed:
            .init(reason: String(localized: "Dictation failed"), accessWord: nil, sentence: failure.message, fix: .none)
        case .undoFailed:
            .init(reason: String(localized: "Not undone"), accessWord: nil, sentence: failure.message, fix: .none)
        }
    }
}
