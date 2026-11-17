import SwiftUI

struct NotchPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    let onCopyText: (String) -> Void
    let onExportMarkdown: (String, StoredMeeting) -> Void
    let onRevealAudio: (URL) -> Void
    let onDeleteStoredMeeting: (StoredMeeting) -> Void
    let onRetryStoredMeeting: (StoredMeeting) -> Void
    let onOpenRecovery: () -> Void
    let onTogglePin: () -> Void
    let onRelaunchApplication: () -> Void
    let analysisActions: MeetingAnalysisActions

    init(
        onRequestCalendarAccess: @escaping () -> Void = {},
        onOpenMeetingURL: @escaping (URL) -> Void = { _ in },
        onStartRecording: @escaping () -> Void = {},
        onStopRecording: @escaping () -> Void = {},
        onToggleMeetingMicrophone: @escaping () -> Void = {},
        onDismissMeetingPrompt: @escaping () -> Void = {},
        onContinueRecording: @escaping () -> Void = {},
        onConfirmMeetingEnded: @escaping () -> Void = {},
        onCancelFlow: @escaping () -> Void = {},
        onRecoverFromFailure: @escaping (AppFailure) -> Void = { _ in },
        onOpenStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
        onCopyText: @escaping (String) -> Void = { _ in },
        onExportMarkdown: @escaping (String, StoredMeeting) -> Void = { _, _ in },
        onRevealAudio: @escaping (URL) -> Void = { _ in },
        onDeleteStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
        onRetryStoredMeeting: @escaping (StoredMeeting) -> Void = { _ in },
        onOpenRecovery: @escaping () -> Void = {},
        onTogglePin: @escaping () -> Void = {},
        onRelaunchApplication: @escaping () -> Void = {},
        analysisActions: MeetingAnalysisActions = MeetingAnalysisActions(),
        showsHistory: Bool = false
    ) {
        _showsHistory = State(initialValue: showsHistory)
        self.analysisActions = analysisActions
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
        self.onCopyText = onCopyText
        self.onExportMarkdown = onExportMarkdown
        self.onRevealAudio = onRevealAudio
        self.onDeleteStoredMeeting = onDeleteStoredMeeting
        self.onRetryStoredMeeting = onRetryStoredMeeting
        self.onOpenRecovery = onOpenRecovery
        self.onTogglePin = onTogglePin
        self.onRelaunchApplication = onRelaunchApplication
    }

    @Environment(\.crenelNotchMetrics) private var notchMetrics
    @Environment(\.crenelNotchOpenedAt) private var notchOpenedAt
    /// The Recordings page is showing instead of the selected tab.
    @State private var showsHistory: Bool

    var body: some View {
        let layout = NotchPanelLayout(
            availableSize: appState.notchPanelAvailableSize,
            preferredWidth: Hud.Notch.openWidth
        )

        VStack(alignment: .leading, spacing: 0) {
            // The camera band is the chrome. It sits outside the scroll view, so it stays
            // in place while the content scrolls.
            Group {
                if let detail = appState.presentedMeetingDetail {
                    MeetingDetailToolbar(
                        content: detail,
                        onBack: appState.dismissMeetingDetail,
                        onCopyText: onCopyText
                    )
                    .padding(.horizontal, Hud.Notch.openInset)
                    .frame(minHeight: max(notchMetrics.topInset, Hud.Notch.bandHeight))
                } else {
                    NotchBand(showsHistory: $showsHistory, onTogglePin: onTogglePin)
                }
            }
            .transition(.opacity)

            // A prompt that arrives while the panel is open shows its strip line here;
            // with the panel closed it is the strip under the ears.
            NotchPanelPromptLine(actions: promptActions)

            NotchPanelScrollableContent(
                maximumHeight: layout.maximumContentHeight,
                bottomContentInset: 0
            ) {
                ZStack(alignment: .top) {
                    if let detail = appState.presentedMeetingDetail {
                        MeetingDetailView(
                            content: detail,
                            onCopyText: onCopyText,
                            onExportMarkdown: { markdown in
                                onExportMarkdown(markdown, detail.meeting)
                            },
                            onRevealAudio: onRevealAudio,
                            onRetry: onRetryStoredMeeting,
                            onDelete: onDeleteStoredMeeting,
                            analysisActions: analysisActions,
                            isProcessing: appState.processingJobs.contains { $0.meetingID == detail.id && $0.state != .failed },
                            importedActionIDs: Set(appState.tasks.filter { $0.sourceMeetingID == detail.id }.compactMap(\.sourceActionID))
                        )
                        .id(detail.id)
                        .transition(.opacity)
                    } else if showsHistory {
                        VStack(alignment: .leading, spacing: Hud.Space.x3) {
                            if let recoverySummary = appState.recordingRecoverySummary {
                                RecordingRecoveryNoticeView(
                                    summary: recoverySummary,
                                    onOpenRecovery: onOpenRecovery,
                                    onDismiss: appState.dismissRecordingRecoverySummary
                                )
                            }
                            RecentMeetingsList(
                                meetings: Array(appState.storedMeetings.prefix(30)),
                                onOpen: onOpenStoredMeeting,
                                onDelete: onDeleteStoredMeeting,
                                onRetry: onRetryStoredMeeting
                            )
                        }
                        .transition(.opacity)
                    } else {
                        switch appState.selectedTab {
                        case .meetings:
                            MeetingStatusView(
                                onRequestCalendarAccess: onRequestCalendarAccess,
                                onOpenMeetingURL: onOpenMeetingURL,
                                onStartRecording: onStartRecording,
                                onStopRecording: onStopRecording,
                                onToggleMeetingMicrophone: onToggleMeetingMicrophone,
                                onDismissMeetingPrompt: onDismissMeetingPrompt,
                                onContinueRecording: onContinueRecording,
                                onConfirmMeetingEnded: onConfirmMeetingEnded,
                                onCancelFlow: onCancelFlow,
                                onRecoverFromFailure: onRecoverFromFailure,
                                onOpenStoredMeeting: onOpenStoredMeeting,
                                onRelaunchApplication: onRelaunchApplication
                            )
                            .transition(.opacity)
                        case .tasks:
                            TasksView()
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                // `#nc.open`: content sits 14 pt from the walls; rows add their own inset.
                .padding(.horizontal, Hud.Notch.openInset)
            }
            .padding(.top, NotchPanelLayout.bandGap)
        }
        .padding(.bottom, Hud.Notch.openBottom)
        .frame(width: layout.width)
        .environment(\.colorScheme, .dark)
        // Gauges inside sweep once when the panel opens from closed, not on tab changes.
        .environment(\.notchPanelIgnites, NotchPanelIgnition.ignites(openedAt: notchOpenedAt, reduceMotion: reduceMotion))
        .onMoveCommand { direction in
            guard appState.presentedMeetingDetail == nil else { return }
            switch direction {
            case .left:
                showsHistory = false
                appState.selectPanelTab(offset: -1)
            case .right:
                showsHistory = false
                appState.selectPanelTab(offset: 1)
            default:
                break
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in showsHistory = false }
        .animation(motion(Hud.Motion.content), value: appState.presentedMeetingDetail?.id)
        .animation(motion(Hud.Motion.content), value: appState.selectedTab)
        .animation(motion(Hud.Motion.content), value: showsHistory)
    }

    private var promptActions: NotchStripActions {
        NotchStripActions(
            startRecording: onStartRecording,
            dismissPrompt: onDismissMeetingPrompt,
            continueRecording: onContinueRecording,
            confirmMeetingEnded: onConfirmMeetingEnded
        )
    }

    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : animation
    }
}

/// The strip's line inside the open panel: a call was detected, or a recorded call seems
/// to have ended, while the panel was already open.
private struct NotchPanelPromptLine: View {
    @EnvironmentObject private var appState: AppState
    let actions: NotchStripActions

    var body: some View {
        if appState.meetingLifecyclePrompt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let state = appState.closedNotchState(now: context.date)
                if state.isPrompt {
                    NotchClosedView(state: state, now: context.date, actions: actions, showsEars: false)
                        .padding(.horizontal, Hud.Notch.openInset)
                        .padding(.top, NotchPanelLayout.bandGap)
                }
            }
            .transition(.opacity)
        }
    }
}

private extension NotchClosedState {
    var isPrompt: Bool {
        switch self {
        case .callDetected: true
        case .recording(_, let prompt): prompt != nil
        default: false
        }
    }
}

/// Shows short content at its natural height and scrolls content taller than the cap.
/// One scroll container for all content, so view state (an open task card, a typed
/// draft) survives content growing past the cap.
struct NotchPanelScrollableContent<Content: View>: View {
    let maximumHeight: CGFloat
    let bottomContentInset: CGFloat
    let content: Content
    @State private var contentHeight: CGFloat?

    init(
        maximumHeight: CGFloat,
        bottomContentInset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.maximumHeight = maximumHeight
        self.bottomContentInset = bottomContentInset
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, bottomContentInset)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    contentHeight = height
                }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight.map { min($0, maximumHeight) })
        .frame(maxHeight: maximumHeight)
    }
}

enum DictationStatusText {
    static func title(for state: DictationState) -> String {
        switch state {
        case .idle: "Dictation ready"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .refining: "Refining"
        case .inserting: "Inserting"
        case .inserted(let summary): summary.message
        case .failed(let failure): failure.message
        }
    }

    static func short(for failure: DictationFailure) -> String {
        switch failure {
        case .noFocusedTextField: "Copied"
        case .speechAssetsDownloading, .speechAssetsMissing: "Downloading"
        case .accessibilityPermissionMissing, .inputMonitoringPermissionMissing, .microphonePermissionDenied: "Needs access"
        case .tooShort, .noSpeechDetected: "No speech"
        default: "Failed"
        }
    }
}

#if DEBUG
private struct NotchPanelAuditPreview: View {
    @StateObject private var appState: AppState
    let profile: NotchPreviewProfile

    init(profile: NotchPreviewProfile) {
        self.profile = profile
        let startedAt = Date().addingTimeInterval(-83)
        let initialFlow: MeetingFlowState = profile.auditFocus == .voiceOver
            ? .recording(startedAt: startedAt)
            : .idle
        let state = AppState(initialFlow: initialFlow)
        if profile.auditFocus == .keyboard {
            state.selectedTab = .tasks
        }
        if profile.auditFocus == .voiceOver {
            state.updateMeetingMicrophoneGate(
                MeetingMicrophoneGate(recordingStartedAt: startedAt)
            )
        }
        _appState = StateObject(wrappedValue: state)
    }

    var body: some View {
        NotchPanelView()
            .environmentObject(appState)
            .environment(
                \.colorScheme,
                profile.colorScheme == .light ? .light : .dark
            )
            .contrast(profile.increasedContrast ? 1.35 : 1)
            .transaction { transaction in
                if profile.reducesMotion {
                    }
            }
    }
}

#Preview("Light · Standard") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[0])
}

#Preview("Dark · Standard") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[1])
}

#Preview("Light · Increase Contrast") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[2])
}

#Preview("Dark · Reduce Motion") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[3])
}

#Preview("Keyboard · Tasks") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[4])
}

#Preview("VoiceOver · Recording") {
    NotchPanelAuditPreview(profile: NotchPreviewProfile.requiredMatrix[5])
}
#endif
