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
    private var pendingRelaunchURL: URL?
    private var processingRestartRequested = false
    private var notchHoverObservation: AnyCancellable?
    private var screenParametersObservation: AnyCancellable?
    private var accessibilityDisplayObservation: AnyCancellable?
    private var activeNotchScreen: NSScreen?
    private var onboardingWindowController: NSWindowController?
    private let notchScreenResolver = NotchScreenResolver()
    private let audioPermissionService = AudioCapturePermissionService()
    private let microphoneDeviceService = MicrophoneDeviceService()
    private let applicationRelauncher = ApplicationRelauncher()
    private let launchAtLoginService: any LaunchAtLoginServicing = LaunchAtLoginService()
    private lazy var meetingMonitor = MeetingMonitor(provider: EventKitMeetingProvider())
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
        let coordinator = RecordingCoordinator()
        coordinator.onStatusChange = { [weak self] status in
            self?.appState.updateRecordingCaptureStatus(status)
        }
        coordinator.onSourceConnectionChange = { [weak self] _, connectionState in
            guard connectionState.needsAttention else { return }
            self?.presentNotch(followPointer: false)
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
        hoverBehavior: [.keepVisible, .increaseShadow]
    ) {
        AnyView(
            NotchPanelView(
                onRequestCalendarAccess: { [weak self] in
                    self?.requestCalendarAccess()
                },
                onOpenMeetingURL: { url in
                    NSWorkspace.shared.open(url)
                },
                onStartRecording: { [weak self] in self?.beginRecording() },
                onStopRecording: { [weak self] in self?.stopRecordingFlow() },
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
                onCompleteTask: { [weak self] task in self?.setTask(task, completed: true) },
                onRestoreTask: { [weak self] task in self?.setTask(task, completed: false) },
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
        configureMeetingMonitor()
        configureNotchInteraction()
        configureMicrophoneDevices()
        refreshAudioPermissions()
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
        notchHoverController.cancel()
        notchHoverObservation = nil
        screenParametersObservation = nil
        accessibilityDisplayObservation = nil
        meetingMonitor.stop()
        microphoneDeviceService.stopMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAudioPermissions(recheckingFor: .seconds(3))
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

        meetingMonitor.onSnapshotChange = { [weak self] snapshot, shouldPresent in
            guard let self else { return }
            let willPresent = self.appState.applyMeetingSnapshot(
                snapshot,
                shouldPresent: shouldPresent
            )
            guard willPresent else { return }
            self.presentMeetingReminder()
        }
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
        appState.updateNotchPanelAvailableSize(targetScreen.visibleFrame.size)
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
        appState.updateNotchPanelAvailableSize(screen.visibleFrame.size)
        return screen
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

    private func requestCalendarAccess() {
        Task {
            await meetingMonitor.requestAccess()
        }
    }

    private func beginRecording() {
        let sourceMeeting = appState.nextMeeting
        guard appState.prepareForRecording() else { return }

        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let permissions = await self.audioPermissionService.verifyAccessForRecording()
                self.appState.updateAudioCapturePermissions(permissions)
                guard permissions.canRecord else {
                    self.presentRecordingFailure(self.permissionFailure(from: permissions))
                    return
                }
                let preferences = (try? await self.appSettingsRepository.load()) ?? .default
                let session = try await self.recordingCoordinator.start(
                    meeting: sourceMeeting,
                    microphoneDeviceID: preferences.selectedMicrophoneID
                )
                guard !Task.isCancelled else {
                    await self.recordingCoordinator.cancel()
                    return
                }
                self.appState.recordingStarted(session)
            } catch is CancellationError {
                await self.recordingCoordinator.cancel()
            } catch {
                AppLogger.recordingOperationFailed(operation: "start", error: error)
                self.presentRecordingFailure(self.recordingFailure(from: error))
            }
        }
    }

    private func stopRecordingFlow() {
        guard appState.stopRecording() else { return }
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recordingCoordinator.stop()
                let storedMeeting = try await self.meetingRepository.saveCapture(result)
                self.appState.recordingSaved(result, storedMeeting: storedMeeting)
                await self.enqueueForProcessing(storedMeeting)
            } catch {
                AppLogger.recordingOperationFailed(operation: "stop-and-save", error: error)
                self.presentRecordingFailure(self.recordingFailure(from: error))
            }
        }
    }

    private func cancelRecordingFlow() {
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

    private func setTask(_ task: TaskItem, completed: Bool) {
        var updated = task
        updated.completedAt = completed ? Date() : nil
        persistTask(updated, operation: completed ? "archive-task" : "restore-task")
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
        case .insufficientDiskSpace:
            return .fileSystem("Kayıt için yeterli boş disk alanı yok.", diskFull: true)
        case .alreadyRecording:
            return .recording("Zaten devam eden bir kayıt var.", retryable: false)
        case .noMicrophone:
            return .recording("Kullanılabilir bir mikrofon bulunamadı.", retryable: false)
        case .noDisplay:
            return .recording("Sistem sesini yakalamak için kullanılabilir ekran bulunamadı.")
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
