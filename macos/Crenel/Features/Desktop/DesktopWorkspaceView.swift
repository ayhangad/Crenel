import AppKit
import SwiftUI

enum DesktopSection: String, CaseIterable, Identifiable {
    case today, meetings, tasks, dictation, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .today: "Today"
        case .meetings: "Meetings"
        case .tasks: "Tasks"
        case .dictation: "Dictation"
        case .settings: "Settings"
        }
    }
    var glyph: HudGlyph {
        switch self {
        case .today: .gauge
        case .meetings: .tape
        case .tasks: .queue
        case .dictation: .waveform
        case .settings: .sliders
        }
    }
}

@MainActor
final class DesktopNavigation: ObservableObject {
    @Published var section: DesktopSection = .today
    @Published var selectedMeeting: UUID?
    @Published var isVisible = false
    @Published var settingsCategory = SettingsCategory.general
}

extension Notification.Name {
    static let openDesktopWorkspace = Notification.Name("Crenel.openDesktopWorkspace")
    static let desktopDidClose = Notification.Name("Crenel.desktopDidClose")
    static let openDesktopSettings = Notification.Name("Crenel.openDesktopSettings")
}

struct DesktopSettingsLink<Label: View>: View {
    var category: SettingsCategory = .general
    @ViewBuilder let label: () -> Label
    var body: some View {
        Button { NotificationCenter.default.post(name: .openDesktopSettings, object: nil, userInfo: ["category": category.rawValue]) } label: { label() }
    }
}

@MainActor
final class DesktopWindowController: NSWindowController, NSWindowDelegate {
    let navigation = DesktopNavigation()

    /// The smallest content size the three-column Meetings page still reads at.
    static let minimumSize = NSSize(width: 1_100, height: 680)

    init(delegate: AppDelegate) {
        let size = NSSize(width: Hud.Window.size.width, height: Hud.Window.size.height)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Crenel"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Hud.Layer.window)
        window.contentMinSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.appearance = NSAppearance(named: .darkAqua)
        let hostingView = NSHostingView(rootView:
            DesktopWorkspaceView(delegate: delegate, navigation: navigation)
                .environment(\.crenelActions, delegate.crenelActions)
                .environmentObject(delegate.appState))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(size)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present(section: DesktopSection? = nil, category: SettingsCategory? = nil) {
        if let category { navigation.settingsCategory = category }
        if let section { navigation.section = section }
        navigation.isVisible = true
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // The notch and background recording continue after the workspace closes.
        navigation.isVisible = false
        NotificationCenter.default.post(name: .desktopDidClose, object: nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The desktop window: a sidebar rail and one page beside it. Three layers — sidebar,
/// window floor, and the meeting sheet one layer up.
struct DesktopWorkspaceView: View {
    let actions: DesktopActions
    @ObservedObject var navigation: DesktopNavigation
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var preferences: DesktopPreferencesModel
    @StateObject private var index = DesktopMeetingIndex()

    @MainActor
    init(delegate: AppDelegate, navigation: DesktopNavigation) {
        self.init(actions: DesktopActions(delegate: delegate), navigation: navigation)
    }

    @MainActor
    init(actions: DesktopActions, navigation: DesktopNavigation, preferences: DesktopPreferencesModel? = nil) {
        self.actions = actions
        self.navigation = navigation
        _preferences = StateObject(wrappedValue: preferences ?? DesktopPreferencesModel())
    }

    var body: some View {
        HStack(spacing: 0) {
            DesktopSidebar(actions: actions, navigation: navigation, preferences: preferences, openSettings: openSettings)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Hud.Layer.window)
                .hudSurface(Hud.Layer.window)
        }
        .ignoresSafeArea()
        .foregroundStyle(Hud.Ink.ink1)
        .preferredColorScheme(.dark)
        .tint(Hud.Ink.ink2)
        .task { await preferences.load(actions) }
        .task(id: indexKey) { index.refresh(meetings: appState.storedMeetings, load: actions.loadMeeting) }
        .onChange(of: navigation.section) { _, section in
            // Shortcut, mode or words may have changed in Settings.
            if section != .settings { Task { await preferences.load(actions) } }
        }
    }

    @ViewBuilder private var page: some View {
        // Each page is a fresh view, so its gauges ignite and its sections stagger once
        // per page change — never when a page moves between its own states.
        switch navigation.section {
        case .today:
            DesktopTodayPage(actions: actions, navigation: navigation, preferences: preferences, index: index)
        case .meetings:
            DesktopMeetingsPage(actions: actions, selection: $navigation.selectedMeeting, index: index, openSettings: openSettings)
        case .tasks:
            DesktopTasksPage(actions: actions, openSettings: openSettings)
        case .dictation:
            DesktopDictationPage(actions: actions, preferences: preferences, openSettings: openSettings)
        case .settings:
            actions.settings(navigation.settingsCategory).id(navigation.settingsCategory)
        }
    }

    private var indexKey: String {
        appState.storedMeetings.map { "\($0.id)|\($0.title)|\($0.processingStatus.rawValue)|\($0.summaryNeedsAttention == true)" }.joined(separator: ",")
    }

    private func openSettings(_ category: SettingsCategory) {
        navigation.settingsCategory = category
        navigation.section = .settings
    }
}

// MARK: - Meeting index

/// What the list and the dashboard know about each processed meeting without opening it:
/// how many tasks it left you, who spoke, and the words to search.
@MainActor
final class DesktopMeetingIndex: ObservableObject {
    struct Entry: Equatable {
        var key: String
        var actionCount = 0
        var speakers: [String] = []
        var hasNotes = false
        var haystack = ""
    }

    @Published private(set) var entries: [UUID: Entry] = [:]
    private var task: Task<Void, Never>?

    func refresh(meetings: [StoredMeeting], load: @escaping (StoredMeeting) async throws -> MeetingDetailContent) {
        task?.cancel()
        let ids = Set(meetings.map(\.id))
        entries = entries.filter { ids.contains($0.key) }
        let pending = meetings.filter { $0.processingStatus == .completed && entries[$0.id]?.key != Self.key($0) }
        guard !pending.isEmpty else { return }
        task = Task { [weak self] in
            for meeting in pending {
                guard !Task.isCancelled else { return }
                let entry = await Self.entry(for: meeting, load: load)
                guard !Task.isCancelled else { return }
                self?.entries[meeting.id] = entry
            }
        }
    }

    /// Forces a reload of one meeting (after a speaker was renamed or a summary rewritten).
    func invalidate(_ id: UUID) {
        entries[id]?.key = ""
    }

    func update(_ content: MeetingDetailContent) {
        entries[content.id] = Self.entry(Self.key(content.meeting), content.storedTranscription)
    }

    private static func key(_ meeting: StoredMeeting) -> String {
        "\(meeting.title)|\(meeting.processingStatus.rawValue)|\(meeting.summaryNeedsAttention == true)"
    }

    private static func entry(for meeting: StoredMeeting, load: (StoredMeeting) async throws -> MeetingDetailContent) async -> Entry {
        let stored = try? await load(meeting).storedTranscription
        return entry(key(meeting), stored)
    }

    private static func entry(_ key: String, _ stored: StoredTranscription?) -> Entry {
        guard let stored else { return Entry(key: key) }
        let owner = MeetingOwner.current()
        var seen = Set<String>()
        let speakers = stored.transcript.segments.compactMap { segment -> String? in
            guard let name = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !owner.speakerIDs.contains(segment.speakerID), !owner.isOwner(name: name),
                  !MeetingOwner.isGenericSpeakerName(name), seen.insert(name).inserted else { return nil }
            return name
        }
        let text = stored.transcript.segments.isEmpty ? stored.transcript.text : stored.transcript.segments.map(\.text).joined(separator: " ")
        return Entry(key: key, actionCount: stored.summary?.actionItems.count ?? 0, speakers: speakers,
                     hasNotes: stored.summary != nil, haystack: [stored.summary?.overview ?? "", text].joined(separator: " "))
    }
}

// MARK: - Search and filter

enum DesktopMeetingSearch {
    static func filter(_ meetings: [StoredMeeting], query: String, transcripts: [UUID: String] = [:]) -> [StoredMeeting] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedStandardContains(query) || (transcripts[$0.id]?.localizedStandardContains(query) ?? false)
        }
    }
}

enum DesktopMeetingFilter: Hashable, CaseIterable {
    case all, needsYou, forYou

    /// Failed or without notes: the recordings that wait for the user.
    static func needsUser(_ meeting: StoredMeeting) -> Bool {
        meeting.processingStatus == .failed || meeting.summaryNeedsAttention == true
    }

    func matches(_ meeting: StoredMeeting, actionCount: Int) -> Bool {
        switch self {
        case .all: true
        case .needsYou: Self.needsUser(meeting)
        case .forYou: actionCount > 0
        }
    }
}
