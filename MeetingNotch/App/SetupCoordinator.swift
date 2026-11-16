import AppKit
import AVFoundation
import EventKit
import Foundation
import UserNotifications

/// Everything Crenel needs from macOS, set up in one place. Onboarding shows every
/// capability on one screen; "Enable all" walks through them in order. When Calendar or
/// Reminders access arrives the features connect themselves — no per-module setup.
enum SetupCapability: String, CaseIterable, Identifiable, Sendable {
    case calendar
    case reminders
    case microphone
    case notifications
    case systemAudio
    case accessibility
    case inputMonitoring

    var id: Self { self }

    var title: String {
        switch self {
        case .calendar: "Takvim"
        case .reminders: "Hatırlatıcılar"
        case .microphone: "Mikrofon"
        case .notifications: "Bildirimler"
        case .systemAudio: "Sistem sesi"
        case .accessibility: "Erişilebilirlik"
        case .inputMonitoring: "Girdi izleme"
        }
    }

    var detail: String {
        switch self {
        case .calendar: "Sıradaki etkinlik ve kalan süre notch’ta"
        case .reminders: "Görevler iPhone ve Watch ile eşitlenir"
        case .microphone: "Dikte ve toplantıda sizin sesiniz"
        case .notifications: "Toplantı başlamadan haber verir"
        case .systemAudio: "Toplantıda diğer katılımcıların sesi"
        case .accessibility: "İmlece yazma, Zoom/Meet mikrofon takibi"
        case .inputMonitoring: "Fn’ye basılı tutup dikte"
        }
    }

    var glyph: CrenelGlyph {
        switch self {
        case .calendar: .calendar
        case .reminders: .tasks
        case .microphone: .mic
        case .notifications: .bell
        case .systemAudio: .speaker
        case .accessibility: .accessibility
        case .inputMonitoring: .keyboard
        }
    }

    /// Granted through a system prompt; the others need a switch in System Settings.
    var usesSystemPrompt: Bool {
        switch self {
        case .calendar, .reminders, .microphone, .notifications, .systemAudio: true
        case .accessibility, .inputMonitoring: false
        }
    }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .calendar: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .microphone: anchor = "Privacy_Microphone"
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .systemAudio: anchor = "Privacy_AudioCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum SetupGrant: Equatable, Sendable {
    case granted
    /// Never asked; one tap shows the system prompt.
    case notAsked
    /// Refused or restricted; only System Settings can change it.
    case blocked
}

/// System calls behind the setup, swappable in tests.
struct SetupSystem {
    var grant: @MainActor (SetupCapability) -> SetupGrant
    var request: @MainActor (SetupCapability) async -> Void
    var open: @MainActor (URL) -> Void
}

@MainActor
final class SetupCoordinator: ObservableObject {
    @Published private(set) var grants: [SetupCapability: SetupGrant] = [:]
    @Published private(set) var isRunningAll = false

    /// Called when a capability becomes granted, so its feature can connect itself.
    var onGranted: (SetupCapability) -> Void = { _ in }

    private let system: SetupSystem
    private var watchTask: Task<Void, Never>?

    init(system: SetupSystem) {
        self.system = system
        refresh()
    }

    var allGranted: Bool { SetupCapability.allCases.allSatisfy { grants[$0] == .granted } }

    func grant(for capability: SetupCapability) -> SetupGrant {
        grants[capability] ?? .notAsked
    }

    func refresh() {
        var next: [SetupCapability: SetupGrant] = [:]
        for capability in SetupCapability.allCases {
            next[capability] = system.grant(capability)
        }
        let newlyGranted = SetupCapability.allCases.filter { next[$0] == .granted && grants[$0] != .granted && !grants.isEmpty }
        grants = next
        newlyGranted.forEach(onGranted)
    }

    /// One capability: the system prompt when it can still be asked, otherwise the
    /// exact System Settings pane.
    func request(_ capability: SetupCapability) async {
        switch grant(for: capability) {
        case .granted:
            return
        case .blocked:
            if let url = capability.settingsURL { system.open(url) }
            watch()
        case .notAsked:
            // Accessory apps must come forward or the prompt can appear behind windows.
            NSApp.activate()
            await system.request(capability)
            refresh()
            if !capability.usesSystemPrompt { watch() }
        }
    }

    /// Prompts for everything that can be prompted, in order, then opens Settings for
    /// the first one that needs a manual switch.
    func requestAll() async {
        guard !isRunningAll else { return }
        isRunningAll = true
        defer { isRunningAll = false }
        for capability in SetupCapability.allCases where capability.usesSystemPrompt && grant(for: capability) == .notAsked {
            await request(capability)
        }
        if let manual = SetupCapability.allCases.first(where: { !$0.usesSystemPrompt && grant(for: $0) != .granted }) {
            await request(manual)
        }
    }

    /// Grants made in System Settings arrive without a callback; poll while the user is
    /// likely there.
    func watch(for duration: Duration = .seconds(90)) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: duration)
            while clock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refresh()
                if self.allGranted { return }
            }
        }
    }
}

extension SetupSystem {
    /// Live system calls. Audio, accessibility and input monitoring reuse the app's
    /// existing services through closures.
    static func live(
        systemAudio: @escaping @MainActor () -> AudioCapturePermissionStatus,
        requestSystemAudio: @escaping @MainActor () async -> Void,
        requestAccessibility: @escaping @MainActor () -> Void,
        requestInputMonitoring: @escaping @MainActor () -> Void,
        notificationStatus: @escaping @MainActor () -> UNAuthorizationStatus
    ) -> SetupSystem {
        let store = EKEventStore()
        return SetupSystem(
            grant: { capability in
                switch capability {
                case .calendar: return Self.grant(EKEventStore.authorizationStatus(for: .event))
                case .reminders: return Self.grant(EKEventStore.authorizationStatus(for: .reminder))
                case .microphone:
                    switch AVCaptureDevice.authorizationStatus(for: .audio) {
                    case .authorized: return .granted
                    case .notDetermined: return .notAsked
                    default: return .blocked
                    }
                case .notifications:
                    switch notificationStatus() {
                    case .authorized, .provisional, .ephemeral: return .granted
                    case .notDetermined: return .notAsked
                    default: return .blocked
                    }
                case .systemAudio:
                    switch systemAudio() {
                    case .authorized: return .granted
                    case .notDetermined, .verificationRequired: return .notAsked
                    case .denied, .restricted: return .blocked
                    }
                case .accessibility:
                    return SystemAccessibilityAuthorizer().isTrusted(prompt: false) ? .granted : .notAsked
                case .inputMonitoring:
                    return DictationHotKeyMonitor.hasInputMonitoringAccess() ? .granted : .notAsked
                }
            },
            request: { capability in
                switch capability {
                case .calendar: _ = try? await store.requestFullAccessToEvents()
                case .reminders: _ = try? await store.requestFullAccessToReminders()
                case .microphone: _ = await AVCaptureDevice.requestAccess(for: .audio)
                case .notifications:
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                case .systemAudio: await requestSystemAudio()
                case .accessibility: requestAccessibility()
                case .inputMonitoring: requestInputMonitoring()
                }
            },
            open: { url in NSWorkspace.shared.open(url) }
        )
    }

    private static func grant(_ status: EKAuthorizationStatus) -> SetupGrant {
        switch status {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notAsked
        default: .blocked
        }
    }
}

/// Notification authorization is only readable asynchronously; keep the last answer and
/// refresh it in the background on every read.
@MainActor
final class NotificationAuthorizationCache {
    private var status: UNAuthorizationStatus = .notDetermined
    private var refreshing = false

    func current() -> UNAuthorizationStatus {
        if !refreshing {
            refreshing = true
            Task { @MainActor in
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                self.status = settings.authorizationStatus
                self.refreshing = false
            }
        }
        return status
    }
}
