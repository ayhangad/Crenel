import Foundation

enum NotchCompactStatus: Equatable {
    enum ProcessingStage: Equatable {
        case preparing
        case finalizing
        case uploading(progress: Double)
        case transcribing
        case summarizing
    }

    case recording(startedAt: Date)
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
        activeTaskCount: Int
    ) -> NotchCompactStatus {
        switch flow {
        case .recording(let startedAt):
            return .recording(startedAt: startedAt)
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
