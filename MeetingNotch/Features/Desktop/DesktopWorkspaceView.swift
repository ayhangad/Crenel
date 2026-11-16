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
    var symbol: String {
        switch self {
        case .meetings: "waveform"
        case .tasks: "checklist"
        case .settings: "gearshape"
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

struct DesktopWorkspaceView: View {
    let delegate: AppDelegate
    @ObservedObject var navigation: DesktopNavigation
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(MeetingNotchTheme.hairline).frame(width: 1)
            Group {
                switch navigation.section {
                case .meetings:
                    DesktopMeetingsView(delegate: delegate, selection: $navigation.selectedMeeting)
                case .tasks:
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tasks").font(MeetingNotchTheme.pageTitleFont)
                        }
                        ScrollView {
                            TasksView()
                                .padding(20)
                                .background(MeetingNotchTheme.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 24))
                        }
                    }.padding(32).frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
                case .settings:
                    delegate.desktopSettings(category: navigation.settingsCategory).id(navigation.settingsCategory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MeetingNotchTheme.workspaceBackground)
            .transition(.opacity)
        }
        .foregroundStyle(MeetingNotchTheme.primaryText)
        .environment(\.workspacePalette, true)
        .preferredColorScheme(.dark)
        .tint(MeetingNotchTheme.cyan)
        .animation(MeetingNotchMotion.navigation(reduceMotion: reduceMotion), value: navigation.section)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image("FigmaVoice").resizable().renderingMode(.template)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(MeetingNotchTheme.cyan)
                    .frame(width: 36, height: 36)
                    .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text("Crenel").font(.system(size: 15, weight: .semibold))
            }.padding(.horizontal, 4).padding(.top, 12)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(DesktopSection.allCases) { section in
                    Button { navigation.section = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).font(.system(size: 17, weight: .regular))
                                .foregroundStyle(navigation.section == section ? MeetingNotchTheme.cyan : MeetingNotchTheme.secondaryText)
                                .frame(width: 20).accessibilityHidden(true)
                            Text(section.title)
                            Spacer(minLength: 4)
                            if section == .tasks, appState.activeTaskCount > 0 {
                                Text("\(appState.activeTaskCount)").font(MeetingNotchTheme.metadataFont)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0.07), in: Capsule())
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12).frame(height: 44)
                    }
                    .buttonStyle(MeetingNotchRowButtonStyle(selected: navigation.section == section))
                    .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                }
            }
            Spacer()
            if case .recording(let startedAt) = appState.meetingFlow {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Recording", systemImage: "record.circle")
                            .foregroundStyle(MeetingNotchTheme.danger)
                        Spacer(minLength: 0)
                    }
                    Text(startedAt, style: .timer).font(.system(size: 24, weight: .medium, design: .monospaced))
                    Button("Stop recording", action: delegate.stopRecordingFlow)
                        .buttonStyle(MeetingNotchActionButtonStyle(kind: .danger))
                }.font(MeetingNotchTheme.metadataFont).padding(12)
                    .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 12) {
                Button(action: delegate.showMeetingNotch) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.topthird.inset.filled")
                        Text("Show notch")
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }.font(MeetingNotchTheme.controlFont).padding(.horizontal, 12).frame(height: 44)
                }.buttonStyle(MeetingNotchRowButtonStyle())

            }
        }
        .padding(16).frame(width: 206)
        .background(MeetingNotchTheme.sidebarBackground)
    }
}

private struct WorkspaceStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(MeetingNotchTheme.success)
            configuration.title
        }
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
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Binding var selection: UUID?
    @State private var detail: MeetingDetailContent?
    @State private var loadError = false
    @State private var revision = 0

    private var filtered: [StoredMeeting] { DesktopMeetingSearch.filter(appState.storedMeetings, query: query) }
    private var selected: StoredMeeting? { appState.storedMeetings.first { $0.id == selection } }
    private var processing: Bool { appState.processingJobs.contains { $0.meetingID == selection && $0.state != .failed } }
    private var requestID: String { "\(selection?.uuidString ?? "")|\(selected?.title ?? "")|\(processing)|\(revision)" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meetings").font(MeetingNotchTheme.pageTitleFont)
                        Text("^[\(appState.storedMeetings.count) recording](inflect: true)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: delegate.startManualRecording) { Image(systemName: "plus") }
                        .buttonStyle(MeetingNotchIconButtonStyle(tint: MeetingNotchTheme.primaryText))
                        .help("New recording").accessibilityLabel("New recording")
                        .disabled(appState.requiresTerminationConfirmation)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search meetings", text: $query).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Search meetings")
                    if !query.isEmpty { Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").frame(width: 40, height: 40) }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search") }
                }.padding(.leading, 12).padding(.trailing, query.isEmpty ? 12 : 0).frame(height: 44)
                    .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(searchFocused ? MeetingNotchTheme.cyan : MeetingNotchTheme.hairline, lineWidth: 1))
                if !appState.upcomingMeetings.isEmpty && query.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UPCOMING").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(appState.upcomingMeetings.prefix(2)) { meeting in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meeting.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(meeting.startDate.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if let url = meeting.meetingURL {
                                    Button("Join") { delegate.openMeetingURL(url) }.buttonStyle(MeetingNotchActionButtonStyle())
                                }
                            }.padding(12).background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                if filtered.isEmpty {
                    MeetingNotchEmptyState(symbol: query.isEmpty ? "waveform" : "magnifyingglass",
                        title: query.isEmpty ? "No recordings yet" : "No results",
                        detail: query.isEmpty ? "Your first recorded meeting will show up here." : "Try another meeting name.", compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(filtered) { meeting in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(meeting.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                HStack {
                                    Text(meeting.startedAt.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    Text(TranscriptTextFormatter.timestamp(meeting.duration)).monospacedDigit()
                                }.font(.caption).foregroundStyle(.secondary)
                                if appState.processingJobs.contains(where: { $0.meetingID == meeting.id && $0.state != .failed }) {
                                    Label("Processing", systemImage: "ellipsis").font(.caption).foregroundStyle(.cyan)
                                } else if meeting.processingStatus == .failed {
                                    Label("Processing failed", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                                } else if meeting.summaryNeedsAttention == true {
                                    Text("Summary pending").font(.caption).foregroundStyle(.orange)
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == meeting.id ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .tag(meeting.id)
                                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    if meeting.processingStatus == .failed {
                                        Button("Retry processing") { delegate.retryProcessing(meeting) }
                                    }
                                    Button("Delete meeting…", role: .destructive) { delegate.deleteStoredMeeting(meeting) }
                                }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }.padding(20).frame(width: 294).background(MeetingNotchTheme.sidebarBackground.opacity(0.45))
            Rectangle().fill(MeetingNotchTheme.hairline).frame(width: 1)
            detailPane.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: requestID) { await loadSelection() }
        .onChange(of: appState.storedMeetings.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil; detail = nil }
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let detail, detail.id == selection {
            VStack(spacing: 0) {
                MeetingDetailToolbar(content: detail, onBack: { selection = nil }, onCopyText: delegate.copyToPasteboard)
                    .padding(24)
                Divider()
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
                        .id(detail.id).padding(24)
                }
            }
        } else if selection != nil {
            if loadError {
                VStack(spacing: 4) {
                    MeetingNotchEmptyState(symbol: "exclamationmark.circle", title: "Couldn’t open meeting",
                        detail: "Couldn’t read the files. Try opening it again.")
                    Button("Try again") { revision += 1 }.buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                }
            } else { ProgressView("Opening meeting…") }
        } else {
            VStack(spacing: 4) {
                MeetingNotchEmptyState(symbol: "waveform", title: "Select a meeting", detail: "")
                Button(action: delegate.startManualRecording) {
                    Label("New recording", systemImage: "plus")
                }.buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
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
