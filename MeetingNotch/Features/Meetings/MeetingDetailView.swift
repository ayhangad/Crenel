@preconcurrency import AVFoundation
import SwiftUI

enum TranscriptTextFormatter {
    static func plainText(_ transcript: Transcript) -> String {
        guard !transcript.segments.isEmpty else {
            return transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return transcript.segments.map { segment in
            let speaker = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = speaker.flatMap { $0.isEmpty ? nil : $0 }
                ?? fallbackSpeakerName(segment.speakerID)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(displayName) [\(timestamp(segment.startTime))]\n\(text)"
        }
        .joined(separator: "\n\n")
    }

    static func fallbackSpeakerName(_ speakerID: String) -> String {
        let suffix = speakerID
            .split(separator: "_")
            .last
            .flatMap { Int($0) }
            .map { String($0 + 1) }
        return "Speaker \(suffix ?? speakerID)"
    }

    static func timestamp(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum TranscriptPresentationPolicy {
    // SwiftUI's macOS text-selection bridge retains a native text view for each
    // selectable row. Keeping it enabled on hundreds of rows makes scrolling grow
    // progressively more expensive, even when the rows live in a LazyVStack.
    static let inlineSelectionSegmentLimit = 80

    static func allowsInlineTextSelection(segmentCount: Int) -> Bool {
        segmentCount <= inlineSelectionSegmentLimit
    }
}

struct MeetingDetailContent: Identifiable {
    let meeting: StoredMeeting
    let storedTranscription: StoredTranscription?
    let markdown: String?
    let audioURL: URL

    var id: UUID { meeting.id }
}

@MainActor
final class MeetingAudioPlayer: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false

    let duration: TimeInterval
    private let player: AVPlayer
    private var timeObserver: Any?

    init(url: URL, duration: TimeInterval) {
        self.duration = max(duration, 0.1)
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = min(max(time.seconds, 0), self.duration)
                if self.currentTime >= self.duration - 0.1 {
                    self.isPlaying = false
                }
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func pause() { player.pause(); isPlaying = false }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func play(from seconds: TimeInterval) {
        seek(to: seconds)
        player.play()
        isPlaying = true
    }

    func seek(to seconds: TimeInterval) {
        let clamped = min(max(seconds, 0), duration)
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}

struct MeetingDetailToolbar: View {
    let content: MeetingDetailContent
    let onBack: () -> Void
    let onCopyText: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedFormat: CopyFormat?
    @State private var copyRevision = 0

    private enum CopyFormat {
        case text
        case markdown
    }

    var body: some View {
        HStack(spacing: Hud.Space.x2) {
            Button(action: onBack) {
                CrenelIcon(.chevronLeft, size: Hud.Size.icon)
            }
            .buttonStyle(HudButtonStyle(kind: .icon))
            .help("Back to meetings")
            .accessibilityLabel("Back to meetings")

            VStack(alignment: .leading, spacing: 2) {
                Text(content.meeting.title)
                    .hud(.title)
                    .lineLimit(1)
                    .help(content.meeting.title)

                Text(detailLine)
                    .hud(.meta, Hud.Ink.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if let transcription = content.storedTranscription {
                    Button {
                        copy(TranscriptTextFormatter.plainText(transcription.transcript), format: .text)
                    } label: {
                        copyLabel("TXT", format: .text)
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .help("Copy transcript as plain text")
                    .accessibilityLabel("Copy transcript as plain text")
                }

                Button {
                    guard let markdown = content.markdown else { return }
                    copy(markdown, format: .markdown)
                } label: {
                    copyLabel("MD", format: .markdown)
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
                .disabled(content.markdown == nil)
                .opacity(content.markdown == nil ? 0.4 : 1)
                .help("Copy meeting as Markdown")
                .accessibilityLabel("Copy meeting as Markdown")
            }
        }
        .animation(Crenel.Motion.resolve(Hud.Motion.hover, reduceMotion: reduceMotion), value: copiedFormat)
        .task(id: copyRevision) {
            guard copiedFormat != nil else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            copiedFormat = nil
        }
    }

    private var detailLine: String {
        let date = content.meeting.startedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.locale)
        )
        let duration = TranscriptTextFormatter.timestamp(content.meeting.duration)
        return "\(date) · \(duration)"
    }

    /// The label keeps its width; a copy is confirmed by the label turning green.
    @ViewBuilder
    private func copyLabel(_ label: String, format: CopyFormat) -> some View {
        if copiedFormat == format {
            Text(verbatim: label).foregroundStyle(Hud.Ink.ok)
        } else {
            // Inherits the button style's hover-aware colour.
            Text(verbatim: label)
        }
    }

    private func copy(_ value: String, format: CopyFormat) {
        onCopyText(value)
        copiedFormat = format
        copyRevision += 1
    }
}

struct MeetingDetailView: View {
    let content: MeetingDetailContent
    let onCopyText: (String) -> Void
    let onExportMarkdown: (String) -> Void
    let onRevealAudio: (URL) -> Void
    let onRetry: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void

    let analysisActions: MeetingAnalysisActions
    let isProcessing: Bool
    let importedActionIDs: Set<UUID>
    @State private var editingSpeakerID: String?
    @State private var editingSpeakerName = ""
    @State private var analysisMessage: String?
    @State private var savingSpeaker = false
    @State private var analysisFailed = false
    @State private var copiedNotes = false
    @State private var notesCopyRevision = 0
    @FocusState private var speakerFieldFocused: Bool
    @State private var importingActions = Set<UUID>()
    @State private var showsAllActions = false
    @State private var hoveredAction: AnyHashable?
    @Namespace private var actionGlide

    // State keeps the controller alive without subscribing this entire detail tree to
    // its 4 Hz playback updates. CompactAudioPlayer is the only observing view.
    @State private var player: MeetingAudioPlayer

    private static let collapsedActionCount = 6

    init(
        content: MeetingDetailContent,
        onCopyText: @escaping (String) -> Void,
        onExportMarkdown: @escaping (String) -> Void,
        onRevealAudio: @escaping (URL) -> Void,
        onRetry: @escaping (StoredMeeting) -> Void,
        onDelete: @escaping (StoredMeeting) -> Void,
        analysisActions: MeetingAnalysisActions = MeetingAnalysisActions(),
        isProcessing: Bool = false,
        importedActionIDs: Set<UUID> = []
    ) {
        self.content = content
        self.onCopyText = onCopyText
        self.onExportMarkdown = onExportMarkdown
        self.onRevealAudio = onRevealAudio
        self.onRetry = onRetry
        self.onDelete = onDelete
        self.analysisActions = analysisActions
        self.isProcessing = isProcessing
        self.importedActionIDs = importedActionIDs
        _player = State(
            initialValue: MeetingAudioPlayer(
                url: content.audioURL,
                duration: content.meeting.duration
            )
        )
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            CompactAudioPlayer(player: player)

            actionBar
                .padding(.top, Hud.Space.x2)

            if let storedTranscription = content.storedTranscription {
                if let summary = storedTranscription.summary {
                    summarySection(summary)
                        .padding(.top, Hud.Space.x5)
                }

                let transcript = storedTranscription.transcript
                let allowsInlineTextSelection = TranscriptPresentationPolicy
                    .allowsInlineTextSelection(segmentCount: transcript.segments.count)

                groupHeader("Transcript")
                    .padding(.top, Hud.Space.x5)

                if transcript.segments.isEmpty {
                    Text(transcript.text)
                        .font(Hud.font(13, .regular))
                        .foregroundStyle(Hud.Ink.text1)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Hud.Size.rowInset)
                        .padding(.vertical, Hud.Space.x2)
                } else {
                    // Rows stay direct children of the scroll view's outer LazyVStack.
                    // A nested stack turns the whole transcript into one eager child.
                    ForEach(transcript.segments) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            allowsInlineTextSelection: allowsInlineTextSelection,
                            onSeek: { player.play(from: segment.startTime) },
                            onCopy: {
                                onCopyText(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        )
                        .equatable()
                    }
                }
            } else {
                processingState
                    .padding(.top, Hud.Space.x4)
            }
        }
        .onDisappear { player.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .desktopDidClose)) { _ in player.pause() }
        .sheet(isPresented: Binding(get: { editingSpeakerID != nil }, set: { if !$0 { editingSpeakerID = nil } })) {
            renameSpeakerSheet
        }
        .task(id: notesCopyRevision) {
            guard copiedNotes else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            copiedNotes = false
        }
    }

    // MARK: Actions

    /// One line of controls under the player: summary on the left, speakers and the
    /// overflow menu on the right. Messages appear underneath, in colour, without icons.
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: Hud.Space.x1) {
            HStack(spacing: 2) {
                if let stored = content.storedTranscription {
                    Button {
                        onRetry(content.meeting)
                    } label: {
                        HStack(spacing: 7) {
                            HudIcon(.spark, size: Hud.Size.smallIcon)
                            Text(stored.summary?.model == nil ? "Create summary" : "Refresh summary")
                        }
                    }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .disabled(isProcessing || savingSpeaker)

                    if isProcessing {
                        HudPulse(color: Hud.Ink.signal)
                            .padding(.leading, Hud.Space.x1)
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: Hud.Space.x2)

                if let stored = content.storedTranscription {
                    speakersMenu(stored)
                }

                moreMenu
            }
            .animation(Hud.Motion.change, value: isProcessing)

            if let failure = content.storedTranscription?.summaryFailure {
                HStack(spacing: Hud.Space.x2) {
                    feedbackLine(failure, isFailure: true)
                    Spacer(minLength: 0)
                    DesktopSettingsLink(category: .ai) { Text("Open OpenAI settings") }
                        .buttonStyle(HudButtonStyle(kind: .ghost))
                }
            }
            if let analysisMessage {
                feedbackLine(analysisMessage, isFailure: analysisFailed)
            }
        }
    }

    private func speakersMenu(_ stored: StoredTranscription) -> some View {
        Menu {
            ForEach(Array(Set(stored.transcript.segments.map(\.speakerID))).sorted(), id: \.self) { id in
                let name = stored.transcript.segments.first { $0.speakerID == id }?.speakerName
                Button(name ?? TranscriptTextFormatter.fallbackSpeakerName(id)) {
                    editingSpeakerID = id
                    editingSpeakerName = name ?? ""
                    analysisMessage = nil
                }
            }
        } label: {
            HStack(spacing: 7) {
                CrenelIcon(.people, size: Hud.Size.smallIcon)
                Text("Speakers")
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HudButtonStyle(kind: .ghost))
        .fixedSize()
        .disabled(isProcessing)
    }

    private var moreMenu: some View {
        Menu {
            Button("Show audio in Finder") {
                onRevealAudio(content.audioURL)
            }

            if let markdown = content.markdown {
                Button("Save Markdown") {
                    onExportMarkdown(markdown)
                }
            }

            if content.meeting.processingStatus == .failed
                || content.meeting.processingStatus == .recorded {
                Button("Retry processing") {
                    onRetry(content.meeting)
                }
            }

            Divider()

            Button("Delete meeting", role: .destructive) {
                onDelete(content.meeting)
            }
        } label: {
            CrenelIcon(.more, size: Hud.Size.icon)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HudButtonStyle(kind: .icon))
        .fixedSize()
        .help("Audio, export, and meeting actions")
        .accessibilityLabel("More actions")
    }

    private func feedbackLine(_ message: String, isFailure: Bool) -> some View {
        Text(message)
            .hud(.meta, isFailure ? Hud.Ink.live : Hud.Ink.ok)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    private func recordResult(_ result: SettingsActionResult) {
        withAnimation(Hud.Motion.change) {
            switch result {
            case .succeeded(let message): analysisMessage = message ?? "Saved."; analysisFailed = false
            case .failed(let message): analysisMessage = message; analysisFailed = true
            }
        }
    }

    // MARK: Rename speaker

    private var renameSpeakerSheet: some View {
        VStack(alignment: .leading, spacing: Hud.Space.x4) {
            Text("Rename speaker")
                .hud(.title)

            TextField("Name", text: $editingSpeakerName)
                .textFieldStyle(.plain)
                .hud(.body)
                .focused($speakerFieldFocused)
                .padding(.horizontal, Hud.Size.rowInset)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                        .fill(speakerFieldFocused ? Hud.Ink.selected : Hud.Ink.hover)
                )
                .animation(Hud.Motion.hover, value: speakerFieldFocused)
                .accessibilityLabel("Speaker name")

            HStack(spacing: Hud.Space.x2) {
                if savingSpeaker {
                    HudPulse(color: Hud.Ink.signal)
                        .accessibilityLabel("Saving…")
                }
                Spacer()
                Button("Cancel") { editingSpeakerID = nil }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
                    .disabled(savingSpeaker)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let speakerID = editingSpeakerID else { return }
                    savingSpeaker = true
                    Task {
                        let result = await analysisActions.renameSpeaker(content.id, speakerID, editingSpeakerName)
                        recordResult(result)
                        savingSpeaker = false
                        if case .succeeded = result { editingSpeakerID = nil }
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(savingSpeaker || isProcessing || editingSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let analysisMessage {
                Text(analysisMessage)
                    .hud(.meta, analysisFailed ? Hud.Ink.live : Hud.Ink.ok)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Hud.Space.x6)
        .frame(width: 380)
        .background(Hud.Ink.canvas)
        .preferredColorScheme(.dark)
        .onAppear { speakerFieldFocused = true }
    }

    // MARK: Notes

    private func summarySection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Hud.Space.x2) {
                groupHeader("Notes")
                Spacer(minLength: 0)
                Button {
                    onCopyText(MeetingMarkdownFormatter.notes(summary))
                    copiedNotes = true
                    notesCopyRevision += 1
                } label: {
                    if copiedNotes {
                        CrenelIcon(.copy, size: Hud.Size.smallIcon).foregroundStyle(Hud.Ink.ok)
                    } else {
                        CrenelIcon(.copy, size: Hud.Size.smallIcon)
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .icon))
                .animation(Hud.Motion.hover, value: copiedNotes)
                .help(copiedNotes ? "Notes copied" : "Copy notes")
                .accessibilityLabel("Copy meeting notes")
            }

            Text(
                summary.overview.isEmpty
                    ? String(localized: "The transcript doesn’t have enough content to summarize.")
                    : summary.overview
            )
            .font(Hud.font(13, .regular))
            .foregroundStyle(summary.overview.isEmpty ? Hud.Ink.text3 : Hud.Ink.text1)
            .textSelection(.enabled)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Hud.Size.rowInset)
            .padding(.top, Hud.Space.x1)

            if !summary.decisions.isEmpty {
                groupHeader("Decisions")
                    .padding(.top, Hud.Space.x4)
                VStack(alignment: .leading, spacing: Hud.Space.x2) {
                    ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(Hud.font(13, .regular))
                            .foregroundStyle(Hud.Ink.text1)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .padding(.top, Hud.Space.x1)
            }

            if !summary.actionItems.isEmpty {
                groupHeader("Action items")
                    .padding(.top, Hud.Space.x4)
                actionItemList(summary.actionItems)
            }
        }
    }

    private func actionItemList(_ items: [ActionItem]) -> some View {
        let limit = Self.collapsedActionCount
        let visible = showsAllActions ? items : Array(items.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { action in
                actionRow(action)
                    .hudGlide(action.id, hovered: $hoveredAction, in: actionGlide)
                    .transition(.opacity)
            }
            if items.count > limit {
                Button {
                    withAnimation(Hud.Motion.change) { showsAllActions.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        CrenelIcon(.chevronDown, size: Hud.Size.smallIcon)
                            .rotationEffect(.degrees(showsAllActions ? 180 : 0))
                        Text(showsAllActions ? "Show less" : "\(items.count - limit) more")
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .ghost))
                .padding(.top, Hud.Space.x1)
            }
        }
    }

    private func actionRow(_ action: ActionItem) -> some View {
        let imported = importedActionIDs.contains(action.id)
        let importing = importingActions.contains(action.id)
        return HStack(alignment: .top, spacing: Hud.Space.x3) {
            Button {
                importingActions.insert(action.id)
                Task {
                    recordResult(await analysisActions.importAction(content.id, action))
                    importingActions.remove(action.id)
                }
            } label: {
                // In tasks: the queue glyph. Not yet: a plus to add it.
                HudIcon(imported ? .queue : .plus, size: Hud.Size.icon)
                    .foregroundStyle(imported ? Hud.Ink.text3 : (importing ? Hud.Ink.text4 : Hud.Ink.text2))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(imported ? "In tasks" : "Add to tasks")
            .accessibilityLabel(imported ? Text("In tasks") : Text("Add to tasks: \(action.title)"))
            .disabled(imported || importing || isProcessing)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .hud(.body, imported ? Hud.Ink.text2 : Hud.Ink.text1)
                    .fixedSize(horizontal: false, vertical: true)
                if action.assignee != nil || action.dueDate != nil {
                    HStack(spacing: Hud.Space.x2) {
                        if let assignee = action.assignee { Text(assignee) }
                        if let date = action.dueDate { Text(date, style: .date) }
                    }
                    .hud(.meta, Hud.Ink.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let time = action.sourceTime {
                HudTimeButton(time: time) { player.play(from: time) }
                    .help("Play source")
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x2 + 1)
        .frame(minHeight: Hud.Size.row)
    }

    // MARK: Processing

    private var processingState: some View {
        HStack(alignment: .center, spacing: Hud.Space.x3) {
            processingMark
                .frame(width: Hud.Size.icon, height: Hud.Size.icon)

            Text(processingTitle)
                .hud(.body, content.meeting.processingStatus == .failed ? Hud.Ink.live : Hud.Ink.text1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if content.meeting.processingStatus == .failed || content.meeting.processingStatus == .completed {
                Button("Retry processing") { onRetry(content.meeting) }
                    .buttonStyle(HudButtonStyle(kind: .ghost))
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(minHeight: Hud.Size.row)
        .background(
            RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous).fill(Hud.Ink.hover)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var processingMark: some View {
        switch content.meeting.processingStatus {
        case .failed:
            CrenelIcon(.warning, size: Hud.Size.icon).foregroundStyle(Hud.Ink.live)
        case .completed:
            CrenelIcon(.warning, size: Hud.Size.icon).foregroundStyle(Hud.Ink.signal)
        case .processing:
            HudPulse(color: Hud.Ink.signal)
        case .recorded:
            HudIcon(.transcript, size: Hud.Size.icon).foregroundStyle(Hud.Ink.text3)
        }
    }

    private var processingTitle: LocalizedStringKey {
        switch content.meeting.processingStatus {
        case .failed: "Transcription didn’t finish"
        case .recorded: "Transcription queued"
        case .processing: "Preparing transcription"
        case .completed: "Couldn’t read the transcript"
        }
    }

    // MARK: Pieces

    /// A plain group title in the row inset: no rule, no count, no tracking.
    private func groupHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .hud(.label, Hud.Ink.text3)
            .padding(.horizontal, Hud.Size.rowInset)
            .frame(height: 22, alignment: .bottom)
            .padding(.bottom, Hud.Space.x1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A timestamp that plays from its moment. Quiet until hovered.
private struct HudTimeButton: View {
    let time: TimeInterval
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(TranscriptTextFormatter.timestamp(time))
                .hud(.meta, isHovering ? Hud.Ink.text1 : Hud.Ink.text3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
    }
}

private struct CompactAudioPlayer: View {
    @ObservedObject var player: MeetingAudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubbing = false
    @State private var scrubTime: TimeInterval = 0

    var body: some View {
        HStack(spacing: Hud.Space.x3) {
            Button(action: player.togglePlayback) {
                CrenelIcon(player.isPlaying ? .pause : .play, size: Hud.Size.smallIcon)
                    .foregroundStyle(Hud.Ink.text1)
                    .contentTransition(.opacity)
                    .animation(Crenel.Motion.resolve(Hud.Motion.hover, reduceMotion: reduceMotion), value: player.isPlaying)
            }
            .buttonStyle(HudButtonStyle(kind: .icon))
            .accessibilityLabel(player.isPlaying ? "Pause audio" : "Play audio")

            Text(TranscriptTextFormatter.timestamp(position))
                .hud(.meta, Hud.Ink.text2)
                .frame(width: timeWidth, alignment: .trailing)

            HudScrubber(
                value: position,
                duration: player.duration,
                isActive: player.isPlaying || scrubbing,
                onScrub: { time in scrubTime = time; scrubbing = true },
                onCommit: { time in player.seek(to: time); scrubbing = false }
            )

            Text(TranscriptTextFormatter.timestamp(player.duration))
                .hud(.meta, Hud.Ink.text3)
                .frame(width: timeWidth, alignment: .leading)
        }
        .padding(.leading, Hud.Size.rowInset - Hud.Space.x2)
        .padding(.trailing, Hud.Size.rowInset)
    }

    private var position: TimeInterval { scrubbing ? scrubTime : player.currentTime }
    private var timeWidth: CGFloat { player.duration >= 3600 ? 56 : 40 }
}

/// A thin track with a white fill. Click or drag anywhere to move the playhead.
private struct HudScrubber: View {
    let value: TimeInterval
    let duration: TimeInterval
    let isActive: Bool
    let onScrub: (TimeInterval) -> Void
    let onCommit: (TimeInterval) -> Void
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = duration > 0 ? min(1, max(0, value / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Hud.Ink.track)
                Capsule()
                    .fill(isActive || isHovering ? Hud.Ink.text1 : Hud.Ink.text2)
                    .frame(width: width * fraction)
            }
            .frame(height: 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(time(at: $0.location.x, width: width)) }
                    .onEnded { onCommit(time(at: $0.location.x, width: width)) }
            )
        }
        .frame(height: 18)
        .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(TranscriptTextFormatter.timestamp(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(duration, value + 5))
            case .decrement: onCommit(max(0, value - 5))
            @unknown default: break
            }
        }
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        duration * Double(min(1, max(0, x / width)))
    }
}

private struct TranscriptSegmentRow: View, Equatable {
    let segment: TranscriptSegment
    let allowsInlineTextSelection: Bool
    let onSeek: () -> Void
    let onCopy: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Hud.Space.x2) {
                Text(displaySpeakerName)
                    .hud(.label, Hud.Ink.text2)
                    .lineLimit(1)

                Spacer(minLength: Hud.Space.x2)

                Button(action: onCopy) { CrenelIcon(.copy, size: Hud.Size.smallIcon) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Hud.Ink.text3)
                    .opacity(isHovering ? 1 : 0)
                    .help("Copy this segment")
                    .accessibilityLabel("Copy transcript segment")

                HudTimeButton(time: segment.startTime, action: onSeek)
                    .help("Play from here")
                    .accessibilityLabel("Play from \(TranscriptTextFormatter.timestamp(segment.startTime))")
            }

            segmentText
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .padding(.vertical, Hud.Space.x2 + 1)
        .background(
            RoundedRectangle(cornerRadius: Hud.Size.corner, style: .continuous)
                .fill(isHovering ? Hud.Ink.hover : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Crenel.Motion.resolve(Hud.Motion.hover, reduceMotion: reduceMotion), value: isHovering)
        .contextMenu {
            Button("Copy segment", action: onCopy)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var segmentText: some View {
        let text = Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(Hud.font(13, .regular))
            .foregroundStyle(Hud.Ink.text1)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

        if allowsInlineTextSelection {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segment == rhs.segment
            && lhs.allowsInlineTextSelection == rhs.allowsInlineTextSelection
    }

    private var displaySpeakerName: String {
        let name = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 }
            ?? TranscriptTextFormatter.fallbackSpeakerName(segment.speakerID)
    }
}

#Preview("Compact meeting detail") {
    let meeting = StoredMeeting(
        id: UUID(),
        title: "Product sync / transcription",
        startedAt: Date().addingTimeInterval(-2_148),
        endedAt: Date(),
        sourceMeeting: nil,
        audioFileName: "preview.m4a",
        processingStatus: .completed
    )
    let transcript = Transcript(
        text: "",
        languageCode: "en",
        segments: [
            TranscriptSegment(
                speakerID: "speaker_0",
                speakerName: "Ayhan",
                startTime: 12,
                endTime: 29,
                text: "Let’s use the meeting detail inside the notch as the main results surface."
            ),
            TranscriptSegment(
                speakerID: "speaker_1",
                speakerName: "Deniz",
                startTime: 31,
                endTime: 48,
                text: "Keep the transcript and Markdown copy actions in the top row."
            )
        ]
    )
    let content = MeetingDetailContent(
        meeting: meeting,
        storedTranscription: StoredTranscription(
            transcript: transcript,
            summary: MeetingSummary(
                overview: "Meeting results are read inside the notch without opening a separate window.",
                decisions: ["The detail panel stays at the same width as every notch screen."],
                actionItems: [ActionItem(title: "Check the dark and light appearance matrix.")]
            )
        ),
        markdown: "# Product sync",
        audioURL: URL(fileURLWithPath: "/tmp/meeting-notch-preview.m4a")
    )

    VStack(spacing: Hud.Space.x4) {
        MeetingDetailToolbar(
            content: content,
            onBack: {},
            onCopyText: { _ in }
        )
        ScrollView {
            MeetingDetailView(
                content: content,
                onCopyText: { _ in },
                onExportMarkdown: { _ in },
                onRevealAudio: { _ in },
                onRetry: { _ in },
                onDelete: { _ in }
            )
        }
        .scrollIndicators(.hidden)
    }
    .padding(.horizontal, Hud.Size.panelInset - Hud.Size.rowInset)
    .padding(.vertical, Hud.Space.x4)
    .frame(width: Hud.Size.panelWidth, height: 600)
    .background(Hud.Ink.canvas)
    .environment(\.colorScheme, .dark)
}
