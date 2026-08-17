import AppKit
import Combine
import DynamicNotchKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var reminderPresentationTask: Task<Void, Never>?
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
    private let notchScreenResolver = NotchScreenResolver()
    private let audioPermissionService = AudioCapturePermissionService()
    private let microphoneDeviceService = MicrophoneDeviceService()
    private let applicationRelauncher = ApplicationRelauncher()
    private let microphoneGateHotKey = GlobalHotKeyMonitor()
    private let browserAudioBroker = BrowserAudioStreamBroker()
    private lazy var browserAudioIPCServer = BrowserAudioIPCServer(broker: browserAudioBroker)
    private let launchAtLoginService: any LaunchAtLoginServicing = LaunchAtLoginService()
    private lazy var meetingMonitor = MeetingMonitor(provider: EventKitMeetingProvider())
    private lazy var meetingSessionCoordinator = MeetingSessionCoordinator()
    private lazy var meetingRepository: any MeetingRepository = FileMeetingRepository()
    private let taskRepository: any TaskRepository = FileTaskRepository()
    private let appSettingsRepository: any AppSettingsRepository = UserDefaultsAppSettingsRepository()
    private let apiKeyRepository: any APIKeyRepository = KeychainAPIKeyRepository()
    private let processingQueue = ProcessingQueue()
    private lazy var transcriptionWorker = TranscriptionProcessingWorker(
        queue: processingQueue,
        meetingRepository: meetingRepository,
        settingsRepository: appSettingsRepository,
        transcriptionService: ElevenLabsTranscriptionService(
            apiKeyRepository: apiKeyRepository
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
                    connectionState.message ?? "Sistem sesi akışı koptu."
                )
            }
        }
        coordinator.onSafetyInterruption = { [weak self] error in
            self?.handleRecordingSafetyInterruption(
                error.errorDescription ?? "Kayıt güvenliği için kayıt durduruluyor."
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

    private lazy var notch: DynamicNotch<AnyView, AnyView, AnyView> = DynamicNotch(
        hoverBehavior: NotchShadowPolicy.hoverBehavior
    ) {
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
                onAddTask: { [weak self] title in self?.addTask(title: title) },
                onUpdateTask: { [weak self] task, title in self?.updateTask(task, title: title) },
                onChangeTaskStatus: { [weak self] task, status in
                    self?.changeTaskStatus(task, to: status)
                },
                onArchiveTask: { [weak self] task in self?.archiveTask(task) },
                onRestoreTask: { [weak self] task in self?.restoreTask(task) },
                onDeleteTask: { [weak self] task in self?.deleteTask(task) },
                onDeleteArchive: { [weak self] in self?.deleteTaskArchive() },
                onRelaunchApplication: { [weak self] in self?.relaunchApplication() }
            )
                .environmentObject(self.appState)
        )
    } compactLeading: {
        AnyView(
            CompactLeadingView()
                .environmentObject(self.appState)
        )
    } compactTrailing: {
        AnyView(
            CompactTrailingView()
                .environmentObject(self.appState)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MultipartFormFileBuilder.removeStaleUploadBodies()
        configureBrowserAudioBridge()
        configureMeetingSessionCoordinator()
        microphoneGateHotKey.start { [weak self] in
            self?.toggleMeetingMicrophoneGate()
        }
        configureMeetingMonitor()
        configureNotchInteraction()
        configureWorkspacePowerEvents()
        configureMicrophoneDevices()
        refreshAudioPermissions()
        refreshAccessibilityPermission()
        loadStoredMeetings()
        loadTasks()
        startPeriodicRetentionCleanup()
        loadInitialPreferences()

        Task {
            let screen = resolvedActiveNotchScreen(preferPhysicalNotch: true)
            await notch.compact(on: screen)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        launchPendingRelaunchIfNeeded()
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
            ? "Kayıt devam ediyor"
            : "Toplantı işlenmeye devam ediyor"
        alert.informativeText = "Şimdi çıkarsanız mevcut işlem durdurulacak."
        alert.addButton(withTitle: "İşlemi Durdur ve Çık")
        alert.addButton(withTitle: "Vazgeç")

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

    func showMeetingNotch() {
        presentNotch(followPointer: true)
    }

    func startManualRecording() {
        beginRecording()
        presentNotch(followPointer: true)
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
            meetingRetentionPolicy: preferences.meetingRetentionPolicy
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
            return .failed(message: "Seçilen mikrofon artık bağlı değil. Listeyi yenileyin.")
        }

        do {
            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.selectedMicrophoneID = deviceID
            try await appSettingsRepository.save(preferences)
            appState.updateSelectedMicrophoneID(deviceID)
            return .succeeded(message: deviceID == nil ? "Sistem varsayılanı kullanılacak." : "Mikrofon seçimi kaydedildi.")
        } catch {
            AppLogger.persistenceFailed(operation: "save-microphone-settings", error: error)
            return .failed(message: "Mikrofon seçimi kaydedilemedi. Tekrar deneyin.")
        }
    }

    func saveGeneralSettings(
        _ snapshot: GeneralSettingsSnapshot
    ) async -> SettingsActionResult {
        guard (60...(60 * 60)).contains(snapshot.reminderLeadTime) else {
            return .failed(message: "Hatırlatma süresi 1–60 dakika arasında olmalıdır.")
        }

        do {
            try launchAtLoginService.setEnabled(snapshot.launchAtLogin)
            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.reminderLeadTime = snapshot.reminderLeadTime
            preferences.isCalendarEnabled = snapshot.isCalendarEnabled
            preferences.launchAtLogin = snapshot.launchAtLogin
            preferences.meetingRetentionPolicy = snapshot.meetingRetentionPolicy
            try await appSettingsRepository.save(preferences)
            applyRuntimePreferences(preferences)
            await runRetentionCleanup()

            return .succeeded(
                message: launchAtLoginService.requiresApproval
                    ? "Login’de açma için Sistem Ayarları’nda onay gerekiyor."
                    : nil
            )
        } catch {
            AppLogger.persistenceFailed(operation: "save-general-settings", error: error)
            return .failed(message: "Genel ayarlar kaydedilemedi. Tekrar deneyin.")
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
            return .failed(message: "Onboarding yeniden başlatılamadı.")
        }
    }

    func deleteAllData() async -> SettingsActionResult {
        guard !appState.requiresTerminationConfirmation else {
            return .failed(message: "Kayıt veya işleme sürerken tüm veriler silinemez.")
        }

        processingTask?.cancel()
        if let processingTask {
            await processingTask.value
        }
        self.processingTask = nil
        processingRestartRequested = false
        meetingMonitor.stop()
        appState.dismissMeetingDetail()

        var keychainDeletionFailed = false
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
                    message: "Yerel veriler silindi ancak en az bir Keychain anahtarı kaldı. Tekrar deneyin."
                )
            }
            return .succeeded(message: "Tüm toplantı, görev, ayar ve API anahtarı verileri silindi.")
        } catch {
            AppLogger.persistenceFailed(operation: "delete-all-data", error: error)
            return .failed(message: "Tüm veriler tamamen silinemedi. Tekrar deneyin.")
        }
    }

    func saveTranscriptionSettings(
        languageCode: String?,
        apiKey: String?
    ) async -> TranscriptionSettingsSaveResult {
        do {
            let normalizedInput = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = if let normalizedInput, !normalizedInput.isEmpty {
                normalizedInput
            } else {
                try await apiKeyRepository.apiKey() ?? ""
            }
            try await ElevenLabsAPIKeyValidator().validate(key)
            if let normalizedInput, !normalizedInput.isEmpty {
                try await apiKeyRepository.saveAPIKey(normalizedInput)
            }

            var preferences = (try? await appSettingsRepository.load()) ?? .default
            preferences.transcription.languageCode = languageCode
            try await appSettingsRepository.save(preferences)

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

    func deleteTranscriptionAPIKey() async -> SettingsActionResult {
        do {
            try await apiKeyRepository.deleteAPIKey()
            return .succeeded(message: "ElevenLabs bağlantısı kaldırıldı.")
        } catch {
            AppLogger.persistenceFailed(operation: "delete-transcription-key", error: error)
            return .failed(message: "API anahtarı Keychain’den kaldırılamadı.")
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
            self?.appState.updateUpcomingMeetings(meetings)
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
            presentNotch(followPointer: false)
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
            if !preferences.hasCompletedOnboarding {
                self.presentOnboarding()
            }
        }
    }

    private func applyRuntimePreferences(_ preferences: AppPreferences) {
        appState.updateSelectedMicrophoneID(preferences.selectedMicrophoneID)
        meetingMonitor.configure(
            isEnabled: preferences.isCalendarEnabled,
            reminderLeadTime: preferences.reminderLeadTime
        )
    }

    private func presentOnboarding() {
        if let onboardingWindowController {
            onboardingWindowController.showWindow(nil)
            onboardingWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = OnboardingView(
            onRequestMicrophoneAccess: { [weak self] in self?.requestMicrophoneAccess() },
            onRequestSystemAudioAccess: { [weak self] in self?.requestSystemAudioAccess() },
            onRequestAccessibilityAccess: { [weak self] in self?.requestAccessibilityAccess() },
            onRequestCalendarAccess: { [weak self] in self?.requestCalendarAccess() },
            onComplete: { [weak self] in self?.completeOnboarding() }
        )
        .environmentObject(appState)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MeetingNotch’a Hoş Geldiniz"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 640, height: 500))
        window.minSize = NSSize(width: 600, height: 460)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeOnboarding() {
        Task { [weak self] in
            guard let self else { return }
            do {
                var preferences = (try? await self.appSettingsRepository.load()) ?? .default
                preferences.hasCompletedOnboarding = true
                try await self.appSettingsRepository.save(preferences)
                self.applyRuntimePreferences(preferences)
                self.onboardingWindowController?.close()
                self.onboardingWindowController = nil
            } catch {
                AppLogger.persistenceFailed(operation: "complete-onboarding", error: error)
            }
        }
    }

    private func configureNotchInteraction() {
        updateNotchTransitionConfiguration()
        notchHoverObservation = notch.$isHovering
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
        let profile = NotchMotionProfile.resolved(
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if profile.reducesMotion {
            notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
                openingAnimation: .linear(duration: profile.openingDuration),
                closingAnimation: .linear(duration: profile.closingDuration),
                conversionAnimation: .linear(duration: profile.conversionDuration),
                skipIntermediateHides: true
            )
        } else {
            notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
                openingAnimation: .smooth(duration: profile.openingDuration),
                closingAnimation: .smooth(duration: profile.closingDuration),
                conversionAnimation: .smooth(duration: profile.conversionDuration),
                skipIntermediateHides: true
            )
        }
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
        appState.updateNotchPanelPresentation(
            availableSize: screen.visibleFrame.size,
            hasPhysicalNotch: notchScreenResolver.hasPhysicalNotch(screen)
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
        Task {
            await meetingMonitor.requestAccess()
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

    private func openMeetingURL(_ url: URL) {
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
        let sourceMeeting = appState.nextMeeting
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

    private func stopRecordingFlow() {
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

    private func loadTasks() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.taskRepository.prepare()
                self.appState.replaceTasks(try await self.taskRepository.loadAll())
            } catch {
                AppLogger.persistenceFailed(operation: "load-tasks", error: error)
            }
        }
    }

    private func addTask(title: String) {
        guard let title = TaskItem.normalizedTitle(title) else { return }
        persistTask(TaskItem(title: title), operation: "add-task")
    }

    private func updateTask(_ task: TaskItem, title: String) {
        guard let title = TaskItem.normalizedTitle(title) else { return }
        var updated = task
        updated.title = title
        persistTask(updated, operation: "update-task")
    }

    private func changeTaskStatus(_ task: TaskItem, to status: TaskStatus) {
        var updated = task
        updated.setStatus(status)
        persistTask(updated, operation: "change-task-status")
    }

    private func archiveTask(_ task: TaskItem) {
        var updated = task
        updated.archive()
        persistTask(updated, operation: "archive-task")
    }

    private func restoreTask(_ task: TaskItem) {
        var updated = task
        updated.restore()
        persistTask(updated, operation: "restore-task")
    }

    private func persistTask(_ task: TaskItem, operation: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.taskRepository.save(task)
                self.appState.upsertTask(task)
            } catch {
                AppLogger.persistenceFailed(operation: operation, error: error)
            }
        }
    }

    private func deleteTask(_ task: TaskItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.taskRepository.delete(id: task.id)
                self.appState.removeTask(id: task.id)
            } catch {
                AppLogger.persistenceFailed(operation: "delete-task", error: error)
            }
        }
    }

    private func deleteTaskArchive() {
        let archived = appState.archivedTasks
        guard !archived.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            for task in archived {
                do {
                    try await self.taskRepository.delete(id: task.id)
                    self.appState.removeTask(id: task.id)
                } catch {
                    AppLogger.persistenceFailed(operation: "delete-task-archive", error: error)
                }
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

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func exportMarkdown(_ markdown: String, for meeting: StoredMeeting) {
        let panel = NSSavePanel()
        panel.title = "Toplantıyı Markdown Olarak Kaydet"
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
            alert.messageText = "Markdown kaydedilemedi"
            alert.informativeText = "Seçtiğiniz klasöre yazma iznini kontrol edip tekrar deneyin."
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

    private func deleteStoredMeeting(_ meeting: StoredMeeting) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Toplantı silinsin mi?"
        alert.informativeText = "“\(meeting.title)” kaydı ve bağlı ses dosyaları kalıcı olarak silinecek."
        alert.addButton(withTitle: "Sil")
        alert.addButton(withTitle: "Vazgeç")
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

    private func retryProcessing(_ meeting: StoredMeeting) {
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let job = try await self.processingQueue.retry(meetingID: meeting.id) else {
                    return
                }
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
            await self.expandNotch(followPointer: false)
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
            self.notchHoverController.markCompact()
            await self.notch.compact(on: self.resolvedActiveNotchScreen())
        }
    }

    private func recordingFailure(from error: Error) -> AppFailure {
        if error is MeetingRepositoryError {
            return .fileSystem("Toplantı dosyaları kaydedilemedi. Tekrar deneyin.")
        }
        guard let captureError = error as? RecordingCaptureError else {
            return .recording("Kayıt işlemi tamamlanamadı. Tekrar deneyin.")
        }

        switch captureError {
        case .microphonePermissionDenied, .systemAudioPermissionDenied:
            return .permission("Kayıt için gerekli ses iznini Sistem Ayarları'ndan açın.", settings: true)
        case .insufficientDiskSpace, .diskSpaceBecameLow:
            return .fileSystem("Kayıt için yeterli boş disk alanı yok.", diskFull: true)
        case .alreadyRecording:
            return .recording("Zaten devam eden bir kayıt var.", retryable: false)
        case .noMicrophone:
            return .recording("Kullanılabilir bir mikrofon bulunamadı.", retryable: false)
        case .noDisplay:
            return .recording("Sistem sesini yakalamak için kullanılabilir ekran bulunamadı.")
        case .meetingProcessUnavailable:
            return .recording(
                "Toplantı sesi güvenli biçimde doğrulanamadı. Toplantı istemcisi açıkken tekrar deneyin."
            )
        case .browserMeetingAudioIsolationUnavailable:
            return AppFailure(
                category: .recording,
                title: "Google Meet sesi güvenli ayrılamadı",
                message: "MeetingNotch gizlilik için global ses kaydına geçmedi ve hiçbir kayıt başlatmadı. Güvenli fallback olarak görüşmeye kayıtsız devam edin veya Zoom masaüstü istemcisini kullanın.",
                recoveryAction: .dismiss
            )
        case .sourceDidNotProduceAudio(let source), .sourceFailed(let source, _):
            return .recording("\(source.displayName) kaydı tamamlanamadı. Bağlantıyı kontrol edip tekrar deneyin.")
        }
    }

    private func permissionFailure(
        from permissions: AudioCapturePermissionSnapshot
    ) -> AppFailure {
        if permissions.microphone != .authorized {
            return .permission(
                "Mikrofon erişimini Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon bölümünden açın.",
                settings: permissions.microphone.requiresSystemSettings
            )
        }
        return .permission(
            "Sistem sesini kaydetmek için Sistem Sesini Kaydetme iznini açın.",
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
        reminderPresentationTask?.cancel()
        reminderPresentationTask = Task { [weak self] in
            guard let self else { return }
            await self.expandNotch(followPointer: true)
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, case .upcomingMeeting = self.appState.meetingFlow else {
                return
            }
            guard !self.notch.isHovering, !self.appState.isNotchPinned else { return }
            self.notchHoverController.markCompact()
            await self.notch.compact(on: self.resolvedActiveNotchScreen())
        }
    }
}
