import AppKit
import SwiftUI
import XCTest
@testable import Crenel

/// Settings and Onboarding in the "gece sürüşü" language: every prototype state
/// (`s-*`, `ob-*`) rendered offscreen with real models. PNGs are written to
/// `artifacts/ui-audit/settings/` and `artifacts/ui-audit/onboarding/` when
/// `/tmp/CrenelExportUIAudit` exists, to be compared with the prototype.
@MainActor
final class SettingsGalleryTests: XCTestCase {
    /// The area right of the app sidebar in the 1240×760 window.
    private static let settingsSize = CGSize(width: 1016, height: 760)

    // MARK: Fixtures

    private struct Fixture {
        var category: SettingsCategory
        var state: AppState
        var general = GeneralSettingsSnapshot(reminderLeadTime: 5 * 60, isCalendarEnabled: true, launchAtLogin: true,
                                              meetingRetentionPolicy: .keepForever, selectedCalendarIDs: ["work", "family"])
        var preferences = CrenelPreferences.default
        var hasAnthropicKey = false
        var hasOpenAIKey = false
        var hasElevenLabsKey = true
        var showsNotifications = false
        var query = ""
    }

    /// Everything connected and allowed, as in the prototype's resting states.
    private func fixture(_ category: SettingsCategory, state: AppState? = nil) -> Fixture {
        let state = state ?? AppState()
        state.updateDictationAvailability(.ready)
        state.updateAccessibilityPermission(granted: true)
        state.updateTaskStorageStatus(.reminders(listTitle: "Crenel"))
        state.updateCalendarAccessState(.authorized)
        state.updateCalendarIntegrationSnapshot(CalendarIntegrationSnapshot(
            sources: [CalendarSourceSummary(kind: .google, calendarCount: 3), CalendarSourceSummary(kind: .iCloud, calendarCount: 2)],
            scannedEventCount: 42, matchedMeetingCount: 6, refreshedAt: Date().addingTimeInterval(-300),
            calendars: [CalendarChoice(id: "work", title: "Work"), CalendarChoice(id: "personal", title: "Personal"),
                        CalendarChoice(id: "family", title: "Family")]
        ))
        state.updateAudioCapturePermissions(AudioCapturePermissionSnapshot(microphone: .authorized, systemAudio: .authorized))
        state.replaceStoredMeetings((0..<12).map { index in
            StoredMeeting(id: UUID(), title: "Design review \(index)", startedAt: Date().addingTimeInterval(-3_600 * Double(index + 2)),
                          endedAt: Date().addingTimeInterval(-3_600 * Double(index + 1)), sourceMeeting: nil,
                          audioFileName: "fixture.m4a", processingStatus: .completed)
        })
        return Fixture(category: category, state: state)
    }

    private func view(_ fixture: Fixture) -> some View {
        let microphones = [MicrophoneDevice(id: "built-in", name: "MacBook Pro Microphone", isSystemDefault: true),
                           MicrophoneDevice(id: "airpods", name: "AirPods Pro", isSystemDefault: false)]
        return SettingsView(
            onLoadGeneralSettings: { fixture.general },
            onLoadMicrophoneSettings: { MicrophoneSettingsSnapshot(devices: microphones, selectedDeviceID: "built-in") },
            onLoadTranscriptionSettings: { TranscriptionSettingsSnapshot(languageCode: nil, hasStoredAPIKey: fixture.hasElevenLabsKey) },
            openAISettings: OpenAISettingsActions(hasKey: { fixture.hasOpenAIKey }),
            crenelSettings: CrenelSettingsActions(load: { fixture.preferences }, hasAnthropicKey: { fixture.hasAnthropicKey }),
            notificationService: fixture.showsNotifications ? MeetingNotificationService() : nil,
            initialCategory: fixture.category,
            onLoadDataFolder: { SettingsDataFolder(path: "~/Library/Application Support/Crenel", bytes: 2_100_000_000) },
            initialQuery: fixture.query
        )
        .environmentObject(fixture.state)
    }

    private func export(_ fixture: Fixture, _ name: String) throws {
        try render(view(fixture), folder: "settings", name: name, size: Self.settingsSize)
    }

    // MARK: Settings

    func testGeneralPage() throws {
        try export(fixture(.general), "s-general")
    }

    func testDictationPages() throws {
        var ready = fixture(.dictation)
        ready.preferences.dictationVocabulary = ["Crenel", "SwiftUI", "Deniz", "ElevenLabs"]
        try export(ready, "s-dictation")

        var needsAccess = fixture(.dictation)
        needsAccess.state.updateDictationAvailability(.needsInputMonitoring)
        needsAccess.state.updateAccessibilityPermission(granted: false)
        try export(needsAccess, "s-dictation-perms")
    }

    func testTasksPages() throws {
        try export(fixture(.tasks), "s-tasks-connected")

        let statuses: [(String, TaskStorageStatus)] = [
            ("s-tasks-notconnected", .localNotConnected),
            ("s-tasks-denied", .localDenied),
            ("s-tasks-error", .localAfterError("Couldn’t save the last change"))
        ]
        for (name, status) in statuses {
            let item = fixture(.tasks)
            item.state.updateTaskStorageStatus(status)
            try export(item, name)
        }

        var local = fixture(.tasks)
        local.state.updateTaskStorageStatus(.localByChoice)
        local.preferences.taskStorage = .local
        try export(local, "s-tasks-local")
    }

    func testAIPages() throws {
        try export(fixture(.ai), "s-ai-auto")

        var openAI = fixture(.ai)
        openAI.preferences.agent.provider = .openAI
        openAI.hasOpenAIKey = true
        try export(openAI, "s-ai-openai")

        var anthropic = fixture(.ai)
        anthropic.preferences.agent.provider = .anthropic
        anthropic.hasAnthropicKey = true
        try export(anthropic, "s-ai-anthropic")

        var noKeys = fixture(.ai)
        noKeys.preferences.agent.provider = .anthropic
        noKeys.hasElevenLabsKey = false
        try export(noKeys, "s-ai-no-keys")

        var localVoice = fixture(.ai)
        localVoice.preferences.agent.provider = .claudeCode
        localVoice.preferences.meetingProcessing.transcription = .onDevice
        try export(localVoice, "s-ai-voice-local")

        var onDevice = fixture(.ai)
        onDevice.preferences.agent.provider = .onDevice
        try export(onDevice, "s-ai-ondevice")

        var off = fixture(.ai)
        off.preferences.agent.provider = .off
        try export(off, "s-ai-off")

        // Newer than the prototype: the command-line providers.
        var claudeCode = fixture(.ai)
        claudeCode.preferences.agent.provider = .claudeCode
        try export(claudeCode, "s-ai-claudecode")
    }

    func testCalendarPages() throws {
        var connected = fixture(.calendar)
        connected.showsNotifications = true
        try export(connected, "s-calendar-connected")

        let states: [(String, CalendarAccessState)] = [
            ("s-calendar-notconnected", .notDetermined),
            ("s-calendar-denied", .denied),
            ("s-calendar-failed", .failed("The calendar store didn’t answer."))
        ]
        for (name, access) in states {
            var item = fixture(.calendar)
            item.showsNotifications = true
            item.state.updateCalendarAccessState(access)
            try export(item, name)
        }

        var off = fixture(.calendar)
        off.showsNotifications = true
        off.general.isCalendarEnabled = false
        try export(off, "s-calendar-off")
    }

    func testRecordingPages() throws {
        try export(fixture(.recording), "s-recording")

        let denied = fixture(.recording)
        denied.state.updateAudioCapturePermissions(AudioCapturePermissionSnapshot(microphone: .authorized, systemAudio: .denied))
        denied.state.updateAccessibilityPermission(granted: false)
        try export(denied, "s-recording-denied")
    }

    func testDataPages() throws {
        try export(fixture(.data), "s-data")
        try export(fixture(.data, state: AppState(initialFlow: .recording(startedAt: Date()))), "s-data-busy")
    }

    func testSearchListsMatchingRowsFromEverySection() throws {
        var results = fixture(.general)
        results.query = "mic"
        try export(results, "s-search")

        var none = fixture(.general)
        none.query = "zzz"
        try export(none, "s-search-empty")

        XCTAssertTrue(SettingsCategory.recording.searchTitles.contains("Microphone"))
        for category in SettingsCategory.allCases {
            XCTAssertFalse(category.searchTitles.isEmpty)
        }
    }

    func testDataFolderReadoutUsesMegabytesBelowOneGigabyte() {
        XCTAssertEqual(SettingsDataFolder(path: "", bytes: 2_100_000_000).readout.digits, "2.1")
        XCTAssertEqual(SettingsDataFolder(path: "", bytes: 2_100_000_000).readout.unit, "GB")
        XCTAssertEqual(SettingsDataFolder(path: "", bytes: 482_400_000).readout.digits, "482")
        XCTAssertEqual(SettingsDataFolder(path: "", bytes: 482_400_000).readout.unit, "MB")
        XCTAssertEqual(SettingsDataFolder(path: "", bytes: 0).readout.digits, "0")
    }

    // MARK: Onboarding

    func testOnboardingStates() throws {
        let partly: [SetupCapability: SetupGrant] = [.calendar: .granted, .reminders: .granted, .microphone: .granted,
                                                      .accessibility: .blocked]
        try renderOnboarding(setup(partly), step: .welcome, name: "ob-welcome")
        try renderOnboarding(setup(partly), step: .setup, name: "ob-setup")

        // "Turn on all" with a prompt that never answers: the turning state.
        let turning = SetupCoordinator(system: SetupSystem(
            grant: { partly[$0] ?? .notAsked },
            request: { _ in try? await Task.sleep(for: .seconds(30)) },
            open: { _ in }
        ))
        let running = Task { await turning.requestAll() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(turning.isRunningAll)
        try renderOnboarding(turning, step: .setup, name: "ob-turning")
        running.cancel()

        let all = Dictionary(uniqueKeysWithValues: SetupCapability.allCases.map { ($0, SetupGrant.granted) })
        try renderOnboarding(setup(all), step: .setup, name: "ob-done")
    }

    private func setup(_ grants: [SetupCapability: SetupGrant]) -> SetupCoordinator {
        SetupCoordinator(system: SetupSystem(grant: { grants[$0] ?? .notAsked }, request: { _ in }, open: { _ in }))
    }

    private func renderOnboarding(_ setup: SetupCoordinator, step: OnboardingView.Step, name: String) throws {
        let view = OnboardingView(setup: setup, onComplete: {}, initialStep: step).environmentObject(AppState())
        try render(view, folder: "onboarding", name: name, size: OnboardingView.windowSize)
    }

    // MARK: Rendering

    private func render(_ view: some View, folder: String, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        // Settings load through async closures; give them a few turns of the run loop.
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 10)
        guard FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/\(folder)/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }
}
