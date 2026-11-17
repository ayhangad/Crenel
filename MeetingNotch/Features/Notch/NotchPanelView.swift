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
        analysisActions: MeetingAnalysisActions = MeetingAnalysisActions()
    ) {
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
    @State private var showsHistory = false

    var body: some View {
        let showsDetail = appState.presentedMeetingDetail != nil
        let layout = NotchPanelLayout(
            availableSize: appState.notchPanelAvailableSize,
            preferredWidth: Hud.Size.panelWidth
        )

        VStack(alignment: .leading, spacing: Hud.Space.x4) {
            Group {
                if let detail = appState.presentedMeetingDetail {
                    MeetingDetailToolbar(
                        content: detail,
                        onBack: appState.dismissMeetingDetail,
                        onCopyText: onCopyText
                    )
                } else {
                    NotchToolbar(showsHistory: $showsHistory, onTogglePin: onTogglePin)
                }
            }
            .transition(.opacity)

            NotchPanelScrollableContent(
                maximumHeight: layout.maximumContentHeight,
                bottomContentInset: showsDetail ? Hud.Space.x4 : 0
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
                        .transition(.opacity.combined(with: .offset(x: 14)))
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
                        .transition(.opacity.combined(with: .offset(x: -14)))
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
                            .transition(tabTransition(for: .meetings))
                        case .tasks:
                            TasksView()
                                .transition(tabTransition(for: .tasks))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        // Clear the menu-bar band (and camera housing) the notch starts under. Text sits
        // `panelInset` from the walls; hover fills reach `rowInset` beyond the text.
        .padding(.top, notchMetrics.topInset + Hud.Space.x2)
        .padding(.horizontal, Hud.Size.panelInset - Hud.Size.rowInset)
        .padding(.bottom, Hud.Space.x3)
        .frame(width: layout.width)
        .environment(\.colorScheme, .dark)
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
        .animation(motion(Hud.Motion.change), value: appState.presentedMeetingDetail?.id)
        .animation(motion(Hud.Motion.change), value: appState.selectedTab)
        .animation(motion(Hud.Motion.change), value: showsHistory)
    }

    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : animation
    }

    /// Tabs slide in from the side they sit on.
    private func tabTransition(for tab: AppState.PanelTab) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(x: tab == .meetings ? -14 : 14))
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

/// One toolbar: the two surfaces centred under the camera, history on the left, window
/// controls on the right.
private struct NotchToolbar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showsHistory: Bool
    let onTogglePin: () -> Void

    var body: some View {
        ZStack {
            HudTabs(
                items: [
                    .init(tab: AppState.PanelTab.meetings, glyph: .calendar, title: AppState.PanelTab.meetings.title),
                    .init(tab: .tasks, glyph: .queue, title: AppState.PanelTab.tasks.title,
                          badge: appState.activeTaskCount > 0 ? appState.activeTaskCount : nil)
                ],
                selection: Binding(
                    get: { appState.selectedTab },
                    set: { tab in
                        showsHistory = false
                        appState.selectedTab = tab
                    }
                )
            )
            .background {
                // ⌘1 / ⌘2 switch surfaces.
                ForEach(AppState.PanelTab.allCases) { tab in
                    Button("") {
                        showsHistory = false
                        appState.selectedTab = tab
                    }
                    .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Panel tabs")

            HStack(spacing: 2) {
                Button {
                    showsHistory.toggle()
                } label: {
                    HudIcon(.history)
                }
                .buttonStyle(HudButtonStyle(kind: showsHistory ? .iconFilled : .icon))
                .help("Recordings")
                .accessibilityLabel("Recordings")
                .accessibilityAddTraits(showsHistory ? .isSelected : [])

                Spacer(minLength: Hud.Space.x2)

                Button {
                    NotificationCenter.default.post(name: .openDesktopWorkspace, object: nil)
                } label: {
                    HudIcon(.window)
                }
                .buttonStyle(HudButtonStyle(kind: .icon))
                .help("Open in window")
                .accessibilityLabel("Open in window")

                Button(action: onTogglePin) {
                    HudIcon(.pin)
                        .rotationEffect(.degrees(appState.isNotchPinned ? 0 : 30))
                }
                .buttonStyle(HudButtonStyle(kind: appState.isNotchPinned ? .iconFilled : .icon))
                .animation(Hud.Motion.glide, value: appState.isNotchPinned)
                .help(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
                .accessibilityLabel(appState.isNotchPinned ? "Unpin panel" : "Keep panel open")
                .accessibilityValue(appState.isNotchPinned ? "Pinned" : "Not pinned")
            }
        }
    }
}

private extension AppState.PanelTab {
    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .meetings: "1"
        case .tasks: "2"
        }
    }

    var title: String {
        switch self {
        case .meetings: String(localized: "Today")
        case .tasks: String(localized: "Tasks")
        }
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
