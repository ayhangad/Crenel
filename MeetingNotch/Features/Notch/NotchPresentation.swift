import AppKit
import Foundation

enum NotchCompactStatus: Equatable {
    struct RecordingStatus: Equatable {
        let startedAt: Date
        let clientID: MeetingClientID?
        let microphoneState: MeetingMicrophoneState
    }

    enum ProcessingStage: Equatable {
        case preparing
        case finalizing
        case uploading(progress: Double)
        case transcribing
        case summarizing
    }

    case dictation(DictationState)
    case recording(RecordingStatus)
    case processing(ProcessingStage)
    case completed
    case failed
    case agenda(NotchAgendaStatus)
    case focus(TaskItem)
    case tasks(count: Int)
    case idle
}

struct NotchStatusResolver {
    static func compactStatus(
        flow: MeetingFlowState,
        nextMeeting: Meeting?,
        activeTaskCount: Int,
        meetingDetection: MeetingSessionDetectionSnapshot? = nil,
        microphoneGate: MeetingMicrophoneGate? = nil,
        agendaItems: [Meeting] = [],
        focusedTask: TaskItem? = nil,
        dictation: DictationState = .idle,
        now: Date = Date()
    ) -> NotchCompactStatus {
        // Dictation is short-lived and needs immediate feedback, so it wins over everything.
        if dictation != .idle {
            return .dictation(dictation)
        }
        switch flow {
        case .recording(let startedAt):
            return .recording(
                .init(
                    startedAt: startedAt,
                    clientID: meetingDetection?.session.clientID,
                    microphoneState: microphoneGate?.state ?? .unknown
                )
            )
        case .preparingRecording:
            return .processing(.preparing)
        case .finalizingAudio:
            return .processing(.finalizing)
        case .uploading(let progress):
            return .processing(.uploading(progress: progress))
        case .transcribing:
            return .processing(.transcribing)
        case .summarizing:
            return .processing(.summarizing)
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .upcomingMeeting(let meeting):
            return .agenda(Self.agendaStatus(for: meeting, now: now))
        case .idle, .cancelled:
            let candidates = agendaItems + (nextMeeting.map { [$0] } ?? [])
            let agenda = NotchAgendaStatus.resolve(items: candidates, now: now)
            // A task being worked on wins over calm calendar items, but an item about to
            // start (or a meeting in progress) still takes the notch.
            if let focusedTask {
                if let agenda, agenda.urgency != .calm || (agenda.item.isMeetingLike && agenda.phase.isOngoing) {
                    return .agenda(agenda)
                }
                return .focus(focusedTask)
            }
            if let agenda {
                return .agenda(agenda)
            }
            if activeTaskCount > 0 {
                return .tasks(count: activeTaskCount)
            }
            return .idle
        }
    }

    private static func agendaStatus(for meeting: Meeting, now: Date) -> NotchAgendaStatus {
        let startsIn = meeting.startDate.timeIntervalSince(now)
        if startsIn > 0 {
            return NotchAgendaStatus(item: meeting, phase: .upcoming(startsIn: startsIn))
        }
        return NotchAgendaStatus(
            item: meeting,
            phase: .ongoing(remaining: max(0, meeting.endDate.timeIntervalSince(now)))
        )
    }
}

struct NotchPanelLayout: Equatable {
    static let preferredWidth: CGFloat = 600
    static let preferredDetailWidth: CGFloat = preferredWidth
    static let minimumWidth: CGFloat = 320
    static let preferredContentHeight: CGFloat = 600
    // Header, header/content gap and the panel's vertical padding remain outside the
    // scroll view. Reserve their tallest (detail) footprint before capping the viewport.
    static let fixedVerticalSpace: CGFloat = 100

    let width: CGFloat
    let maximumContentHeight: CGFloat

    init(width: CGFloat, maximumContentHeight: CGFloat) {
        self.width = width
        self.maximumContentHeight = maximumContentHeight
    }

    init(
        availableSize: CGSize,
        preferredWidth: CGFloat = Self.preferredWidth
    ) {
        let availableWidth = max(0, availableSize.width)
        let availableContentHeight = max(
            0,
            availableSize.height - Self.fixedVerticalSpace
        )
        width = min(preferredWidth, availableWidth)
        maximumContentHeight = min(Self.preferredContentHeight, availableContentHeight)
    }
}

/// Space the open notch may use inside Crenel's notch window: the window minus side
/// margins for the flare and shadow, and minus the menu-bar band the notch starts under.
struct NotchHostViewport: Equatable {
    static let horizontalMargin: CGFloat = 48
    static let bottomMargin: CGFloat = 24

    let availableSize: CGSize

    init(windowSize: CGSize, topInset: CGFloat) {
        availableSize = CGSize(
            width: max(0, windowSize.width - Self.horizontalMargin),
            height: max(0, windowSize.height - max(0, topInset) - Self.bottomMargin)
        )
    }

    @MainActor
    init(screen: NSScreen) {
        let metrics = CrenelNotchController.metrics(for: screen)
        let windowSize = CGSize(
            width: min(CrenelNotchController.windowSize.width, screen.frame.width),
            height: min(CrenelNotchController.windowSize.height, screen.frame.height * 0.85)
        )
        self.init(windowSize: windowSize, topInset: metrics.topInset)
    }
}

struct NotchTransientStatusPolicy {
    static let displayDuration: Duration = .seconds(8)

    static func shouldPresent(_ state: MeetingFlowState) -> Bool {
        switch state {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }

    static func shouldResetAfterTimeout(_ state: MeetingFlowState) -> Bool {
        if case .completed = state { return true }
        return false
    }
}

struct NotchMotionProfile: Equatable {
    let reducesMotion: Bool
    let openingDuration: Double
    let closingDuration: Double
    let conversionDuration: Double

    static func resolved(reducesMotion: Bool) -> Self {
        if reducesMotion {
            return Self(
                reducesMotion: true,
                openingDuration: 0.01,
                closingDuration: 0.01,
                conversionDuration: 0.01
            )
        }
        return Self(
            reducesMotion: false,
            openingDuration: 0.28,
            closingDuration: 0.2,
            conversionDuration: 0.3
        )
    }
}

enum NotchPreviewColorScheme: String, CaseIterable, Hashable {
    case light
    case dark
}

enum NotchPreviewAuditFocus: String, CaseIterable, Hashable {
    case appearance
    case keyboard
    case voiceOver
}

struct NotchPreviewProfile: Equatable, Hashable {
    let name: String
    let colorScheme: NotchPreviewColorScheme
    let increasedContrast: Bool
    let reducesMotion: Bool
    let auditFocus: NotchPreviewAuditFocus

    static let requiredMatrix: [Self] = [
        Self(
            name: "Light · Standard",
            colorScheme: .light,
            increasedContrast: false,
            reducesMotion: false,
            auditFocus: .appearance
        ),
        Self(
            name: "Dark · Standard",
            colorScheme: .dark,
            increasedContrast: false,
            reducesMotion: false,
            auditFocus: .appearance
        ),
        Self(
            name: "Light · Increase Contrast",
            colorScheme: .light,
            increasedContrast: true,
            reducesMotion: false,
            auditFocus: .appearance
        ),
        Self(
            name: "Dark · Reduce Motion",
            colorScheme: .dark,
            increasedContrast: false,
            reducesMotion: true,
            auditFocus: .appearance
        ),
        Self(
            name: "Keyboard · Tasks",
            colorScheme: .dark,
            increasedContrast: false,
            reducesMotion: false,
            auditFocus: .keyboard
        ),
        Self(
            name: "VoiceOver · Recording",
            colorScheme: .dark,
            increasedContrast: true,
            reducesMotion: true,
            auditFocus: .voiceOver
        )
    ]
}

enum NotchAccessibilityContract {
    static func tabLabel(_ tab: AppState.PanelTab) -> String {
        "\(tab.rawValue) tab"
    }

    static func tabShortcutDescription(_ tab: AppState.PanelTab) -> String {
        switch tab {
        case .meetings: "Command 1"
        case .tasks: "Command 2"
        }
    }

    static func recordingSessionLabel(clientID: MeetingClientID?) -> String {
        "Recording \(clientName(clientID)) session"
    }

    static func microphoneGateLabel(_ state: MeetingMicrophoneState) -> String {
        "Meeting microphone \(microphoneGateTitle(state))"
    }

    static func recordingDurationLabel(_ formattedDuration: String) -> String {
        "Recording time \(formattedDuration)"
    }

    private static func clientName(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: "Meeting"
        }
    }

    private static func microphoneGateTitle(_ state: MeetingMicrophoneState) -> String {
        switch state {
        case .open: "on"
        case .closed: "off"
        case .unknown: "unknown, kept off"
        }
    }
}
