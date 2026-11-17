import AppKit
import EventKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Declared first so it runs before any property below reads defaults, Keychain or files.
    private let legacyIdentityMigration: Void = LegacyIdentityMigration.runIfNeeded()
    let appState = AppState()

    private var reminderPresentationTask: Task<Void, Never>?
    private var editingMeetingIDs = Set<UUID>()
    private var recordingTask: Task<Void, Never>?
    private var terminationCleanupTask: Task<Void, Never>?
    private var retentionCleanupTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var permissionRefreshTask: Task<Void, Never>?
    private var transientStatusTask: Task<Void, Never>?
    private var meetingAutoStopTask: Task<Void, Never>?
    private var pendingRelaunchURL: URL?
    private var processingRestartRequested = false
    private var meetingLifecyclePolicy = MeetingSessionLifecyclePolicy()
    private var notchHoverObservation: AnyCancellable?
    private var screenParametersObservation: AnyCancellable?
    private var accessibilityDisplayObservation: AnyCancellable?
    private var workspaceWillSleepObservation: AnyCancellable?
    private var workspaceDidWakeObservation: AnyCancellable?
    private var workspaceScreensDidSleepObservation: AnyCancellable?
    private var workspaceScreensDidWakeObservation: AnyCancellable?
    private var workspaceSessionDidResignObservation: AnyCancellable?
    private var workspaceSessionDidBecomeObservation: AnyCancellable?
    private var activeNotchScreen: NSScreen?
    private var onboardingWindowController: NSWindowController?
    private var onboardingCloseObserver: NSObjectProtocol?
    let meetingNotifications = MeetingNotificationService()
    private var notificationLeadTime: TimeInterval = 600
    private var calendarEnabled = true
    private let notchScreenResolver = NotchScreenResolver()
    private let audioPermissionService = AudioCapturePermissionService()
    private let microphoneDeviceService = MicrophoneDeviceService()
    private let applicationRelauncher = ApplicationRelauncher()
    private let microphoneGateHotKey = GlobalHotKeyMonitor()
    private let browserAudioBroker = BrowserAudioStreamBroker()
    private lazy var browserAudioIPCServer = BrowserAudioIPCServer(broker: browserAudioBroker)
    private let launchAtLoginService: any LaunchAtLoginServicing = LaunchAtLoginService()
    private let calendarProvider = EventKitMeetingProvider()
    private lazy var meetingMonitor = MeetingMonitor(provider: calendarProvider)
    private lazy var meetingSessionCoordinator = MeetingSessionCoordinator()
    private lazy var meetingRepository: any MeetingRepository = FileMeetingRepository()
    private(set) lazy var taskCoordinator = TaskCoordinator.live(appState: appState)
    private let notificationAuthorization = NotificationAuthorizationCache()
    private(set) lazy var setupCoordinator: SetupCoordinator = {
        let coordinator = SetupCoordinator(system: .live(
            systemAudio: { [unowned self] in self.audioPermissionService.currentSnapshot().systemAudio },
            requestSystemAudio: { [unowned self] in
                let snapshot = await self.audioPermissionService.requestSystemAudioAccess()
                self.appState.updateAudioCapturePermissions(snapshot)
            },
            requestAccessibility: { [unowned self] in self.requestAccessibilityAccess() },
            requestInputMonitoring: { [unowned self] in self.dictationCoordinator.requestInputMonitoringAccess() },
            notificationStatus: { [unowned self] in self.notificationAuthorization.current() }
        ))
        coordinator.onGranted = { [unowned self] capability in
            self.capabilityGranted(capability)
        }
        return coordinator
    }()
    private(set) lazy var dictationCoordinator: DictationCoordinator = {
        let coordinator = DictationCoordinator(appState: appState, taskCoordinator: taskCoordinator)
        coordinator.onListeningChange = { [weak self] listening in
            self?.dictationListeningChanged(listening)
        }
        return coordinator
    }()
    /// True while dictation has closed the meeting microphone gate.
    private var dictationClosedMeetingMicrophone = false
    private var appliedTaskStorage: TaskStorageBackend?
    private var agentResolutionTask: Task<Void, Never>?
    private let appSettingsRepository: any AppSettingsRepository = UserDefaultsAppSettingsRepository()
    private let apiKeyRepository: any APIKeyRepository = KeychainAPIKeyRepository()
    private let openAIKeys: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.openAIService)
    private let processingQueue = ProcessingQueue()
    private lazy var transcriptionWorker = TranscriptionProcessingWorker(
        queue: processingQueue,
        meetingRepository: meetingRepository,
        settingsRepository: appSettingsRepository,
        transcriptionService: MeetingTranscriptionRouter(
            preferences: { [appSettingsRepository] in
                ((try? await appSettingsRepository.load()) ?? .default).crenel.meetingProcessing
            },
            elevenLabs: ElevenLabsTranscriptionService(apiKeyRepository: apiKeyRepository)
        ),
        summaryService: MeetingSummaryRouter(
            preferences: { [appSettingsRepository] in
                ((try? await appSettingsRepository.load()) ?? .default).crenel.meetingProcessing
            },
            agentPreferences: { [appSettingsRepository] in
                await AgentProviderResolver.resolve(((try? await appSettingsRepository.load()) ?? .default).crenel.agent)
            },
            openAI: OpenAIMeetingSummaryService(keys: openAIKeys)
        ),
        onEvent: { [weak self] event in
            await self?.handleTranscriptionProcessingEvent(event)
        }
    )
    private lazy var recordingRecoveryService = RecordingRecoveryService(repository: meetingRepository)
    private lazy var retentionCleanupService = MeetingRetentionCleanupService(
        repository: meetingRepository
    )
    private lazy var recordingCoordinator: RecordingCoordinator = {
        let coordinator = RecordingCoordinator(systemAudioFactory: { [weak self] scope in
            guard let self else { return SystemAudioCaptureSource(scope: scope) }
            switch scope {
            case .browserTab:
                return BrowserAudioCaptureSource(broker: self.browserAudioBroker)
            case .meetingProcesses, .explicitManualGlobal:
                return SystemAudioCaptureSource(scope: scope)
            }
        })
        coordinator.onStatusChange = { [weak self] status in
            self?.appState.updateRecordingCaptureStatus(status)
        }
        coordinator.onSourceConnectionChange = { [weak self] source, connectionState in
            guard connectionState.needsAttention else { return }
            self?.presentNotch(followPointer: false)
            if source == .systemAudio, connectionState == .pipelineStalled {
                self?.handleRecordingSafetyInterruption(
                    connectionState.message ?? "System audio stream was lost."
                )
            }
        }
        coordinator.onSafetyInterruption = { [weak self] error in
            self?.handleRecordingSafetyInterruption(
                error.errorDescription ?? "Stopping the recording to keep it safe."
            )
        }
        coordinator.onMicrophoneGateChange = { [weak self] gate in
            guard let self else { return }
            self.appState.updateMeetingMicrophoneGate(gate)
            switch gate.events.last?.source {
            case .adapterUnavailable, .processChanged, .systemInterruption:
                self.presentNotch(followPointer: false)
            default:
                break
            }
        }
        return coordinator
    }()
    private lazy var notchHoverController = NotchHoverController(
        onExpand: { [weak self] in
            guard let self else { return }
            await self.notch.expand(on: self.resolvedActiveNotchScreen())
        },
        onCompact: { [weak self] in
            guard let self else { return }
            await self.notch.compact(on: self.resolvedActiveNotchScreen())
        }
    )

    private lazy var notch = CrenelNotchController(
        expanded: { [unowned self] in
            AnyView(
            NotchPanelView(
                onRequestCalendarAccess: { [weak self] in
                    self?.requestCalendarAccess()
                },
                onOpenMeetingURL: { [weak self] url in self?.openMeetingURL(url) },
                onStartRecording: { [weak self] in self?.beginRecording() },
                onStopRecording: { [weak self] in self?.stopRecordingFlow() },
                onToggleMeetingMicrophone: { [weak self] in
                    self?.toggleMeetingMicrophoneGate()
                },
                onDismissMeetingPrompt: { [weak self] in
                    self?.dismissMeetingLifecyclePrompt()
                },
                onContinueRecording: { [weak self] in
                    self?.continueRecordingAfterMeetingSignal()
                },
                onConfirmMeetingEnded: { [weak self] in
                    self?.confirmMeetingEnded()
                },
                onCancelFlow: { [weak self] in self?.cancelRecordingFlow() },
                onRecoverFromFailure: { [weak self] failure in
                    self?.recover(from: failure)
                },
                onOpenStoredMeeting: { [weak self] meeting in self?.openStoredMeeting(meeting) },
                onCopyText: { [weak self] text in self?.copyToPasteboard(text) },
                onExportMarkdown: { [weak self] markdown, meeting in
                    self?.exportMarkdown(markdown, for: meeting)
                },
                onRevealAudio: { url in
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                },
                onDeleteStoredMeeting: { [weak self] meeting in self?.deleteStoredMeeting(meeting) },
                onRetryStoredMeeting: { [weak self] meeting in self?.retryProcessing(meeting) },
                onOpenRecovery: { [weak self] in self?.openRecoveryDirectory() },
                onTogglePin: { [weak self] in self?.toggleNotchPin() },
                onRelaunchApplication: { [weak self] in self?.relaunchApplication() },
                analysisActions: self.meetingAnalysisActions
            )
                .environmentObject(self.appState)
                .environment(\.crenelActions, self.crenelActions)
        )
        },
        compact: { [unowned self] in
            AnyView(
                CrenelCompactView(actions: self.notchStripActions)
                    .environmentObject(self.appState)
                    .environment(\.crenelActions, self.crenelActions)
            )
        }
    )

    /// The strip under the closed notch answers with the same actions as the panel.
    private var notchStripActions: NotchStripActions {
        NotchStripActions(
            joinMeeting: { [weak self] url in self?.openMeetingURL(url) },
            startRecording: { [weak self] in self?.beginRecording() },
            dismissPrompt: { [weak self] in self?.dismissMeetingLifecyclePrompt() },
            continueRecording: { [weak self] in self?.continueRecordingAfterMeetingSignal() },
            confirmMeetingEnded: { [weak self] in self?.confirmMeetingEnded() },
            openStoredMeeting: { [weak self] meeting in
                self?.openStoredMeeting(meeting)
                self?.presentNotch(followPointer: false)
            },
            recoverFromFailure: { [weak self] failure in self?.recover(from: failure) }
        )
    }

    private var desktopController: DesktopWindowController?
    private var desktopOpenObserver: NSObjectProtocol?
    private var desktopSettingsObserver: NSObjectProtocol?

    func showDesktop(section: DesktopSection? = nil, category: SettingsCategory? = nil) {
        if desktopController == nil {
            desktopController = DesktopWindowController(delegate: self)
        }
        desktopController?.present(section: section, category: category)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDesktop()
        return false
    }

    func desktopSettings(category: SettingsCategory = .general) -> some View {
            SettingsView(
                onRequestMicrophoneAccess: self.requestMicrophoneAccess,
                onRequestSystemAudioAccess: self.requestSystemAudioAccess,
                onRequestAccessibilityAccess: self.requestAccessibilityAccess,
                onOpenAccessibilitySettings: self.openAccessibilitySettings,
                onOpenSystemSettings: self.openSystemSettings,
                onRelaunchApplication: self.relaunchApplication,
                onRefreshPermissions: {
                    self.refreshAudioPermissions()
                    self.refreshAccessibilityPermission()
                    self.refreshCalendar()
                },
                onRequestCalendarAccess: self.requestCalendarAccess,
                onRefreshCalendar: self.refreshCalendar,
                onOpenCalendarSettings: self.openCalendarPrivacySettings,
                onOpenInternetAccounts: self.openInternetAccountsSettings,
                onLoadGeneralSettings: self.loadGeneralSettings,
                onSaveGeneralSettings: self.saveGeneralSettings,
                onLoadMicrophoneSettings: self.loadMicrophoneSettings,
                onSaveMicrophoneSelection: self.saveMicrophoneSelection,
                onOpenDataDirectory: self.openDataDirectory,
                onDeleteAllData: self.deleteAllData,
                onResetOnboarding: self.resetOnboarding,
                onLoadTranscriptionSettings: self.loadTranscriptionSettings,
                onSaveTranscriptionSettings: self.saveTranscriptionSettings,
                onDeleteTranscriptionAPIKey: self.deleteTranscriptionAPIKey,
                openAISettings: self.openAISettingsActions,
                crenelSettings: self.crenelSettingsActions,
                notificationService: self.meetingNotifications,
                initialCategory: category
            )
            .environmentObject(self.appState)
    }

    func loadDesktopMeeting(_ meeting: StoredMeeting) async throws -> MeetingDetailContent {
        let transcript = try await meetingRepository.loadTranscription(for: meeting.id)
        let markdown = try await meetingRepository.loadMarkdown(for: meeting.id)
        let audio = await meetingRepository.audioFileURL(for: meeting)
        return MeetingDetailContent(meeting: meeting, storedTranscription: transcript,
            markdown: markdown, audioURL: audio)
    }

    func desktopAudioURL(for meeting: StoredMeeting) async -> URL {
        await meetingRepository.audioFileURL(for: meeting)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Hud.registerFonts()
        // XCTest must not start real calendar/account/audio services or drain user queues.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        // Start keeping the recording level history now, so a recording begun from the
        // strip has its chart before the panel is first opened.
        _ = appState.todayFlowMemory
        desktopSettingsObserver = NotificationCenter.default.addObserver(
            forName: .openDesktopSettings, object: nil, queue: .main
        ) { [weak self] notification in
            let category = (notification.userInfo?["category"] as? String).flatMap(SettingsCategory.init(rawValue:))
            Task { @MainActor in self?.showDesktop(section: .settings, category: category) }
        }
        desktopOpenObserver = NotificationCenter.default.addObserver(
            forName: .openDesktopWorkspace, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.showDesktop() } }
        MultipartFormFileBuilder.removeStaleUploadBodies()
        configureBrowserAudioBridge()
        configureMeetingSessionCoordinator()
        microphoneGateHotKey.start { [weak self] in
            self?.toggleMeetingMicrophoneGate()
        }
        meetingNotifications.onOpenMeeting = { [weak self] url in self?.openMeetingURL(url) }
        configureMeetingMonitor()
        configureNotchInteraction()
        configureWorkspacePowerEvents()
        configureMicrophoneDevices()
        refreshAudioPermissions()
        refreshAccessibilityPermission()
        loadStoredMeetings()
        startPeriodicRetentionCleanup()
        loadInitialPreferences()

        Task {
            let screen = resolvedActiveNotchScreen(preferPhysicalNotch: true)
            await notch.compact(on: screen)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        launchPendingRelaunchIfNeeded()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            // Fn's own system action must work again while Crenel is not running.
            FnKeySystemActionGuard().update(dictationEnabled: false, trigger: .fnHold)
        }
        reminderPresentationTask?.cancel()
        recordingTask?.cancel()
        terminationCleanupTask?.cancel()
        retentionCleanupTask?.cancel()
        processingTask?.cancel()
        permissionRefreshTask?.cancel()
        transientStatusTask?.cancel()
        meetingAutoStopTask?.cancel()
        notchHoverController.cancel()
        notchHoverObservation = nil
        screenParametersObservation = nil
        accessibilityDisplayObservation = nil
        workspaceWillSleepObservation = nil
        workspaceDidWakeObservation = nil
        workspaceScreensDidSleepObservation = nil
        workspaceScreensDidWakeObservation = nil
        workspaceSessionDidResignObservation = nil
        workspaceSessionDidBecomeObservation = nil
        meetingMonitor.stop()
        Task { await meetingSessionCoordinator.stop() }
        microphoneDeviceService.stopMonitoring()
        microphoneGateHotKey.stop()
        browserAudioIPCServer.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAudioPermissions(recheckingFor: .seconds(3))
        refreshAccessibilityPermission()
    }

    private func configureWorkspacePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceWillSleepObservation = center.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.systemWillSleep()
            }
        workspaceDidWakeObservation = center.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.systemDidWake()
            }
        workspaceScreensDidSleepObservation = center.publisher(
            for: NSWorkspace.screensDidSleepNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.systemWillSleep()
        }
        workspaceScreensDidWakeObservation = center.publisher(
            for: NSWorkspace.screensDidWakeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.systemDidWake()
        }
        workspaceSessionDidResignObservation = center.publisher(
            for: NSWorkspace.sessionDidResignActiveNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.systemWillSleep()
        }
        workspaceSessionDidBecomeObservation = center.publisher(
            for: NSWorkspace.sessionDidBecomeActiveNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.systemDidWake()
        }
    }

    private func systemWillSleep() {
        switch appState.meetingFlow.phase {
        case .recording:
            recordingCoordinator.failClosedForSystemInterruption()
            presentNotch(followPointer: false)
            stopRecordingFlow()
        case .preparingRecording:
            cancelRecordingFlow()
        default:
            break
        }
    }

    private func systemDidWake() {
        refreshAudioPermissions(recheckingFor: .seconds(3))
        refreshAccessibilityPermission(recheckingFor: .seconds(3))
        microphoneDeviceService.startMonitoring()
        Task { [weak self] in
            await self?.meetingSessionCoordinator.refresh()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appState.requiresTerminationConfirmation else {
            return .terminateNow
        }

        AppLogger.terminationRequiresConfirmation(phase: appState.meetingFlow.phase)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appState.meetingFlow.isRecording
            ? "Recording in progress"
            : "Meeting is still processing"
        alert.informativeText = "If you quit now, the current work will stop."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        recordingTask?.cancel()
        appState.cancelCurrentFlow()
        terminationCleanupTask = Task { [weak self] in
            guard let self else {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            await self.recordingCoordinator.cancel()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func showCrenel() {
        presentNotch(followPointer: true)
    }

    func startManualRecording() {
        beginRecording()
        presentNotch(followPointer: true)
    }

    /// Words dictated into another app during a meeting recording must not end up in the
    /// meeting audio: the meeting microphone gate closes while dictation listens.
    private func dictationListeningChanged(_ listening: Bool) {
        if listening {
            guard appState.meetingFlow.isRecording,
                  appState.meetingMicrophoneGate?.permitsAudio == true else { return }
            recordingCoordinator.setManualMicrophoneState(.closed)
            dictationClosedMeetingMicrophone = true
        } else if dictationClosedMeetingMicrophone {
            dictationClosedMeetingMicrophone = false
            guard appState.meetingFlow.isRecording else { return }
            recordingCoordinator.setManualMicrophoneState(.open)
        }
    }

    func toggleMeetingMicrophoneGate() {
        guard appState.meetingFlow.isRecording,
              let gate = appState.meetingMicrophoneGate else { return }
        recordingCoordinator.setManualMicrophoneState(
            gate.permitsAudio ? .closed : .open
        )
        presentNotch(followPointer: false)
    }

    func refreshCalendar() {
        Task {
            await meetingMonitor.refresh()
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func requestMicrophoneAccess() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.audioPermissionService.requestMicrophoneAccess()
            self.appState.updateAudioCapturePermissions(snapshot)
        }
    }

    func requestSystemAudioAccess() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.audioPermissionService.requestSystemAudioAccess()
            self.appState.updateAudioCapturePermissions(snapshot)
            if snapshot.systemAudio.requiresSystemSettings {
                self.openSystemSettings(for: .systemAudio)
            } else {
                self.refreshAudioPermissions(recheckingFor: .seconds(3))
            }
        }
    }

    func requestAccessibilityAccess() {
        let granted = SystemAccessibilityAuthorizer().isTrusted(prompt: true)
        appState.updateAccessibilityPermission(granted: granted)
        refreshAccessibilityPermission(recheckingFor: .seconds(5))
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshAccessibilityPermission(recheckingFor duration: Duration? = nil) {
        appState.updateAccessibilityPermission(
            granted: SystemAccessibilityAuthorizer().isTrusted(prompt: false)
        )
        guard let duration else { return }
        Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: duration)
            while !Task.isCancelled, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let granted = SystemAccessibilityAuthorizer().isTrusted(prompt: false)
                self.appState.updateAccessibilityPermission(granted: granted)
                if granted {
                    await self.meetingSessionCoordinator.refresh()
                    return
                }
            }
        }
    }

    func relaunchApplication() {
        pendingRelaunchURL = Bundle.main.bundleURL
        NSApp.terminate(nil)
    }

    private func launchPendingRelaunchIfNeeded() {
        guard let applicationURL = pendingRelaunchURL else { return }
        pendingRelaunchURL = nil

        do {
            try applicationRelauncher.prepareRelaunch(applicationURL: applicationURL)
        } catch {
            AppLogger.permissionOperationFailed(operation: "relaunch")
        }
    }

    func openSystemSettings(for source: AudioSourceKind) {
        let pane = switch source {
        case .microphone:
            "Privacy_Microphone"
        case .systemAudio:
            "Privacy_AudioCapture"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func loadTranscriptionSettings() async -> TranscriptionSettingsSnapshot {
        let preferences = (try? await appSettingsRepository.load()) ?? .default
        let hasKey = ((try? await apiKeyRepository.apiKey()) ?? nil) != nil
        return TranscriptionSettingsSnapshot(
            languageCode: preferences.transcription.languageCode,
            hasStoredAPIKey: hasKey
        )
    }

    func loadGeneralSettings() async -> GeneralSettingsSnapshot {
        let preferences = (try? await appSettingsRepository.load()) ?? .default
        return GeneralSettingsSnapshot(
            reminderLeadTime: preferences.reminderLeadTime,
            isCalendarEnabled: preferences.isCalendarEnabled,
            launchAtLogin: launchAtLoginService.isConfigured,
            meetingRetentionPolicy: preferences.meetingRetentionPolicy,
            selectedCalendarIDs: preferences.selectedCalendarIDs
        )
    }

    func loadMicrophoneSettings() async -> MicrophoneSettingsSnapshot {
        let preferences = (try? await appSettingsRepository.load()) ?? .default
        return MicrophoneSettingsSnapshot(
            devices: await microphoneDeviceService.currentDevices(),
            selectedDeviceID: preferences.selectedMicrophoneID
        )
    }

    func saveMicrophoneSelection(_ deviceID: String?) async -> SettingsActionResult {
        let devices = await microphoneDeviceService.currentDevices()
        if let deviceID, !devices.contains(where: { $0.id == deviceID }) {
            return .failed(message: "The selected microphone is no longer connected. Refresh the list.")
        }

        do {
            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.selectedMicrophoneID = deviceID
            try await appSettingsRepository.save(preferences)
            appState.updateSelectedMicrophoneID(deviceID)
            return .succeeded(message: deviceID == nil ? "The system default will be used." : "Microphone saved.")
        } catch {
            AppLogger.persistenceFailed(operation: "save-microphone-settings", error: error)
            return .failed(message: "Couldn't save the microphone. Try again.")
        }
    }

    func saveGeneralSettings(
        _ snapshot: GeneralSettingsSnapshot
    ) async -> SettingsActionResult {
        guard (60...(60 * 60)).contains(snapshot.reminderLeadTime) else {
            return .failed(message: "Reminder time must be between 1 and 60 minutes.")
        }

        do {
            try launchAtLoginService.setEnabled(snapshot.launchAtLogin)
            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.reminderLeadTime = snapshot.reminderLeadTime
            preferences.isCalendarEnabled = snapshot.isCalendarEnabled
            preferences.selectedCalendarIDs = snapshot.selectedCalendarIDs
            preferences.launchAtLogin = snapshot.launchAtLogin
            preferences.meetingRetentionPolicy = snapshot.meetingRetentionPolicy
            try await appSettingsRepository.save(preferences)
            applyRuntimePreferences(preferences)
            await runRetentionCleanup()

            return .succeeded(
                message: launchAtLoginService.requiresApproval
                    ? "Approve Open at Login in System Settings."
                    : nil
            )
        } catch {
            AppLogger.persistenceFailed(operation: "save-general-settings", error: error)
            return .failed(message: "Couldn't save general settings. Try again.")
        }
    }

    func openDataDirectory() {
        do {
            let layout = try AppStorageLayout.applicationSupport()
            try layout.createDirectories()
            NSWorkspace.shared.open(layout.root)
        } catch {
            AppLogger.persistenceFailed(operation: "open-data-directory", error: error)
        }
    }

    func resetOnboarding() async -> SettingsActionResult {
        do {
            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.hasCompletedOnboarding = false
            try await appSettingsRepository.save(preferences)
            presentOnboarding()
            return .succeeded()
        } catch {
            AppLogger.persistenceFailed(operation: "reset-onboarding", error: error)
            return .failed(message: "Couldn't restart onboarding.")
        }
    }

    func deleteAllData() async -> SettingsActionResult {
        guard !appState.requiresTerminationConfirmation else {
            return .failed(message: "You can't delete all data while recording or processing.")
        }

        processingTask?.cancel()
        if let processingTask {
            await processingTask.value
        }
        self.processingTask = nil
        processingRestartRequested = false
        meetingMonitor.stop()
        appState.dismissMeetingDetail()

        meetingNotifications.update(meetings: [], leadTime: notificationLeadTime, enabled: false)
        var keychainDeletionFailed = false
        do { try await LegacyGoogleCalendarCleanup.removeStoredGrant() }
        catch { keychainDeletionFailed = true }
        do { try await openAIKeys.deleteAPIKey() }
        catch { keychainDeletionFailed = true }
        do { try await KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.anthropicService).deleteAPIKey() }
        catch { keychainDeletionFailed = true }
        do {
            try await apiKeyRepository.deleteAPIKey()
        } catch {
            keychainDeletionFailed = true
            AppLogger.persistenceFailed(operation: "delete-transcription-key", error: error)
        }

        do {
            try launchAtLoginService.setEnabled(false)
            if let identifier = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: identifier)
            }
            await appSettingsRepository.reset()

            let layout = try AppStorageLayout.applicationSupport()
            if FileManager.default.fileExists(atPath: layout.root.path) {
                try FileManager.default.removeItem(at: layout.root)
            }
            try layout.createDirectories()
            try await processingQueue.removeAll()
            appState.resetPersistedContent()
            applyRuntimePreferences(.default)
            presentOnboarding()

            if keychainDeletionFailed {
                return .failed(
                    message: "Local data was deleted, but at least one Keychain key remains. Try again."
                )
            }
            return .succeeded(message: "All meetings, tasks, settings and API keys were deleted.")
        } catch {
            AppLogger.persistenceFailed(operation: "delete-all-data", error: error)
            return .failed(message: "Couldn't delete all data. Try again.")
        }
    }

    func saveTranscriptionSettings(
        languageCode: String?,
        apiKey: String?
    ) async -> TranscriptionSettingsSaveResult {
        do {
            let normalizedInput = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let newKey = normalizedInput.flatMap { $0.isEmpty ? nil : $0 }
            if let newKey {
                try await ElevenLabsAPIKeyValidator().validate(newKey)
                try await apiKeyRepository.saveAPIKey(newKey)
            }

            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.transcription.languageCode = languageCode
            try await appSettingsRepository.save(preferences)
            // Only the language changed: nothing to verify, nothing to retry.
            guard newKey != nil else { return .saved(retriedJobCount: 0) }

            let retriedJobs = try await processingQueue.retryFailed(
                failure: .authentication
            )
            retriedJobs.forEach(appState.upsertProcessingJob)
            if !retriedJobs.isEmpty {
                startProcessingQueue()
            }
            return .saved(retriedJobCount: retriedJobs.count)
        } catch {
            let normalized = TranscriptionErrorNormalizer.normalize(error)
            return .failed(normalized.appFailure)
        }
    }

    var crenelSettingsActions: CrenelSettingsActions {
        let anthropicKeys = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.anthropicService)
        return CrenelSettingsActions(
            load: { [weak self] in await self?.loadCrenelPreferences() ?? .default },
            save: { [weak self] preferences in
                await self?.saveCrenelPreferences(preferences) ?? .failed(message: "The app is quitting.")
            },
            hasAnthropicKey: { ((try? await anthropicKeys.apiKey()) ?? nil) != nil },
            saveAnthropicKey: { [weak self] key in
                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .failed(message: "Key can't be empty.") }
                do {
                    try await anthropicKeys.saveAPIKey(trimmed)
                    await self?.reapplyAgentProvider()
                    return .succeeded(message: "Anthropic key saved to Keychain.")
                } catch {
                    return .failed(message: "Couldn't save the key.")
                }
            },
            deleteAnthropicKey: { [weak self] in
                do {
                    try await anthropicKeys.deleteAPIKey()
                    await self?.reapplyAgentProvider()
                    return .succeeded(message: "Anthropic key removed.")
                } catch {
                    return .failed(message: "Couldn't remove the key.")
                }
            },
            onDeviceModelStatus: {
                if case .unavailable(let reason) = FoundationModelsProvider().availability {
                    return reason.message
                }
                return nil
            }
        )
    }

    var openAISettingsActions: OpenAISettingsActions {
        OpenAISettingsActions(
            hasKey: { [weak self] in (try? await self?.openAIKeys.apiKey()) != nil },
            save: { [weak self] key in
                guard let self else { return .failed(message: "The app is quitting.") }
                do {
                    try await OpenAIMeetingSummaryService(keys: self.openAIKeys).validate(apiKey: key)
                    try await self.openAIKeys.saveAPIKey(key)
                    await self.reapplyAgentProvider()
                    return .succeeded(message: "OpenAI connected. New meetings will be summarized automatically.")
                } catch {
                    return .failed(message: (error as? MeetingAnalysisError)?.errorDescription ?? "Couldn't save the key to Keychain.")
                }
            },
            disconnect: { [weak self] in
                do {
                    try await self?.openAIKeys.deleteAPIKey()
                    await self?.reapplyAgentProvider()
                    return .succeeded(message: "OpenAI disconnected. Your recordings are kept.")
                } catch { return .failed(message: "Couldn't remove the key.") }
            }
        )
    }

    func deleteTranscriptionAPIKey() async -> SettingsActionResult {
        do {
            try await apiKeyRepository.deleteAPIKey()
            return .succeeded(message: "ElevenLabs disconnected.")
        } catch {
            AppLogger.persistenceFailed(operation: "delete-transcription-key", error: error)
            return .failed(message: "Couldn't remove the API key from Keychain.")
        }
    }

    private func configureMeetingMonitor() {
        meetingMonitor.onAccessStateChange = { [weak self] state in
            self?.appState.updateCalendarAccessState(state)
        }

        meetingMonitor.onIntegrationSnapshotChange = { [weak self] snapshot in
            self?.appState.updateCalendarIntegrationSnapshot(snapshot)
        }

        meetingMonitor.onRefreshStateChange = { [weak self] isRefreshing in
            self?.appState.updateCalendarRefreshState(isRefreshing: isRefreshing)
        }

        meetingMonitor.onMeetingsChange = { [weak self] meetings in
            guard let self else { return }
            self.appState.updateUpcomingMeetings(meetings)
            self.meetingNotifications.update(meetings: meetings.filter(\.isReminderCandidate), leadTime: self.notificationLeadTime, enabled: self.calendarEnabled)
        }

        meetingMonitor.onSnapshotChange = { [weak self] snapshot, shouldPresent in
            guard let self else { return }
            Task {
                await self.meetingSessionCoordinator.updateCalendarMeeting(
                    snapshot.nextMeeting
                )
            }
            let willPresent = self.appState.applyMeetingSnapshot(
                snapshot,
                shouldPresent: shouldPresent
            )
            guard willPresent else { return }
            self.presentMeetingReminder()
        }
    }

    private func configureMeetingSessionCoordinator() {
        Task { [weak self] in
            guard let self else { return }
            await self.meetingSessionCoordinator.start { [weak self] snapshot in
                await self?.receiveMeetingSessionDetection(snapshot)
            }
        }
    }

    private func receiveMeetingSessionDetection(
        _ snapshot: MeetingSessionDetectionSnapshot
    ) {
        appState.updateMeetingSessionDetection(snapshot)
        recordingCoordinator.updateMicrophoneGate(from: snapshot)
        let decision = meetingLifecyclePolicy.evaluate(
            snapshot.session,
            isRecording: appState.meetingFlow.isRecording,
            canOfferRecording: canOfferDetectedRecording
        )
        applyMeetingLifecycleDecision(decision)
    }

    private var canOfferDetectedRecording: Bool {
        switch appState.meetingFlow {
        case .idle, .upcomingMeeting:
            true
        default:
            false
        }
    }

    private func applyMeetingLifecycleDecision(
        _ decision: MeetingSessionLifecycleDecision
    ) {
        switch decision {
        case .none:
            return
        case .dismiss:
            meetingAutoStopTask?.cancel()
            meetingAutoStopTask = nil
            appState.dismissMeetingLifecyclePrompt()
        case .present(let prompt):
            meetingAutoStopTask?.cancel()
            meetingAutoStopTask = nil
            appState.presentMeetingLifecyclePrompt(prompt)
            // The prompt is a strip under the closed notch; it never opens the panel.
            notch.pulse()
            guard case .autoStop(_, _, let deadline) = prompt else { return }
            meetingAutoStopTask = Task { [weak self] in
                let delay = max(0, deadline.timeIntervalSinceNow)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let self,
                      self.appState.meetingLifecyclePrompt == prompt,
                      self.appState.meetingFlow.isRecording else {
                    return
                }
                _ = self.meetingLifecyclePolicy.confirmEnd(sessionID: prompt.sessionID)
                self.appState.dismissMeetingLifecyclePrompt()
                self.meetingAutoStopTask = nil
                self.stopRecordingFlow()
            }
        }
    }

    private func dismissMeetingLifecyclePrompt() {
        applyMeetingLifecycleDecision(
            meetingLifecyclePolicy.dismissRecordingOffer()
        )
    }

    private func continueRecordingAfterMeetingSignal() {
        guard let prompt = appState.meetingLifecyclePrompt else { return }
        applyMeetingLifecycleDecision(
            meetingLifecyclePolicy.continueRecording(sessionID: prompt.sessionID)
        )
    }

    private func confirmMeetingEnded() {
        guard let prompt = appState.meetingLifecyclePrompt else { return }
        applyMeetingLifecycleDecision(
            meetingLifecyclePolicy.confirmEnd(sessionID: prompt.sessionID)
        )
        stopRecordingFlow()
    }

    private func configureMicrophoneDevices() {
        microphoneDeviceService.onDevicesChange = { [weak self] devices in
            self?.appState.updateAvailableMicrophones(devices)
        }
        microphoneDeviceService.startMonitoring()
    }

    private func loadInitialPreferences() {
        Task { [weak self] in
            guard let self else { return }
            var preferences = (try? await self.appSettingsRepository.load()) ?? .default
            let actualLaunchAtLogin = self.launchAtLoginService.isConfigured
            if preferences.launchAtLogin != actualLaunchAtLogin {
                preferences.launchAtLogin = actualLaunchAtLogin
                try? await self.appSettingsRepository.save(preferences)
            }
            self.applyRuntimePreferences(preferences)
            // Builds before the unified setup could leave Calendar/Reminders never asked
            // (or silently refused); show the one-screen setup once to existing users too.
            if !preferences.hasCompletedOnboarding || !UserDefaults.standard.bool(forKey: Self.unifiedSetupShownKey) {
                self.presentOnboarding()
            }
        }
    }

    private func applyRuntimePreferences(_ preferences: AppPreferences) {
        calendarEnabled = preferences.isCalendarEnabled
        notificationLeadTime = preferences.reminderLeadTime
        appState.isCalendarEnabled = preferences.isCalendarEnabled
        appState.updateSelectedMicrophoneID(preferences.selectedMicrophoneID)
        meetingMonitor.configure(
            isEnabled: preferences.isCalendarEnabled,
            reminderLeadTime: preferences.reminderLeadTime,
            selectedCalendarIDs: preferences.selectedCalendarIDs
        )
        applyCrenelPreferences(preferences)
    }

    private func applyCrenelPreferences(_ preferences: AppPreferences) {
        dictationCoordinator.apply(preferences.crenel, microphoneID: preferences.selectedMicrophoneID)
        if preferences.crenel.agent.provider == .automatic {
            agentResolutionTask?.cancel()
            agentResolutionTask = Task { [weak self] in
                var crenel = preferences.crenel
                crenel.agent = await AgentProviderResolver.resolve(crenel.agent)
                guard !Task.isCancelled else { return }
                self?.dictationCoordinator.apply(crenel, microphoneID: preferences.selectedMicrophoneID)
            }
        }
        let storage = preferences.crenel.taskStorage
        if appliedTaskStorage == nil {
            appliedTaskStorage = storage
            taskCoordinator.start(preferReminders: storage == .reminders)
        } else if appliedTaskStorage != storage {
            appliedTaskStorage = storage
            Task { await self.taskCoordinator.activate(preferReminders: storage == .reminders) }
        }
    }

    /// A key was added or removed: `.automatic` may now resolve to a different provider.
    private func reapplyAgentProvider() async {
        let preferences = (try? await appSettingsRepository.load()) ?? .default
        applyCrenelPreferences(preferences)
    }

    func loadCrenelPreferences() async -> CrenelPreferences {
        ((try? await appSettingsRepository.load()) ?? .default).crenel
    }

    func saveCrenelPreferences(_ crenel: CrenelPreferences) async -> SettingsActionResult {
        do {
            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.crenel = crenel
            try await appSettingsRepository.save(preferences)
            applyCrenelPreferences(preferences)
            return .succeeded(message: nil)
        } catch {
            AppLogger.persistenceFailed(operation: "save-crenel-settings", error: error)
            return .failed(message: "Couldn't save settings. Try again.")
        }
    }

    static let unifiedSetupShownKey = "crenel.unifiedSetupShown"

    private func presentOnboarding() {
        if let onboardingWindowController {
            onboardingWindowController.showWindow(nil)
            onboardingWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hasCompletedBefore = UserDefaults.standard.bool(forKey: Self.unifiedSetupShownKey)
        let rootView = OnboardingView(
            setup: setupCoordinator,
            onComplete: { [weak self] in self?.completeOnboarding() },
            initialStep: hasCompletedBefore ? .setup : .welcome
        )
        .environmentObject(appState)
        .environment(\.crenelActions, crenelActions)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Crenel"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.setContentSize(OnboardingView.windowSize)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        onboardingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onboardingDidClose() }
        }
        setupCoordinator.onReturnFromSystem = { [weak self] in self?.bringOnboardingToFront() }
        // A menu-bar app's window falls behind other apps whenever focus moves (a
        // permission prompt, a click elsewhere). While setup is open Crenel behaves like a
        // regular app: it has a Dock icon, takes part in ⌘Tab and keeps its window.
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        bringOnboardingToFront()
    }

    private func bringOnboardingToFront() {
        guard let window = onboardingWindowController?.window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func onboardingDidClose() {
        if let onboardingCloseObserver {
            NotificationCenter.default.removeObserver(onboardingCloseObserver)
        }
        onboardingCloseObserver = nil
        onboardingWindowController = nil
        setupCoordinator.onReturnFromSystem = {}
        if desktopController?.window?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func completeOnboarding() {
        Task { [weak self] in
            guard let self else { return }
            do {
                var preferences = (try? await self.appSettingsRepository.load()) ?? .default
                preferences.hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: Self.unifiedSetupShownKey)
                self.setupCoordinator.refresh()
                try await self.appSettingsRepository.save(preferences)
                self.applyRuntimePreferences(preferences)
                self.onboardingWindowController?.close()
            } catch {
                AppLogger.persistenceFailed(operation: "complete-onboarding", error: error)
            }
        }
    }

    private func configureNotchInteraction() {
        updateNotchTransitionConfiguration()
        // A strip holds buttons, so hovering it does not open the panel; a click on its
        // ears does.
        notch.onRequestExpand = { [weak self] in self?.presentNotch(followPointer: false) }
        notchHoverObservation = notch.$hoverIntent
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isHovering in
                self?.notchHoverController.update(isHovering: isHovering)
            }

        screenParametersObservation = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .sink { [weak self] _ in
            self?.screenParametersDidChange()
        }

        accessibilityDisplayObservation = NotificationCenter.default.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )
        .sink { [weak self] _ in
            self?.updateNotchTransitionConfiguration()
        }
    }

    private func updateNotchTransitionConfiguration() {
        // Motion follows the Reduce Motion setting inside the notch views themselves.
    }

    private func presentNotch(followPointer: Bool) {
        Task {
            await expandNotch(followPointer: followPointer)
        }
    }

    private func expandNotch(followPointer: Bool) async {
        let previousScreen = activeNotchScreen
        let targetScreen = followPointer
            ? (notchScreenResolver.presentationScreen() ?? resolvedActiveNotchScreen())
            : resolvedActiveNotchScreen()
        let needsRelocation = notchHoverController.presentationState == .expanded
            && !notchScreenResolver.isSameScreen(previousScreen, targetScreen)

        activeNotchScreen = targetScreen
        updateNotchPanelPresentation(for: targetScreen)
        notchHoverController.markExpanded()
        if needsRelocation {
            await notch.hide()
        }
        await notch.expand(on: targetScreen)
    }

    private func toggleNotchPin() {
        let isPinned = appState.toggleNotchPin()
        notchHoverController.setPinned(isPinned, isHovering: notch.isHovering)
    }

    private func resolvedActiveNotchScreen(preferPhysicalNotch: Bool = false) -> NSScreen {
        let resolved: NSScreen?
        if preferPhysicalNotch {
            resolved = notchScreenResolver.startupScreen()
        } else {
            resolved = notchScreenResolver.availableScreen(matching: activeNotchScreen)
        }

        let screen = resolved ?? NSScreen.main ?? NSScreen.screens[0]
        activeNotchScreen = screen
        updateNotchPanelPresentation(for: screen)
        return screen
    }

    private func updateNotchPanelPresentation(for screen: NSScreen) {
        let hasPhysicalNotch = notchScreenResolver.hasPhysicalNotch(screen)
        let viewport = NotchHostViewport(screen: screen)
        appState.updateNotchPanelPresentation(
            availableSize: viewport.availableSize,
            hasPhysicalNotch: hasPhysicalNotch
        )
    }

    private func screenParametersDidChange() {
        let screen = resolvedActiveNotchScreen()
        Task {
            await notch.hide()
            switch notchHoverController.presentationState {
            case .expanded:
                await notch.expand(on: screen)
            case .compact:
                await notch.compact(on: screen)
            }
        }
    }

    func requestCalendarAccess() {
        // A refused permission can no longer be prompted; send the user to the pane.
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted, .writeOnly:
            openCalendarPrivacySettings()
            setupCoordinator.watch()
            return
        default:
            break
        }
        // Accessory apps must come forward or the system prompt can stay hidden.
        NSApp.activate()
        Task {
            await meetingMonitor.requestAccess()
        }
    }

    /// A permission arrived (from onboarding, Settings or System Settings): connect the
    /// feature that needed it. Nothing else has to be set up by hand.
    private func capabilityGranted(_ capability: SetupCapability) {
        switch capability {
        case .calendar:
            Task { await meetingMonitor.requestAccess() }
        case .reminders:
            Task { await taskCoordinator.activate(preferReminders: true) }
        case .microphone, .systemAudio:
            refreshAudioPermissions()
        case .accessibility:
            refreshAccessibilityPermission()
        case .notifications:
            Task { await meetingNotifications.refreshStatus() }
        case .inputMonitoring:
            dictationCoordinator.requestInputMonitoringAccess()
        }
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInternetAccountsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    var crenelActions: CrenelActions {
        let tasks = taskCoordinator
        return CrenelActions(
            openInCalendar: { [weak self] item in self?.openInCalendar(item) },
            openMeetingURL: { [weak self] url in self?.openMeetingURL(url) },
            tasks: CrenelActions.TaskActions(
                add: { tasks.add($0) },
                rename: { tasks.rename($0, to: $1) },
                save: { tasks.save($0) },
                setStatus: { tasks.setStatus($0, to: $1) },
                reschedule: { tasks.reschedule($0, to: $1, hasTime: $2) },
                postponeToTomorrow: { tasks.postponeToTomorrow($0) },
                setPriority: { tasks.setPriority($0, to: $1) },
                archive: { tasks.archive($0) },
                restore: { tasks.restore($0) },
                delete: { tasks.delete($0) },
                clearHistory: { tasks.clearHistory() },
                connectReminders: { tasks.connectReminders() },
                openSourceMeeting: { [weak self] meetingID in self?.openStoredMeeting(id: meetingID) }
            ),
            dictation: CrenelActions.DictationActions(
                toggleHandsFree: { [weak self] in self?.dictationCoordinator.toggleHandsFree() },
                cancel: { [weak self] in self?.dictationCoordinator.cancel() },
                copyLast: { [weak self] in self?.dictationCoordinator.copyLastDictation() },
                requestInputMonitoring: { [weak self] in self?.dictationCoordinator.requestInputMonitoringAccess() },
                prepareSpeechAssets: { [weak self] in self?.dictationCoordinator.prepareSpeechAssets() }
            )
        )
    }

    private func openStoredMeeting(id: UUID) {
        guard let meeting = appState.storedMeetings.first(where: { $0.id == id }) else { return }
        appState.selectedTab = .meetings
        openStoredMeeting(meeting)
    }

    func openInCalendar(_ item: Meeting) {
        guard let url = CalendarAppLink.url(for: item) else { return }
        NSWorkspace.shared.open(url)
    }

    func openMeetingURL(_ url: URL) {
        let meeting = appState.upcomingMeeting(matching: url)
        Task { [weak self] in
            guard let self else { return }
            await self.meetingSessionCoordinator.recordJoinAction(
                meeting: meeting,
                url: url
            )
            NSWorkspace.shared.open(url)
        }
    }

    private func beginRecording() {
        let sourceMeeting = RecordingMeetingContext.resolve(
            meetings: appState.upcomingMeetings,
            session: appState.meetingSessionDetection?.session,
            now: Date()
        )
        applyMeetingLifecycleDecision(
            meetingLifecyclePolicy.dismissRecordingOffer()
        )
        guard appState.prepareForRecording() else { return }

        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let systemAudioScope = try MeetingAudioCaptureScopeResolver(
                    browserAudioAvailable: { [weak self] in
                        self?.browserAudioBroker.hasActiveSession ?? false
                    }
                ).resolve(
                    detection: self.appState.meetingSessionDetection,
                    meeting: sourceMeeting
                )
                let permissions: AudioCapturePermissionSnapshot
                switch systemAudioScope {
                case .browserTab:
                    permissions = await self.audioPermissionService.requestMicrophoneAccess()
                case .meetingProcesses, .explicitManualGlobal:
                    permissions = await self.audioPermissionService.verifyAccessForRecording()
                }
                self.appState.updateAudioCapturePermissions(permissions)
                let hasRequiredPermissions = permissions.microphone == .authorized
                    && (systemAudioScope == .browserTab || permissions.canRecord)
                guard hasRequiredPermissions else {
                    self.presentRecordingFailure(self.permissionFailure(from: permissions))
                    return
                }
                let preferences = (try? await self.appSettingsRepository.load()) ?? .default
                let session = try await self.recordingCoordinator.start(
                    meeting: sourceMeeting,
                    microphoneDeviceID: preferences.selectedMicrophoneID,
                    systemAudioScope: systemAudioScope
                )
                if let detection = self.appState.meetingSessionDetection {
                    self.recordingCoordinator.updateMicrophoneGate(
                        from: detection,
                        at: session.startedAt
                    )
                }
                guard !Task.isCancelled else {
                    await self.recordingCoordinator.cancel()
                    return
                }
                self.appState.recordingStarted(session)
                await self.meetingSessionCoordinator.recordingStarted(at: session.startedAt)
            } catch is CancellationError {
                await self.recordingCoordinator.cancel()
            } catch {
                AppLogger.recordingOperationFailed(operation: "start", error: error)
                self.presentRecordingFailure(self.recordingFailure(from: error))
            }
        }
    }

    private func configureBrowserAudioBridge() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        do {
            browserAudioBroker.setStatusHandler { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.appState.updateBrowserAudioConnectionStatus(status)
                }
            }
            try browserAudioIPCServer.start()
            _ = try BrowserAudioNativeHostInstaller().install(bundleURL: Bundle.main.bundleURL)
            appState.updateBrowserAudioConnectionStatus(.waitingForMeetTab)
        } catch {
            browserAudioIPCServer.stop()
            browserAudioBroker.setStatusHandler(nil)
            appState.updateBrowserAudioConnectionStatus(.unavailable)
            AppLogger.recordingOperationFailed(operation: "browser-audio-bridge-start", error: error)
        }
    }

    func stopRecordingFlow() {
        prepareRecordingStopUI()
        guard appState.stopRecording() else { return }
        finalizeRecordingAfterStopRequest()
    }

    private func prepareRecordingStopUI() {
        meetingAutoStopTask?.cancel()
        meetingAutoStopTask = nil
        appState.dismissMeetingLifecyclePrompt()
    }

    private func finalizeRecordingAfterStopRequest() {
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recordingCoordinator.stop()
                await self.meetingSessionCoordinator.recordingStopped(
                    at: result.session.endedAt ?? Date()
                )
                let storedMeeting = try await self.meetingRepository.saveCapture(result)
                self.appState.recordingSaved(result, storedMeeting: storedMeeting)
                await self.enqueueForProcessing(storedMeeting)
            } catch {
                AppLogger.recordingOperationFailed(operation: "stop-and-save", error: error)
                self.presentRecordingFailure(self.recordingFailure(from: error))
            }
        }
    }

    private func handleRecordingSafetyInterruption(_ message: String) {
        prepareRecordingStopUI()
        guard appState.stopRecordingForSafety(message: message) else { return }
        presentNotch(followPointer: false)
        finalizeRecordingAfterStopRequest()
    }

    private func cancelRecordingFlow() {
        meetingAutoStopTask?.cancel()
        meetingAutoStopTask = nil
        appState.dismissMeetingLifecyclePrompt()
        switch appState.meetingFlow.phase {
        case .uploading, .transcribing, .summarizing:
            // Cancelling processing must not delete the durable recording. The worker marks
            // only its current job as cancelled/failed so it remains available for retry,
            // then a fresh drain can continue any unrelated queued meetings.
            processingRestartRequested = true
            processingTask?.cancel()
        case .preparingRecording, .recording, .finalizingAudio:
            recordingTask?.cancel()
            recordingTask = Task { [weak self] in
                guard let self else { return }
                await self.recordingCoordinator.cancel()
                await self.meetingSessionCoordinator.recordingStopped()
            }
        default:
            return
        }
        appState.cancelCurrentFlow()
    }

    private func loadStoredMeetings() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.meetingRepository.prepare()
                let recoveryReport = await self.recordingRecoveryService.recoverInterruptedCaptures()
                let meetings = try await self.meetingRepository.loadAll()
                self.appState.replaceStoredMeetings(meetings)
                self.appState.applyRecordingRecoveryReport(recoveryReport)
                await self.restoreProcessingQueue(for: meetings)
            } catch {
                AppLogger.persistenceFailed(
                    operation: "load-meetings",
                    error: error
                )
            }
        }
    }

    private func startPeriodicRetentionCleanup() {
        retentionCleanupTask?.cancel()
        retentionCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runRetentionCleanup()
                do {
                    try await Task.sleep(for: .seconds(24 * 60 * 60))
                } catch {
                    return
                }
            }
        }
    }

    private func runRetentionCleanup() async {
        do {
            let preferences = try await appSettingsRepository.load()
            let report = try await retentionCleanupService.cleanup(
                policy: preferences.meetingRetentionPolicy
            )
            report.deletedMeetingIDs.forEach { appState.removeStoredMeeting(id: $0) }
            for meetingID in report.deletedMeetingIDs {
                try? await processingQueue.remove(meetingID: meetingID)
            }
            if !report.failedMeetingIDs.isEmpty {
                AppLogger.persistenceFailed(
                    operation: "retention-cleanup",
                    failureCount: report.failedMeetingIDs.count
                )
            }
        } catch is CancellationError {
            return
        } catch {
            AppLogger.persistenceFailed(
                operation: "retention-cleanup",
                error: error
            )
        }
    }

    var meetingAnalysisActions: MeetingAnalysisActions {
        MeetingAnalysisActions(
            renameSpeaker: { [weak self] meetingID, speakerID, name in
                guard let self else { return .failed(message: "The app is quitting.") }
                guard !self.editingMeetingIDs.contains(meetingID),
                      !self.appState.processingJobs.contains(where: { $0.meetingID == meetingID }) else {
                    return .failed(message: "You can edit speakers once processing is done.")
                }
                self.editingMeetingIDs.insert(meetingID)
                defer { self.editingMeetingIDs.remove(meetingID) }
                do {
                    let meeting = try await self.meetingRepository.renameSpeaker(meetingID: meetingID, speakerID: speakerID, name: name)
                    for var task in try await self.taskCoordinator.repository.loadAll() where task.sourceMeetingID == meetingID && task.sourceSpeakerID == speakerID {
                        task.assignee = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String(name.prefix(100))
                        try await self.taskCoordinator.repository.save(task)
                    }
                    await self.taskCoordinator.reload()
                    if self.appState.presentedMeetingDetail?.id == meetingID { self.openStoredMeeting(meeting) }
                    return .succeeded(message: "Speaker updated.")
                } catch { return .failed(message: "Couldn't save the speaker. Try again.") }
            },
            importAction: { [weak self] meetingID, action in
                guard let self else { return .failed(message: "The app is quitting.") }
                do {
                    // Validate the source against persisted content, not a stale view snapshot.
                    guard let stored = try await self.meetingRepository.loadTranscription(for: meetingID),
                          let current = stored.summary?.actionItems.first(where: { $0.id == action.id }) else {
                        return .failed(message: "The task's source changed. Reopen the meeting.")
                    }
                    _ = try await self.taskCoordinator.repository.importAction(current, meetingID: meetingID)
                    await self.taskCoordinator.reload()
                    return .succeeded(message: "Added to your tasks.")
                } catch { return .failed(message: "Couldn't save the task. Try again.") }
            }
        )
    }

    private func openStoredMeeting(_ meeting: StoredMeeting) {
        Task { [weak self] in
            guard let self else { return }
            let audioURL = await self.meetingRepository.audioFileURL(for: meeting)
            let transcription: StoredTranscription?
            do {
                transcription = try await self.meetingRepository.loadTranscription(for: meeting.id)
            } catch {
                AppLogger.persistenceFailed(operation: "load-transcript-detail", error: error)
                transcription = nil
            }
            let markdown: String?
            if let stored = try? await self.meetingRepository.loadMarkdown(for: meeting.id) {
                markdown = stored
            } else if let transcription {
                markdown = MeetingMarkdownFormatter.markdown(
                    meeting: meeting,
                    transcription: transcription
                )
            } else {
                markdown = nil
            }
            self.appState.presentMeetingDetail(
                MeetingDetailContent(
                    meeting: meeting,
                    storedTranscription: transcription,
                    markdown: markdown,
                    audioURL: audioURL
                )
            )
        }
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func exportMarkdown(_ markdown: String, for meeting: StoredMeeting) {
        let panel = NSSavePanel()
        panel.title = "Save Meeting as Markdown"
        panel.nameFieldStringValue = URL(fileURLWithPath: meeting.audioFileName)
            .deletingPathExtension()
            .lastPathComponent + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try Data(markdown.utf8).write(to: destination, options: .atomic)
        } catch {
            AppLogger.persistenceFailed(operation: "export-meeting-markdown", error: error)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't save Markdown"
            alert.informativeText = "Check that you can write to the selected folder and try again."
            alert.runModal()
        }
    }

    private func openRecoveryDirectory() {
        Task { [weak self] in
            guard let self else { return }
            let directory = await self.meetingRepository.recoveryDirectoryURL()
            NSWorkspace.shared.open(directory)
        }
    }

    func deleteStoredMeeting(_ meeting: StoredMeeting) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete meeting?"
        alert.informativeText = "Audio, transcript and notes will be deleted permanently."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        deleteStoredMeetingConfirmed(meeting)
    }

    private func deleteStoredMeetingConfirmed(_ meeting: StoredMeeting) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.meetingRepository.delete(id: meeting.id)
                try? await self.processingQueue.remove(meetingID: meeting.id)
                self.appState.removeStoredMeeting(id: meeting.id)
            } catch {
                AppLogger.persistenceFailed(
                    operation: "delete-meeting",
                    error: error
                )
            }
        }
    }

    private func restoreProcessingQueue(for meetings: [StoredMeeting]) async {
        do {
            var jobs = try await processingQueue.restore()
            let existingMeetingIDs = Set(jobs.map(\.meetingID))
            for meeting in meetings
                where meeting.processingStatus == .recorded
                    && !existingMeetingIDs.contains(meeting.id) {
                let job = try await processingQueue.enqueue(meetingID: meeting.id)
                jobs.append(job)
            }
            appState.replaceProcessingJobs(jobs)
            startProcessingQueue()
        } catch {
            AppLogger.persistenceFailed(operation: "restore-processing-queue", error: error)
        }
    }

    private func enqueueForProcessing(_ meeting: StoredMeeting) async {
        do {
            let job = try await processingQueue.enqueue(meetingID: meeting.id)
            appState.upsertProcessingJob(job)
            startProcessingQueue()
        } catch {
            AppLogger.persistenceFailed(operation: "enqueue-processing-job", error: error)
        }
    }

    func retryProcessing(_ meeting: StoredMeeting) {
        guard !editingMeetingIDs.contains(meeting.id) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let jobs = try await self.processingQueue.allJobs()
                if jobs.contains(where: { $0.meetingID == meeting.id && $0.state != .failed }) { return }
                let job: ProcessingJob
                if let retried = try await self.processingQueue.retry(meetingID: meeting.id) { job = retried }
                else { job = try await self.processingQueue.enqueue(meetingID: meeting.id) }
                self.appState.upsertProcessingJob(job)
                self.startProcessingQueue()
            } catch {
                AppLogger.persistenceFailed(operation: "retry-processing-job", error: error)
            }
        }
    }

    private func startProcessingQueue() {
        guard processingTask == nil || processingTask?.isCancelled == true else {
            processingRestartRequested = true
            return
        }
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.transcriptionWorker.drain()
            self.processingTask = nil
            if self.processingRestartRequested {
                self.processingRestartRequested = false
                self.startProcessingQueue()
            }
        }
    }

    private func handleTranscriptionProcessingEvent(_ event: TranscriptionProcessingEvent) {
        switch event {
        case .started(let job):
            appState.processingStarted(job)
        case .uploadProgress(_, let progress):
            appState.updateTranscriptionUploadProgress(progress)
        case .transcribing:
            appState.processingBeganTranscribing()
        case .summarizing:
            appState.processingBeganSummarizing()
        case .completed(let meeting):
            appState.processingCompleted(meeting)
            if appState.presentedMeetingDetail?.id == meeting.id {
                openStoredMeeting(meeting)
            }
            if appState.processingJobs.isEmpty {
                presentTransientStatus(appState.meetingFlow)
            }
        case .failed(let job, let error):
            appState.processingFailed(job, error: error)
            presentTransientStatus(appState.meetingFlow)
        }
    }

    private func presentRecordingFailure(_ failure: AppFailure) {
        appState.recordingFailed(failure)
        presentTransientStatus(appState.meetingFlow)
    }

    private func presentTransientStatus(_ state: MeetingFlowState) {
        guard NotchTransientStatusPolicy.shouldPresent(state) else { return }
        transientStatusTask?.cancel()
        transientStatusTask = Task { [weak self] in
            guard let self else { return }
            // Results are a strip under the closed notch; it folds away after 8 s.
            self.notch.pulse()
            do {
                try await Task.sleep(for: NotchTransientStatusPolicy.displayDuration)
            } catch {
                return
            }

            guard self.appState.meetingFlow == state else { return }
            guard !self.notch.isHovering, !self.appState.isNotchPinned else { return }
            if NotchTransientStatusPolicy.shouldResetAfterTimeout(state) {
                self.appState.resetFlow()
            }
        }
    }

    private func recordingFailure(from error: Error) -> AppFailure {
        if error is MeetingRepositoryError {
            return .fileSystem("Couldn't save the meeting files. Try again.")
        }
        guard let captureError = error as? RecordingCaptureError else {
            return .recording("Couldn't finish the recording. Try again.")
        }

        switch captureError {
        case .microphonePermissionDenied, .systemAudioPermissionDenied:
            return .permission("Turn on audio access for recording in System Settings.", settings: true)
        case .insufficientDiskSpace, .diskSpaceBecameLow:
            return .fileSystem("Not enough free disk space to record.", diskFull: true)
        case .alreadyRecording:
            return .recording("A recording is already in progress.", retryable: false)
        case .noMicrophone:
            return .recording("No microphone available.", retryable: false)
        case .noDisplay:
            return .recording("No display available to capture system audio.")
        case .meetingProcessUnavailable:
            return .recording(
                "Couldn't safely verify the meeting audio. Try again with the meeting app open."
            )
        case .browserMeetingAudioIsolationUnavailable:
            return AppFailure(
                category: .recording,
                title: "Couldn't safely isolate Google Meet audio",
                message: "To protect your privacy, Crenel didn't fall back to recording all system audio and started no recording. Continue the call without recording, or use the Zoom desktop app.",
                recoveryAction: .dismiss
            )
        case .sourceDidNotProduceAudio(let source), .sourceFailed(let source, _):
            return .recording("Couldn't finish recording \(source.displayName). Check the connection and try again.")
        }
    }

    private func permissionFailure(
        from permissions: AudioCapturePermissionSnapshot
    ) -> AppFailure {
        if permissions.microphone != .authorized {
            return .permission(
                "Turn on microphone access in System Settings > Privacy & Security > Microphone.",
                settings: permissions.microphone.requiresSystemSettings
            )
        }
        return .permission(
            "To record system audio, turn on System Audio Recording access.",
            settings: permissions.systemAudio.requiresSystemSettings
        )
    }

    private func recover(from failure: AppFailure) {
        switch failure.recoveryAction {
        case .openSystemSettings:
            let permissions = audioPermissionService.currentSnapshot()
            let source: AudioSourceKind = permissions.microphone != .authorized
                ? .microphone
                : .systemAudio
            appState.recoverFromFailure()
            if source == .systemAudio {
                requestSystemAudioAccess()
            } else {
                openSystemSettings(for: source)
            }
        case .requestPermission:
            appState.recoverFromFailure()
            beginRecording()
        default:
            appState.recoverFromFailure()
        }
    }

    func refreshAudioPermissions() {
        refreshAudioPermissions(recheckingFor: nil)
    }

    private func refreshAudioPermissions(recheckingFor duration: Duration?) {
        permissionRefreshTask?.cancel()
        appState.updateAudioCapturePermissions(audioPermissionService.currentSnapshot())
        guard let duration else { return }

        permissionRefreshTask = Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: duration)
            while !Task.isCancelled, clock.now < deadline {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    return
                }
                guard let self else { return }
                let snapshot = self.audioPermissionService.currentSnapshot()
                self.appState.updateAudioCapturePermissions(snapshot)
                if snapshot.canRecord { return }
            }
        }
    }

    private func presentMeetingReminder() {
        // The closed notch carries the reminder itself: amber minutes and a burning fuse,
        // then the "Starting now" strip. It never opens the panel on its own.
        reminderPresentationTask?.cancel()
        reminderPresentationTask = nil
        notch.pulse()
    }
}
