import AppKit
import SwiftUI

enum DesktopSection: String, CaseIterable, Identifiable {
    case meetings, tasks, settings
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .meetings: "Meetings"
        case .tasks: "Tasks"
        case .settings: "Settings"
        }
    }
    var glyph: CrenelGlyph {
        switch self {
        case .meetings: .mic
        case .tasks: .tasks
        case .settings: .sliders
        }
    }
}

@MainActor
final class DesktopNavigation: ObservableObject {
    @Published var section: DesktopSection = .meetings
    @Published var selectedMeeting: UUID?
    @Published var isVisible = false
    @Published var settingsCategory = SettingsCategory.general
}

extension Notification.Name {
    static let openDesktopWorkspace = Notification.Name("MeetingNotch.openDesktopWorkspace")
    static let desktopDidClose = Notification.Name("MeetingNotch.desktopDidClose")
    static let openDesktopSettings = Notification.Name("MeetingNotch.openDesktopSettings")
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

    init(delegate: AppDelegate) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Crenel"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "MeetingNotchWorkspace")
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 960, height: 540)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.appearance = NSAppearance(named: .darkAqua)
        let hostingView = NSHostingView(rootView:
            DesktopWorkspaceView(delegate: delegate, navigation: navigation)
                .environment(\.crenelActions, delegate.crenelActions)
                .environmentObject(delegate.appState))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 1120, height: 680))
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

/// Window surfaces: pure greys, separated by tone and space instead of lines.
enum DesktopInk {
    static let content = Color(white: 0.06)
    static let sidebar = Color(white: 0.04)
}

struct DesktopWorkspaceView: View {
    let delegate: AppDelegate
    @ObservedObject var navigation: DesktopNavigation
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sidebarSpace
    @State private var hoveredItem: AnyHashable?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                switch navigation.section {
                case .meetings:
                    DesktopMeetingsView(delegate: delegate, selection: $navigation.selectedMeeting)
                case .tasks:
                    VStack(alignment: .leading, spacing: Hud.Space.x5) {
                        Text("Tasks").font(Hud.font(20, .semibold)).foregroundStyle(Hud.Ink.text1)
                        ScrollView {
                            TasksView()
                        }
                        .scrollIndicators(.never)
                    }
                    .padding(Hud.Space.x8)
                    .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
                case .settings:
                    delegate.desktopSettings(category: navigation.settingsCategory).id(navigation.settingsCategory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesktopInk.content)
            .transition(.opacity)
        }
        .foregroundStyle(Hud.Ink.text1)
        .preferredColorScheme(.dark)
        .tint(Hud.Ink.text2)
        .animation(reduceMotion ? nil : Hud.Motion.change, value: navigation.section)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Hud.Space.x6) {
            HStack(spacing: Hud.Space.x2) {
                CrenelIcon(.logo, size: 16)
                    .foregroundStyle(Hud.Ink.text1)
                Text("Crenel").hud(.title, Hud.Ink.text1)
            }
            .padding(.horizontal, Hud.Size.rowInset)
            .padding(.top, Hud.Space.x8)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(DesktopSection.allCases) { section in
                    sectionRow(section)
                }
            }

            Spacer()

            if case .recording(let startedAt) = appState.meetingFlow {
                VStack(alignment: .leading, spacing: Hud.Space.x2) {
                    HStack(spacing: Hud.Space.x2) {
                        HudPulse(color: Hud.Ink.live)
                        Text("Recording").hud(.label, Hud.Ink.live)
                    }
                    Text(startedAt, style: .timer)
                        .font(Hud.Style.display.font).monospacedDigit()
                        .foregroundStyle(Hud.Ink.text1)
                    Button(action: delegate.stopRecordingFlow) {
                        HStack(spacing: Hud.Space.x2) {
                            HudIcon(.stop, size: Hud.Size.smallIcon)
                            Text("Stop recording")
                        }
                        .foregroundStyle(Hud.Ink.live)
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .padding(.leading, -Hud.Space.x3)
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .transition(.opacity)
            }

            Button(action: delegate.showMeetingNotch) {
                HStack(spacing: Hud.Space.x3) {
                    HudIcon(.window, size: Hud.Size.icon)
                        .foregroundStyle(Hud.Ink.text3)
                    Text("Show notch").hud(.label, Hud.Ink.text2)
                    Spacer(minLength: 0)
                    HudIcon(.link, size: Hud.Size.smallIcon)
                        .foregroundStyle(Hud.Ink.text4)
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .frame(height: 36)
                .hudGlide("notch", hovered: $hoveredItem, in: sidebarSpace)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Hud.Space.x3)
        .padding(.bottom, Hud.Space.x4)
        .frame(width: 206)
        .background(DesktopInk.sidebar)
    }

    private func sectionRow(_ section: DesktopSection) -> some View {
        let isSelected = navigation.section == section
        return Button {
            withAnimation(reduceMotion ? nil : Hud.Motion.glide) { navigation.section = section }
        } label: {
            HStack(spacing: Hud.Space.x3) {
                CrenelIcon(section.glyph, size: Hud.Size.icon)
                    .foregroundStyle(isSelected ? Hud.Ink.text1 : Hud.Ink.text3)
                    .frame(width: Hud.Size.icon + 2)
                Text(section.title)
                    .hud(.label, isSelected ? Hud.Ink.text1 : Hud.Ink.text2)
                Spacer(minLength: Hud.Space.x1)
                if section == .tasks, appState.activeTaskCount > 0 {
                    Text("\(appState.activeTaskCount)").hud(.meta, Hud.Ink.text4)
                }
            }
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: 36)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                        .fill(Hud.Ink.selected)
                        .matchedGeometryEffect(id: "desktop.section", in: sidebarSpace)
                }
            }
            .hudGlide(section, hovered: $hoveredItem, in: sidebarSpace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A quiet empty or error state: an icon, a line, an optional detail.
private struct DesktopEmptyState: View {
    let glyph: CrenelGlyph
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Hud.Space.x2) {
            CrenelIcon(glyph, size: 18)
                .foregroundStyle(Hud.Ink.text4)
                .padding(.bottom, Hud.Space.x1)
            Text(title).hud(.body, Hud.Ink.text2)
            if let detail {
                Text(detail).hud(.meta, Hud.Ink.text3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 260)
        .accessibilityElement(children: .combine)
    }
}

enum DesktopMeetingSearch {
    static func filter(_ meetings: [StoredMeeting], query: String) -> [StoredMeeting] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetings }
        return meetings.filter { $0.title.localizedStandardContains(query) }
    }
}

private struct DesktopMeetingsView: View {
    let delegate: AppDelegate
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Binding var selection: UUID?
    @State private var detail: MeetingDetailContent?
    @State private var loadError = false
    @State private var revision = 0
    @State private var hoveredRow: AnyHashable?
    @Namespace private var listSpace

    private var filtered: [StoredMeeting] { DesktopMeetingSearch.filter(appState.storedMeetings, query: query) }
    private var selected: StoredMeeting? { appState.storedMeetings.first { $0.id == selection } }
    private var processing: Bool { appState.processingJobs.contains { $0.meetingID == selection && $0.state != .failed } }
    private var requestID: String { "\(selection?.uuidString ?? "")|\(selected?.title ?? "")|\(processing)|\(revision)" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Hud.Space.x4) {
                header
                searchField
                if filtered.isEmpty && (appState.upcomingMeetings.isEmpty || !query.isEmpty) {
                    DesktopEmptyState(glyph: query.isEmpty ? .waveform : .history,
                        title: query.isEmpty ? "No recordings yet" : "No results",
                        detail: query.isEmpty ? "Your first recorded meeting will show up here." : "Try another meeting name.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .padding(.top, Hud.Space.x8)
            .padding(.horizontal, Hud.Space.x4)
            .frame(width: 300)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: requestID) { await loadSelection() }
        .onChange(of: appState.storedMeetings.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil; detail = nil }
        }
    }

    // MARK: List column

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Meetings").font(Hud.font(20, .semibold)).foregroundStyle(Hud.Ink.text1)
            Text("\(appState.storedMeetings.count)").hud(.meta, Hud.Ink.text4)
                .accessibilityLabel(Text("^[\(appState.storedMeetings.count) recording](inflect: true)"))
            Spacer()
            Button(action: delegate.startManualRecording) { HudIcon(.plus, size: Hud.Size.icon) }
                .buttonStyle(HudButtonStyle(kind: .icon))
                .help("New recording").accessibilityLabel("New recording")
                .disabled(appState.requiresTerminationConfirmation)
        }
        .padding(.horizontal, Hud.Size.rowInset)
    }

    private var searchField: some View {
        HStack(spacing: Hud.Space.x2) {
            TextField("Search meetings", text: $query)
                .textFieldStyle(.plain)
                .font(Hud.Style.body.font)
                .foregroundStyle(Hud.Ink.text1)
                .focused($searchFocused)
                .accessibilityLabel("Search meetings")
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: { HudIcon(.close, size: Hud.Size.smallIcon) }
                    .buttonStyle(HudButtonStyle(kind: .icon))
                    .help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, Hud.Size.rowInset)
        .padding(.trailing, 2)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                .fill(searchFocused ? Hud.Ink.selected : Hud.Ink.hover)
        )
        .animation(Hud.Motion.hover, value: searchFocused)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !appState.upcomingMeetings.isEmpty && query.isEmpty {
                    groupHeader("Upcoming")
                    ForEach(appState.upcomingMeetings.prefix(2)) { meeting in
                        upcomingRow(meeting)
                    }
                    if !filtered.isEmpty {
                        groupHeader("Recorded").padding(.top, Hud.Space.x3)
                    }
                }
                ForEach(filtered) { meeting in
                    meetingRow(meeting)
                }
            }
            .padding(.bottom, Hud.Space.x4)
        }
        .scrollIndicators(.never)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
    }

    private func groupHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .hud(.label, Hud.Ink.text3)
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: 22, alignment: .bottom)
            .padding(.bottom, Hud.Space.x1)
            .accessibilityAddTraits(.isHeader)
    }

    private func upcomingRow(_ meeting: Meeting) -> some View {
        HStack(spacing: Hud.Space.x3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).hud(.body, Hud.Ink.text1).lineLimit(1)
                Text(HudFormat.day(meeting.startDate, now: .now)).hud(.meta, Hud.Ink.text3)
            }
            Spacer(minLength: Hud.Space.x2)
            if let url = meeting.meetingURL {
                Button("Join") { delegate.openMeetingURL(url) }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }
            Text(HudFormat.clock(meeting.startDate)).hud(.value, Hud.Ink.text2)
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
        .hudGlide(AnyHashable("upcoming-\(meeting.id)"), hovered: $hoveredRow, in: listSpace)
        .accessibilityElement(children: .combine)
    }

    private func meetingRow(_ meeting: StoredMeeting) -> some View {
        let isSelected = selection == meeting.id
        let isProcessing = appState.processingJobs.contains(where: { $0.meetingID == meeting.id && $0.state != .failed })
        return Button {
            selection = meeting.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title).hud(.body, Hud.Ink.text1).lineLimit(1)
                    meta(for: meeting, isProcessing: isProcessing)
                }
                Spacer(minLength: Hud.Space.x2)
                Text(HudFormat.clock(meeting.startedAt))
                    .hud(.value, isSelected ? Hud.Ink.text1 : Hud.Ink.text2)
            }
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: Hud.Size.row)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                        .fill(Hud.Ink.selected)
                        .matchedGeometryEffect(id: "desktop.meeting", in: listSpace)
                }
            }
            .hudGlide(meeting.id, hovered: $hoveredRow, in: listSpace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if meeting.processingStatus == .failed {
                Button("Retry processing") { delegate.retryProcessing(meeting) }
            }
            Button("Delete meeting…", role: .destructive) { delegate.deleteStoredMeeting(meeting) }
        }
    }

    /// Second line: day and length, or the state that needs attention in its colour.
    @ViewBuilder private func meta(for meeting: StoredMeeting, isProcessing: Bool) -> some View {
        if isProcessing {
            Text("Processing").hud(.meta, Hud.Ink.signal)
        } else if meeting.processingStatus == .failed {
            Text("Processing failed").hud(.meta, Hud.Ink.live)
        } else if meeting.summaryNeedsAttention == true {
            Text("Summary pending").hud(.meta, Hud.Ink.signal)
        } else {
            Text("\(HudFormat.day(meeting.startedAt, now: .now)) · \(TranscriptTextFormatter.timestamp(meeting.duration))")
                .hud(.meta, Hud.Ink.text3)
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let ids = filtered.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let next: Int
        if let selection, let index = ids.firstIndex(of: selection) {
            next = min(max(index + offset, 0), ids.count - 1)
        } else {
            next = offset > 0 ? 0 : ids.count - 1
        }
        withAnimation(reduceMotion ? nil : Hud.Motion.glide) { selection = ids[next] }
        return .handled
    }

    // MARK: Detail

    @ViewBuilder private var detailPane: some View {
        if let detail, detail.id == selection {
            VStack(spacing: 0) {
                MeetingDetailToolbar(content: detail, onBack: { selection = nil }, onCopyText: delegate.copyToPasteboard)
                    .padding(.horizontal, Hud.Space.x6)
                    .padding(.top, Hud.Space.x6)
                    .padding(.bottom, Hud.Space.x2)
                ScrollView {
                    MeetingDetailView(content: detail, onCopyText: delegate.copyToPasteboard,
                        onExportMarkdown: { delegate.exportMarkdown($0, for: detail.meeting) },
                        onRevealAudio: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                        onRetry: delegate.retryProcessing, onDelete: delegate.deleteStoredMeeting,
                        analysisActions: MeetingAnalysisActions(renameSpeaker: { id, speaker, name in
                            let result = await delegate.meetingAnalysisActions.renameSpeaker(id, speaker, name)
                            revision += 1
                            return result
                        }, importAction: delegate.meetingAnalysisActions.importAction),
                        isProcessing: processing,
                        importedActionIDs: Set(appState.tasks.filter { $0.sourceMeetingID == detail.id }.compactMap(\.sourceActionID)))
                        .id(detail.id)
                        .padding(.horizontal, Hud.Space.x6)
                        .padding(.vertical, Hud.Space.x4)
                }
                .scrollIndicators(.never)
            }
        } else if selection != nil {
            if loadError {
                VStack(spacing: Hud.Space.x4) {
                    DesktopEmptyState(glyph: .warning, title: "Couldn’t open meeting",
                        detail: "Couldn’t read the files. Try opening it again.")
                    Button("Try again") { revision += 1 }
                        .buttonStyle(HudButtonStyle(kind: .primary))
                }
            } else {
                HStack(spacing: Hud.Space.x2) {
                    ProgressView().controlSize(.small)
                    Text("Opening meeting…").hud(.meta, Hud.Ink.text3)
                }
            }
        } else {
            VStack(spacing: Hud.Space.x4) {
                DesktopEmptyState(glyph: .waveform, title: "Select a meeting")
                Button(action: delegate.startManualRecording) {
                    HStack(spacing: Hud.Space.x2) {
                        HudIcon(.plus, size: Hud.Size.smallIcon)
                        Text("New recording")
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .primary))
                .disabled(appState.requiresTerminationConfirmation)
            }
        }
    }

    private func loadSelection() async {
        guard let meeting = selected else { detail = nil; return }
        loadError = false
        do {
            let loaded = try await delegate.loadDesktopMeeting(meeting)
            guard !Task.isCancelled, selection == meeting.id else { return }
            detail = loaded
        } catch { if !Task.isCancelled, selection == meeting.id { loadError = true; detail = nil } }
    }
}
