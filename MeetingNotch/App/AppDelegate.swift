import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var reminderPresentationTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var terminationCleanupTask: Task<Void, Never>?
    private var retentionCleanupTask: Task<Void, Never>?
    private var notchHoverObservation: AnyCancellable?
    private var screenParametersObservation: AnyCancellable?
    private var activeNotchScreen: NSScreen?
    private let notchScreenResolver = NotchScreenResolver()
    private let audioPermissionService = AudioCapturePermissionService()
    private lazy var meetingMonitor = MeetingMonitor(provider: EventKitMeetingProvider())
    private lazy var meetingRepository: any MeetingRepository = FileMeetingRepository()
    private let appSettingsRepository: any AppSettingsRepository = UserDefaultsAppSettingsRepository()
    private lazy var recordingRecoveryService = RecordingRecoveryService(repository: meetingRepository)
    private lazy var retentionCleanupService = MeetingRetentionCleanupService(
        repository: meetingRepository
    )
    private lazy var recordingCoordinator: RecordingCoordinator = {
        let coordinator = RecordingCoordinator()
        coordinator.onStatusChange = { [weak self] status in
            self?.appState.updateRecordingCaptureStatus(status)
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
                onDeleteStoredMeeting: { [weak self] meeting in self?.deleteStoredMeeting(meeting) },
                onOpenRecovery: { [weak self] in self?.openRecoveryDirectory() },
                onTogglePin: { [weak self] in self?.toggleNotchPin() }
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
        configureMeetingMonitor()
        configureNotchInteraction()
        refreshAudioPermissions()
        meetingMonitor.start()
        loadStoredMeetings()
        startPeriodicRetentionCleanup()

        Task {
            let screen = resolvedActiveNotchScreen(preferPhysicalNotch: true)
            await notch.compact(on: screen)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        reminderPresentationTask?.cancel()
        recordingTask?.cancel()
        terminationCleanupTask?.cancel()
        retentionCleanupTask?.cancel()
        notchHoverController.cancel()
        notchHoverObservation = nil
        screenParametersObservation = nil
        meetingMonitor.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAudioPermissions()
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
        let snapshot = audioPermissionService.requestSystemAudioAccess()
        appState.updateAudioCapturePermissions(snapshot)
    }

    func openSystemSettings(for source: AudioSourceKind) {
        let pane = switch source {
        case .microphone:
            "Privacy_Microphone"
        case .systemAudio:
            "Privacy_ScreenCapture"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
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

    private func configureNotchInteraction() {
        notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
            openingAnimation: .smooth(duration: 0.28),
            closingAnimation: .smooth(duration: 0.2),
            conversionAnimation: .smooth(duration: 0.3),
            skipIntermediateHides: true
        )
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
                    self.appState.recordingFailed(self.permissionFailure(from: permissions))
                    return
                }
                let session = try await self.recordingCoordinator.start(meeting: sourceMeeting)
                guard !Task.isCancelled else {
                    await self.recordingCoordinator.cancel()
                    return
                }
                self.appState.recordingStarted(session)
            } catch is CancellationError {
                await self.recordingCoordinator.cancel()
            } catch {
                AppLogger.recordingOperationFailed(operation: "start", error: error)
                self.appState.recordingFailed(self.recordingFailure(from: error))
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
            } catch {
                AppLogger.recordingOperationFailed(operation: "stop-and-save", error: error)
                self.appState.recordingFailed(self.recordingFailure(from: error))
            }
        }
    }

    private func cancelRecordingFlow() {
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            await self.recordingCoordinator.cancel()
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
            } catch {
                AppLogger.persistenceFailed(
                    operation: "load-meetings",
                    message: error.localizedDescription
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
            if !report.failedMeetingIDs.isEmpty {
                AppLogger.persistenceFailed(
                    operation: "retention-cleanup",
                    message: "\(report.failedMeetingIDs.count) toplantı silinemedi."
                )
            }
        } catch is CancellationError {
            return
        } catch {
            AppLogger.persistenceFailed(
                operation: "retention-cleanup",
                message: error.localizedDescription
            )
        }
    }

    private func openStoredMeeting(_ meeting: StoredMeeting) {
        Task { [weak self] in
            guard let self else { return }
            let audioURL = await self.meetingRepository.audioFileURL(for: meeting)
            NSWorkspace.shared.activateFileViewerSelecting([audioURL])
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

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.meetingRepository.delete(id: meeting.id)
                self.appState.removeStoredMeeting(id: meeting.id)
            } catch {
                AppLogger.persistenceFailed(
                    operation: "delete-meeting",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func recordingFailure(from error: Error) -> AppFailure {
        if error is MeetingRepositoryError {
            return .fileSystem(error.localizedDescription)
        }
        guard let captureError = error as? RecordingCaptureError else {
            return .recording(error.localizedDescription)
        }

        switch captureError {
        case .microphonePermissionDenied, .systemAudioPermissionDenied:
            return .permission(captureError.localizedDescription, settings: true)
        case .insufficientDiskSpace:
            return .fileSystem(captureError.localizedDescription, diskFull: true)
        default:
            return .recording(captureError.localizedDescription)
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
            "Sistem sesini kaydetmek için Ekran ve Sistem Sesi Kaydı iznini açın.",
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
            openSystemSettings(for: source)
            appState.recoverFromFailure()
        case .requestPermission:
            appState.recoverFromFailure()
            beginRecording()
        default:
            appState.recoverFromFailure()
        }
    }

    func refreshAudioPermissions() {
        appState.updateAudioCapturePermissions(audioPermissionService.currentSnapshot())
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
