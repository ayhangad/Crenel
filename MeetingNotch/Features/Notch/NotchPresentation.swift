import DynamicNotchKit
import Foundation

enum NotchShadowPolicy {
    // DynamicNotchKit's window reserves 15 pt for the external shadow. Its optional
    // hover effect grows the shadow radius to 20 pt and gets clipped at the panel edge.
    static let hoverBehavior: DynamicNotchHoverBehavior = [.keepVisible]
}

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

    case recording(RecordingStatus)
    case processing(ProcessingStage)
    case completed
    case failed
    case upcoming(startDate: Date)
    case tasks(count: Int)
    case idle
}

struct NotchStatusResolver {
    static func compactStatus(
        flow: MeetingFlowState,
        nextMeeting: Meeting?,
        activeTaskCount: Int,
        meetingDetection: MeetingSessionDetectionSnapshot? = nil,
        microphoneGate: MeetingMicrophoneGate? = nil
    ) -> NotchCompactStatus {
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
            return .upcoming(startDate: meeting.startDate)
        case .idle, .cancelled:
            if let nextMeeting {
                return .upcoming(startDate: nextMeeting.startDate)
            }
            if activeTaskCount > 0 {
                return .tasks(count: activeTaskCount)
            }
            return .idle
        }
    }
}

struct NotchPanelLayout: Equatable {
    static let preferredWidth: CGFloat = 424
    static let preferredDetailWidth: CGFloat = 520
    static let minimumWidth: CGFloat = 320
    static let preferredContentHeight: CGFloat = 600
    static let minimumContentHeight: CGFloat = 200

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
        let availableWidth = max(0, availableSize.width - 32)
        let availableContentHeight = max(0, availableSize.height - 150)
        width = min(preferredWidth, availableWidth)
        maximumContentHeight = min(Self.preferredContentHeight, availableContentHeight)
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
        "\(tab.rawValue) sekmesi"
    }

    static func tabShortcutDescription(_ tab: AppState.PanelTab) -> String {
        switch tab {
        case .meetings: "Command 1"
        case .tasks: "Command 2"
        }
    }

    static func recordingSessionLabel(clientID: MeetingClientID?) -> String {
        "\(clientName(clientID)) oturumu kaydediliyor"
    }

    static func microphoneGateLabel(_ state: MeetingMicrophoneState) -> String {
        "Toplantı mikrofonu \(microphoneGateTitle(state))"
    }

    static func recordingDurationLabel(_ formattedDuration: String) -> String {
        "Kayıt süresi \(formattedDuration)"
    }

    private static func clientName(_ clientID: MeetingClientID?) -> String {
        switch clientID {
        case .zoom: "Zoom"
        case .googleMeetChrome: "Google Meet"
        case .unsupported, nil: "Toplantı"
        }
    }

    private static func microphoneGateTitle(_ state: MeetingMicrophoneState) -> String {
        switch state {
        case .open: "açık"
        case .closed: "kapalı"
        case .unknown: "bilinmiyor, güvenli kapalı"
        }
    }
}
