import SwiftUI

/// Meetings: the list on the window floor, the selected meeting on a sheet one layer up.
struct DesktopMeetingsPage: View {
    let actions: DesktopActions
    @Binding var selection: UUID?
    @ObservedObject var index: DesktopMeetingIndex
    let openSettings: (SettingsCategory) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var filter = DesktopMeetingFilter.all
    @FocusState private var searchFocused: Bool
    @State private var detail: MeetingDetailContent?
    @State private var loadError = false
    @State private var revision = 0
    @State private var hoveredRow: AnyHashable?
    @Namespace private var listSpace

    private var filtered: [StoredMeeting] {
        DesktopMeetingSearch.filter(appState.storedMeetings, query: query, transcripts: index.entries.mapValues(\.haystack))
            .filter { filter.matches($0, actionCount: index.entries[$0.id]?.actionCount ?? 0) }
    }
    private var selected: StoredMeeting? { appState.storedMeetings.first { $0.id == selection } }
    private var processing: Bool { appState.processingJobs.contains { $0.meetingID == selection && $0.state != .failed } }
    private var requestID: String { "\(selection?.uuidString ?? "")|\(selected?.title ?? "")|\(processing)|\(selected?.processingStatus.rawValue ?? "")|\(revision)" }
    private var isEmpty: Bool { appState.storedMeetings.isEmpty }

    var body: some View {
        DesktopClock { now in
            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 0) {
                    listColumn(now: now)
                        .frame(width: Hud.Window.meetingListWidth)
                    sheet
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .hudSheet()
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }
        }
        .task(id: requestID) { await loadSelection() }
        .onChange(of: appState.storedMeetings.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil; detail = nil }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        let total = appState.storedMeetings.reduce(0) { $0 + $1.duration }
        return DesktopToolbar(title: "Meetings",
                              meta: isEmpty ? nil : "\(appState.storedMeetings.count) recorded · \(DesktopFormat.tape(total)) on tape") {
            if !isEmpty {
                DesktopSearchField(text: $query, prompt: "Search meetings and transcripts", focus: $searchFocused)
                    .background {
                        Button("Search") { searchFocused = true }
                            .keyboardShortcut("f", modifiers: .command)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
            }
            HudButton("New recording", lamp: .red, size: .small, action: actions.startRecording)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.requiresTerminationConfirmation)
        }
    }

    // MARK: List column

    @ViewBuilder private func listColumn(now: Date) -> some View {
        let needsCount = appState.storedMeetings.filter(DesktopMeetingFilter.needsUser).count
        VStack(alignment: .leading, spacing: 0) {
            if isEmpty {
                VStack(spacing: 6) {
                    Text("No recordings yet").hud(.body, Hud.Ink.ink2)
                    Text("Crenel offers to record when a call starts.").hud(.meta)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
                Spacer(minLength: 0)
            } else {
                HudAnnunciator(items: [.init(DesktopMeetingFilter.all, "All"),
                                       .init(DesktopMeetingFilter.needsYou, "Needs you", count: needsCount > 0 ? needsCount : nil),
                                       .init(DesktopMeetingFilter.forYou, "For you")],
                               selection: $filter)
                    .frame(height: 26)
                    .padding(.leading, 10)
                    .padding(.bottom, 6)
                list(now: now)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }

    private func list(now: Date) -> some View {
        let meetings = filtered
        let showsUpcoming = query.trimmingCharacters(in: .whitespaces).isEmpty && filter == .all
        let upcoming = showsUpcoming ? Array(appState.upcomingMeetings.filter { !$0.isAllDay && $0.endDate > now }.prefix(2)) : []
        let groups = Dictionary(grouping: meetings) { Calendar.current.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !upcoming.isEmpty {
                    HudGroupHeader(title: "Coming up").accessibilityAddTraits(.isHeader)
                    ForEach(upcoming) { meeting in upcomingRow(meeting, now: now) }
                }
                if meetings.isEmpty {
                    VStack(spacing: 4) {
                        Text(query.isEmpty ? "Nothing here" : "No results").hud(.body, Hud.Ink.ink2)
                        Text(query.isEmpty ? "No recording matches this filter." : "Try another name or a phrase from the call.").hud(.meta)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                }
                ForEach(Array(groups.enumerated()), id: \.element.key) { offset, group in
                    HudGroupHeader(title: DesktopFormat.dayGroup(group.key, now: now))
                        .padding(.top, offset > 0 || !upcoming.isEmpty ? 8 : 0)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.value.sorted { $0.startedAt > $1.startedAt }) { meeting in
                        meetingRow(meeting)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
    }

    private func upcomingRow(_ meeting: Meeting, now: Date) -> some View {
        HudRow(.twoLine) {
            HudTimeColumn(DesktopFormat.clock(meeting.startDate))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: meeting.title).hud(.body).lineLimit(1).truncationMode(.tail)
                Text(verbatim: upcomingMeta(meeting, now: now)).hud(.meta).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hudGlide(AnyHashable("upcoming-\(meeting.id)"), hovered: $hoveredRow, in: listSpace)
        .contextMenu {
            if let url = meeting.meetingURL {
                Button("Join meeting") { actions.openMeetingURL(url) }
                Button("Copy link") { actions.copyText(url.absoluteString) }
            }
            Button("Open in Calendar") { crenelActions.openInCalendar(meeting) }
        }
        .accessibilityElement(children: .combine)
    }

    private func upcomingMeta(_ meeting: Meeting, now: Date) -> String {
        let venue = DesktopFormat.venue(meeting)
        if Calendar.current.isDate(meeting.startDate, inSameDayAs: now) {
            let when = meeting.startDate > now ? "in \(NotchAgendaFormatter.durationText(meeting.startDate.timeIntervalSince(now)))" : "now"
            return [venue, when].compactMap { $0 }.joined(separator: " · ")
        }
        return [DesktopFormat.weekday(meeting.startDate), venue].compactMap { $0 }.joined(separator: " · ")
    }

    private func meetingRow(_ meeting: StoredMeeting) -> some View {
        let isSelected = selection == meeting.id
        let state = DesktopMeetingState.resolve(meeting, jobs: appState.processingJobs)
        return Button {
            selection = meeting.id
        } label: {
            HudRow(.twoLine) {
                HudTimeColumn(DesktopFormat.clock(meeting.startedAt), DesktopFormat.runLength(meeting.duration))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: meeting.title).hud(.body).lineLimit(1).truncationMode(.tail)
                    Text(verbatim: rowMeta(meeting, state: state)).hud(.meta).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                switch state {
                case .processing: HudBusy().padding(.top, 5)
                case .failed: HudStatusShape(.err).padding(.top, 3)
                case .transcriptOnly: HudStatusShape(.warn).padding(.top, 3)
                case .ready, .notTranscribed: EmptyView()
                }
            }
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Hud.Row.radius, style: .continuous).fill(Color(white: 1, opacity: 0.06))
                        .overlay(alignment: .topLeading) {
                            Capsule().fill(Hud.Ink.ink1)
                                .shadow(color: Hud.Ink.ink1.opacity(0.7), radius: 3)
                                .frame(width: 3, height: 22)
                                .offset(x: 3, y: 14)
                        }
                        .matchedGeometryEffect(id: "desktop.meeting", in: listSpace)
                }
            }
            .hudGlide(meeting.id, hovered: $hoveredRow, in: listSpace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if meeting.processingStatus == .failed {
                Button("Retry processing") { actions.retryProcessing(meeting) }
            }
            Button("Delete meeting…", role: .destructive) { actions.deleteMeeting(meeting) }
        }
    }

    /// Second line: what the meeting left you and who was there, or the state it is in.
    private func rowMeta(_ meeting: StoredMeeting, state: DesktopMeetingState) -> String {
        switch state {
        case .processing: return "Processing"
        case .failed: return "Transcription failed"
        case .transcriptOnly: return "Transcript only"
        case .notTranscribed: return "Not transcribed"
        case .ready:
            var parts: [String] = []
            let entry = index.entries[meeting.id]
            if let entry, entry.actionCount > 0 { parts.append("\(entry.actionCount) for you") }
            if let speakers = entry?.speakers, !speakers.isEmpty {
                parts.append(speakers.prefix(3).joined(separator: ", "))
            } else if let people = meeting.sourceMeeting.flatMap({ MeetingPeopleFormatter.count($0.attendees) }) {
                // No voices told apart: the calendar's head count ("5 people").
                parts.append(people)
            }
            if parts.isEmpty, let source = meeting.sourceMeeting, let venue = DesktopFormat.venue(source) { parts.append(venue) }
            return parts.isEmpty ? "Notes ready" : parts.joined(separator: " · ")
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let ids = filtered.sorted { $0.startedAt > $1.startedAt }.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let next: Int
        if let selection, let index = ids.firstIndex(of: selection) {
            next = min(max(index + offset, 0), ids.count - 1)
        } else {
            next = offset > 0 ? 0 : ids.count - 1
        }
        withAnimation(reduceMotion ? nil : Hud.Motion.slab) { selection = ids[next] }
        return .handled
    }

    // MARK: Sheet

    @ViewBuilder private var sheet: some View {
        if let detail, detail.id == selection {
            DesktopMeetingDetail(content: detail, actions: actions, isProcessing: processing,
                                 importedActionIDs: Set(appState.tasks.filter { $0.sourceMeetingID == detail.id }.compactMap(\.sourceActionID)),
                                 openSettings: openSettings,
                                 onChanged: { index.invalidate(detail.id); revision += 1 })
                .id(detail.id)
        } else if let selected {
            if loadError {
                VStack(spacing: 16) {
                    HudStatusWell(.err)
                    VStack(spacing: 4) {
                        Text("Couldn’t open this meeting").hud(.body, Hud.Ink.ink1)
                        Text("Its files couldn’t be read. The audio is still on disk.").hud(.meta)
                    }
                    HStack(spacing: 8) {
                        HudButton("Show in Finder", glyph: .archive) { actions.revealMeetingAudio(selected) }
                        HudButton("Try again", key: "↩", kind: .primary) { revision += 1 }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .multilineTextAlignment(.center)
            } else {
                HStack(spacing: 8) {
                    HudSpinner()
                    Text("Opening meeting…").hud(.meta)
                }
            }
        } else {
            VStack(spacing: 20) {
                HudGauge(value: 0, size: 120, bleed: false) {
                    HudIcon(.tape, size: 20).foregroundStyle(Hud.Ink.ink4)
                }
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("Pick a meeting").hud(.body, Hud.Ink.ink2)
                    Text("Notes, tasks and the transcript open here.").hud(.meta)
                }
                HudButton("New recording", lamp: .red, action: actions.startRecording)
                    .disabled(appState.requiresTerminationConfirmation)
            }
        }
    }

    private func loadSelection() async {
        guard let meeting = selected else { detail = nil; return }
        loadError = false
        do {
            let loaded = try await actions.loadMeeting(meeting)
            guard !Task.isCancelled, selection == meeting.id else { return }
            detail = loaded
            index.update(loaded)
        } catch { if !Task.isCancelled, selection == meeting.id { loadError = true; detail = nil } }
    }
}
