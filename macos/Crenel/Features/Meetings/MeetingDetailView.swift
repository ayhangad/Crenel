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

// MARK: - Menu actions

/// What the band's "more" menu can do beyond copying.
struct MeetingDetailMenuActions {
    var onExportMarkdown: (String) -> Void
    var onRevealAudio: (URL) -> Void
    var onRetry: (StoredMeeting) -> Void
    var onDelete: (StoredMeeting) -> Void
}

/// The band and the body of a meeting detail are siblings, and only the body is handed
/// the export, retry and delete callbacks. The body leaves them here, keyed by meeting,
/// so a `MeetingDetailToolbar` built without `menuActions` can still offer them.
@MainActor
final class MeetingDetailActionRelay: ObservableObject {
    static let shared = MeetingDetailActionRelay()
    @Published private(set) var actions: [UUID: MeetingDetailMenuActions] = [:]

    func register(_ actions: MeetingDetailMenuActions, for id: UUID) { self.actions[id] = actions }
    func unregister(_ id: UUID) { actions[id] = nil }
}

// MARK: - Band

/// The detail's band (`tpl-detail` `.band`, 32 pt): back to Recordings on the left;
/// Copy (xs) and the "more" menu on the right. The camera gap stays empty between them.
///
///     MeetingDetailToolbar(content: detail, onBack: close, onCopyText: copy)
///     MeetingDetailToolbar(content: detail, onBack: close, onCopyText: copy, menuActions: actions)
struct MeetingDetailToolbar: View {
    let content: MeetingDetailContent
    let onBack: () -> Void
    let onCopyText: (String) -> Void
    /// Export, reveal, retry and delete for the "more" menu. When nil, the ones the
    /// visible `MeetingDetailView` registered are used.
    var menuActions: MeetingDetailMenuActions?
    /// The word beside the back arrow: where it leads.
    var backTitle: LocalizedStringKey = "Recordings"

    @ObservedObject private var relay = MeetingDetailActionRelay.shared
    @State private var copied = false
    @State private var copyRevision = 0

    init(
        content: MeetingDetailContent,
        onBack: @escaping () -> Void,
        onCopyText: @escaping (String) -> Void,
        menuActions: MeetingDetailMenuActions? = nil,
        backTitle: LocalizedStringKey = "Recordings"
    ) {
        self.content = content
        self.onBack = onBack
        self.onCopyText = onCopyText
        self.menuActions = menuActions
        self.backTitle = backTitle
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                HudIconButton(.chevronLeft, help: "Back to recordings", action: onBack)
                Text(backTitle).hud(.label, Hud.Ink.ink3).lineLimit(1)
            }
            .padding(.leading, -6)

            Spacer(minLength: 8)

            if content.storedTranscription != nil {
                Button {
                    onCopyText(copyText)
                    copied = true
                    copyRevision += 1
                } label: {
                    HStack(spacing: 4) {
                        HudIcon(.copy, size: 12).foregroundStyle(copied ? Hud.Ink.ok : Hud.Ink.ink2)
                        if copied {
                            Text("Copied").foregroundStyle(Hud.Ink.ok)
                        } else {
                            Text("Copy")
                        }
                    }
                }
                .buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))
                .help("Copy the notes and transcript")
                .accessibilityLabel("Copy the notes and transcript")
            }

            MeetingDetailMoreMenu(content: content, onCopyText: onCopyText, actions: menuActions ?? relay.actions[content.id])
        }
        .frame(height: Hud.Notch.bandHeight)
        .animation(Hud.Motion.hover, value: copied)
        .task(id: copyRevision) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
            copied = false
        }
    }

    /// Notes and transcript as Markdown when there are any, the plain transcript otherwise.
    private var copyText: String {
        if let markdown = content.markdown { return markdown }
        return content.storedTranscription.map { TranscriptTextFormatter.plainText($0.transcript) } ?? ""
    }
}

/// The "more" menu (`menu-more`): Copy as text · Save as Markdown · Show audio in
/// Finder · Retry processing — Delete meeting.
///
///     MeetingDetailMoreMenu(content: detail, onCopyText: copy, actions: actions)
struct MeetingDetailMoreMenu: View {
    let content: MeetingDetailContent
    let onCopyText: (String) -> Void
    let actions: MeetingDetailMenuActions?
    var framed = false

    var body: some View {
        Menu {
            if let transcription = content.storedTranscription {
                Button("Copy as text") { onCopyText(TranscriptTextFormatter.plainText(transcription.transcript)) }
            }
            if let actions {
                if let markdown = content.markdown {
                    Button("Save as Markdown") { actions.onExportMarkdown(markdown) }
                }
                Button("Show audio in Finder") { actions.onRevealAudio(content.audioURL) }
                if content.meeting.processingStatus != .processing {
                    Button("Retry processing") { actions.onRetry(content.meeting) }
                }
                Divider()
                Button("Delete meeting", role: .destructive) { actions.onDelete(content.meeting) }
            }
        } label: {
            HudIcon(.more, size: framed ? 14 : 16)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HudButtonStyle(kind: framed ? .iconFramed : .icon, size: framed ? .small : .regular))
        .fixedSize()
        .help("Export and actions")
        .accessibilityLabel("Export and actions")
    }
}

// MARK: - Detail

/// The meeting detail inside the open notch (`tpl-detail` + `tpl-detail-body`): title and
/// meta, the player, talk time, then Summary · Decided · For you · Transcript — or one
/// line saying why there is no transcript yet.
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
    /// Title and meta above the player. The desktop prints its own header.
    let showsHeader: Bool

    @State private var editingSpeakerID: String?
    @State private var editingSpeakerName = ""
    @State private var analysisFailure: String?
    @State private var savingSpeaker = false
    @State private var appeared = false
    @State private var hoveredSegment: AnyHashable?
    @Namespace private var segmentGlide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // State keeps the controller alive without subscribing this entire detail tree to
    // its 4 Hz playback updates. MeetingPlayerView is the only observing view.
    @State private var player: MeetingAudioPlayer

    init(
        content: MeetingDetailContent,
        onCopyText: @escaping (String) -> Void,
        onExportMarkdown: @escaping (String) -> Void,
        onRevealAudio: @escaping (URL) -> Void,
        onRetry: @escaping (StoredMeeting) -> Void,
        onDelete: @escaping (StoredMeeting) -> Void,
        analysisActions: MeetingAnalysisActions = MeetingAnalysisActions(),
        isProcessing: Bool = false,
        importedActionIDs: Set<UUID> = [],
        showsHeader: Bool = true,
        startAt: TimeInterval = 0
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
        self.showsHeader = showsHeader
        let player = MeetingAudioPlayer(url: content.audioURL, duration: content.meeting.duration)
        // Opens with the needle at a moment (an action item's source), without playing.
        if startAt > 0 { player.seek(to: startAt) }
        _player = State(initialValue: player)
    }

    var body: some View {
        // Rows stay direct children of the scroll view's LazyVStack: a nested stack
        // would turn the whole transcript into one eager child.
        LazyVStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                MeetingDetailHeader(meeting: content.meeting, transcript: content.storedTranscription?.transcript)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)
            }

            MeetingPlayerView(player: player, audioURL: content.audioURL)
                .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)

            if let stored = content.storedTranscription {
                let transcript = stored.transcript
                if !transcript.segments.isEmpty {
                    MeetingTalkTimeBar(talk: MeetingTalkTime(transcript: transcript), isDisabled: isProcessing || savingSpeaker) { speaker in
                        editingSpeakerID = speaker.id
                        editingSpeakerName = speaker.storedName ?? ""
                        analysisFailure = nil
                    }
                    .padding(.top, 12)
                    .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
                }

                if let analysisFailure, editingSpeakerID == nil {
                    HStack(spacing: 8) {
                        HudStatusShape(.err)
                        Text(analysisFailure).hud(.meta, Hud.Ink.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Hud.Row.inset)
                    .padding(.top, 10)
                    .transition(.opacity)
                }

                notes(stored)
                    .hudStagger(3, shown: appeared, reduceMotion: reduceMotion)

                HudGroupHeader(title: "Transcript")
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)
                    .hudStagger(4, shown: appeared, reduceMotion: reduceMotion)

                if transcript.segments.isEmpty {
                    Text(transcript.text)
                        .hud(.read)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Hud.Row.inset)
                        .padding(.vertical, 8)
                } else {
                    let selectable = TranscriptPresentationPolicy.allowsInlineTextSelection(segmentCount: transcript.segments.count)
                    ForEach(transcript.segments) { segment in
                        MeetingTranscriptRow(
                            segment: segment,
                            allowsInlineTextSelection: selectable,
                            onPlay: { player.play(from: segment.startTime) },
                            onCopy: { onCopyText(segment.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        )
                        .equatable()
                        .hudGlide(segment.id, hovered: $hoveredSegment, in: segmentGlide)
                    }
                }
            } else {
                MeetingTranscriptStateConsole(state: MeetingTranscriptState(content.meeting.processingStatus)) {
                    onRetry(content.meeting)
                }
                .padding(.top, 16)
                .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
            }
        }
        .onAppear {
            appeared = true
            MeetingDetailActionRelay.shared.register(menuActions, for: content.id)
        }
        .onDisappear {
            player.pause()
            MeetingDetailActionRelay.shared.unregister(content.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .desktopDidClose)) { _ in player.pause() }
        .sheet(isPresented: Binding(get: { editingSpeakerID != nil }, set: { if !$0 { editingSpeakerID = nil } })) {
            MeetingRenameSpeakerSheet(
                name: $editingSpeakerName,
                isSaving: savingSpeaker,
                message: analysisFailure,
                isDisabled: isProcessing,
                onCancel: { editingSpeakerID = nil },
                onSave: saveSpeakerName
            )
        }
    }

    private var menuActions: MeetingDetailMenuActions {
        MeetingDetailMenuActions(onExportMarkdown: onExportMarkdown, onRevealAudio: onRevealAudio, onRetry: onRetry, onDelete: onDelete)
    }

    // MARK: Notes

    /// Summary, Decided and For you — or, without notes, the reason and the way out.
    @ViewBuilder
    private func notes(_ stored: StoredTranscription) -> some View {
        if let summary = stored.summary, stored.summaryFailure == nil {
            VStack(alignment: .leading, spacing: 0) {
                MeetingSummarySection(
                    overview: summary.overview,
                    isRewriting: isProcessing,
                    isDisabled: savingSpeaker,
                    onRewrite: { onRetry(content.meeting) }
                )
                .padding(.top, 16)

                if !summary.decisions.isEmpty {
                    MeetingDecidedSection(decisions: summary.decisions)
                        .padding(.top, 12)
                }

                if !summary.actionItems.isEmpty {
                    MeetingForYouSection(
                        items: summary.actionItems,
                        importedIDs: importedActionIDs,
                        isDisabled: isProcessing,
                        onPlay: { player.play(from: $0) },
                        onAdd: addToTasks
                    )
                    .padding(.top, 12)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                MeetingNotesMissingConsole(failure: stored.summaryFailure)
                    .padding(.top, 16)
                MeetingSummarySection(
                    overview: nil,
                    placeholder: MeetingNotesMissingConsole.remainder(stored.summaryFailure),
                    isRewriting: isProcessing
                )
                .padding(.top, 16)
            }
        }
    }

    // MARK: Actions

    private func addToTasks(_ item: ActionItem) async {
        record(await analysisActions.importAction(content.id, item))
    }

    private func saveSpeakerName() {
        guard let speakerID = editingSpeakerID else { return }
        savingSpeaker = true
        Task {
            let result = await analysisActions.renameSpeaker(content.id, speakerID, editingSpeakerName)
            record(result)
            savingSpeaker = false
            if case .succeeded = result { editingSpeakerID = nil }
        }
    }

    /// Success is visible where it happened (the lamp, the new name); only failures
    /// are spelled out.
    private func record(_ result: SettingsActionResult) {
        withAnimation(Hud.Motion.hover) {
            switch result {
            case .succeeded: analysisFailure = nil
            case .failed(let message): analysisFailure = message
            }
        }
    }
}

#Preview("Meeting detail") {
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
        audioURL: URL(fileURLWithPath: "/tmp/crenel-preview.m4a")
    )

    VStack(spacing: 8) {
        MeetingDetailToolbar(content: content, onBack: {}, onCopyText: { _ in })
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
    .padding(.horizontal, Hud.Notch.openInset)
    .padding(.bottom, Hud.Notch.openBottom)
    .frame(width: Hud.Notch.openWidth, height: 600)
    .background(Color.black)
    .environment(\.colorScheme, .dark)
}
