import AppKit
import SwiftUI

enum DesktopSection: String, CaseIterable, Identifiable {
    case meetings = "Toplantılar", tasks = "Görevler", settings = "Ayarlar"
    var id: Self { self }
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "MeetingNotch"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "MeetingNotchWorkspace")
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 1000, height: 620)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView:
            DesktopWorkspaceView(delegate: delegate, navigation: navigation)
                .environmentObject(delegate.appState))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MeetingNotchWorkspace")
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

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch navigation.section {
                case .meetings: DesktopMeetingsView(delegate: delegate, selection: $navigation.selectedMeeting)
                case .tasks:
                    ScrollView {
                        TasksView(onAdd: delegate.addTask, onUpdate: delegate.updateTask,
                            onChangeStatus: delegate.changeTaskStatus, onArchive: delegate.archiveTask,
                            onRestore: delegate.restoreTask, onDelete: delegate.deleteTask,
                            onDeleteArchive: delegate.deleteTaskArchive)
                            .frame(maxWidth: 860).padding(32)
                    }
                case .settings: delegate.desktopSettings(category: navigation.settingsCategory).id(navigation.settingsCategory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.title2).foregroundStyle(.cyan)
                Text("MeetingNotch").font(.system(size: 16, weight: .semibold))
            }.padding(.horizontal, 12).padding(.top, 16)
            VStack(spacing: 6) {
                ForEach(DesktopSection.allCases) { section in
                    Button { navigation.section = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).frame(width: 20)
                            Text(section.rawValue)
                            Spacer()
                            if section == .tasks, appState.activeTaskCount > 0 {
                                Text("\(appState.activeTaskCount)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 13, weight: navigation.section == section ? .semibold : .regular))
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(navigation.section == section ? Color.white.opacity(0.09) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                }
            }
            Spacer()
            if case .recording(let startedAt) = appState.meetingFlow {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Kayıt sürüyor", systemImage: "record.circle.fill").foregroundStyle(.red)
                    Text(startedAt, style: .timer).monospacedDigit()
                    Button("Kaydı bitir", action: delegate.stopRecordingFlow)
                }.font(.callout).padding(12)
            }
            VStack(alignment: .leading, spacing: 12) {
                Button(action: delegate.showMeetingNotch) {
                    Label("Notch’u göster", systemImage: "rectangle.topthird.inset.filled")
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
                }.buttonStyle(.plain)
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Notch arka planda açık").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(12)
        }
        .padding(12).frame(width: 190)
        .background(.ultraThinMaterial)
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
                        Text("Toplantılar").font(.system(size: 24, weight: .bold))
                        Text("\(appState.storedMeetings.count) kayıt").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: delegate.startManualRecording) { Image(systemName: "record.circle").foregroundStyle(.red) }
                        .help("Yeni kayıt başlat").controlSize(.large)
                        .disabled(appState.requiresTerminationConfirmation)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Toplantılarda ara", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if !appState.upcomingMeetings.isEmpty && query.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YAKLAŞAN").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(appState.upcomingMeetings.prefix(2)) { meeting in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meeting.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(meeting.startDate.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if let url = meeting.meetingURL {
                                    Button("Katıl") { delegate.openMeetingURL(url) }.controlSize(.small)
                                }
                            }.padding(10).background(Color.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                if filtered.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Henüz kayıt yok" : "Sonuç bulunamadı",
                        systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                        description: Text(query.isEmpty ? "İlk toplantınız kaydedildiğinde burada görünecek." : "Başka bir toplantı adı deneyin."))
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
                                    Label("İşleniyor", systemImage: "ellipsis").font(.caption).foregroundStyle(.cyan)
                                } else if meeting.processingStatus == .failed {
                                    Label("İşlem tamamlanamadı", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                                } else if meeting.summaryNeedsAttention == true {
                                    Text("Özet bekliyor").font(.caption).foregroundStyle(.orange)
                                }
                            }.padding(.vertical, 8).tag(meeting.id)
                                .contextMenu {
                                    if meeting.processingStatus == .failed {
                                        Button("İşlemeyi tekrar dene") { delegate.retryProcessing(meeting) }
                                    }
                                    Button("Toplantıyı sil…", role: .destructive) { delegate.deleteStoredMeeting(meeting) }
                                }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }.padding(20).frame(width: 280)
            Divider()
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
                ContentUnavailableView {
                    Label("Toplantı açılamadı", systemImage: "exclamationmark.triangle")
                } description: { Text("Dosyalar okunamadı. Kaydı tekrar açmayı deneyin.") }
                actions: { Button("Tekrar dene") { revision += 1 } }
            } else { ProgressView("Toplantı açılıyor…") }
        } else {
            ContentUnavailableView {
                Label("Toplantılarınız, tek bir yerde", systemImage: "waveform")
            } description: {
                Text("Özeti okuyun, konuşmacıları düzenleyin ve\ngörevleri takip edin. Başlamak için bir toplantı seçin.")
            } actions: {
                Button("Yeni kayıt", action: delegate.startManualRecording)
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
        } catch { if !Task.isCancelled { loadError = true; detail = nil } }
    }
}
