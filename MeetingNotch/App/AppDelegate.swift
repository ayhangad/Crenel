import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var reminderPresentationTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var terminationCleanupTask: Task<Void, Never>?
    private lazy var meetingMonitor = MeetingMonitor(provider: EventKitMeetingProvider())
    private lazy var recordingCoordinator: RecordingCoordinator = {
        let coordinator = RecordingCoordinator()
        coordinator.onStatusChange = { [weak self] status in
            self?.appState.updateRecordingCaptureStatus(status)
        }
        return coordinator
    }()

    private lazy var notch: DynamicNotch<AnyView, AnyView, AnyView> = DynamicNotch {
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
                onCancelFlow: { [weak self] in self?.cancelRecordingFlow() }
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
        configureStatusItem()
        configureMeetingMonitor()
        meetingMonitor.start()

        Task {
            await notch.compact()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        reminderPresentationTask?.cancel()
        recordingTask?.cancel()
        terminationCleanupTask?.cancel()
        meetingMonitor.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    @objc private func showMeetingNotch() {
        Task {
            await notch.expand()
        }
    }

    @objc private func startRecording() {
        beginRecording()
        Task {
            await notch.expand()
        }
    }

    @objc private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshCalendar() {
        Task {
            await meetingMonitor.refresh()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.badge.mic",
            accessibilityDescription: "MeetingNotch"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "MeetingNotch'u Aç", action: #selector(showMeetingNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Kaydı Başlat", action: #selector(startRecording), keyEquivalent: "r")
        menu.addItem(withTitle: "Takvimi Yenile", action: #selector(refreshCalendar), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ayarlar…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çıkış", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
        self.statusItem = statusItem
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
                let session = try await self.recordingCoordinator.start(meeting: sourceMeeting)
                guard !Task.isCancelled else {
                    await self.recordingCoordinator.cancel()
                    return
                }
                self.appState.recordingStarted(session)
            } catch is CancellationError {
                await self.recordingCoordinator.cancel()
            } catch {
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
                self.appState.recordingSaved(result)
            } catch {
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

    private func recordingFailure(from error: Error) -> AppFailure {
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

    private func presentMeetingReminder() {
        reminderPresentationTask?.cancel()
        reminderPresentationTask = Task { [weak self] in
            guard let self else { return }
            await self.notch.expand()
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, case .upcomingMeeting = self.appState.meetingFlow else {
                return
            }
            await self.notch.compact()
        }
    }
}
