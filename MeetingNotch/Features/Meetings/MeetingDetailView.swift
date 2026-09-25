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
        return "Konuşmacı \(suffix ?? speakerID)"
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
        HStack(spacing: MeetingNotchTheme.itemSpacing) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(MeetingNotchIconButtonStyle())
            .help("Toplantılara dön")
            .accessibilityLabel("Toplantılara dön")

            VStack(alignment: .leading, spacing: 2) {
                Text(content.meeting.title)
                    .font(MeetingNotchTheme.titleFont)
                    .lineLimit(1)
                    .help(content.meeting.title)

                Text(detailLine)
                    .font(MeetingNotchTheme.metadataFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let transcription = content.storedTranscription {
                Button {
                    copy(
                        TranscriptTextFormatter.plainText(transcription.transcript),
                        format: .text
                    )
                } label: {
                    copyLabel("TXT", format: .text)
                }
                .buttonStyle(
                    MeetingNotchIconButtonStyle(
                        tint: MeetingNotchTheme.success,
                        isActive: copiedFormat == .text
                    )
                )
                .help("Transkripti düz metin olarak kopyala")
                .accessibilityLabel("Transkripti düz metin olarak kopyala")
            }

            Button {
                guard let markdown = content.markdown else { return }
                copy(markdown, format: .markdown)
            } label: {
                copyLabel("MD", format: .markdown)
            }
            .buttonStyle(
                MeetingNotchIconButtonStyle(
                    tint: MeetingNotchTheme.accent,
                    isActive: copiedFormat == .markdown
                )
            )
            .disabled(content.markdown == nil)
            .help("Toplantıyı Markdown olarak kopyala")
            .accessibilityLabel("Toplantıyı Markdown olarak kopyala")
        }
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: copiedFormat)
        .task(id: copyRevision) {
            guard copiedFormat != nil else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            copiedFormat = nil
        }
    }

    private var detailLine: String {
        let date = content.meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
        let duration = TranscriptTextFormatter.timestamp(content.meeting.duration)
        return "\(date) · \(duration)"
    }

    @ViewBuilder
    private func copyLabel(_ label: String, format: CopyFormat) -> some View {
        if copiedFormat == format {
            Image("FigmaRecentCheck")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Text(label)
                .font(MeetingNotchTheme.MainPanel.smallMediumFont.monospaced())
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

    // State keeps the controller alive without subscribing this entire detail tree to
    // its 4 Hz playback updates. CompactAudioPlayer is the only observing view.
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
                .padding(.bottom, MeetingNotchTheme.sectionSpacing)

            if let storedTranscription = content.storedTranscription {
                if let summary = storedTranscription.summary {
                    summarySection(summary)
                        .padding(.bottom, MeetingNotchTheme.sectionSpacing)
                }

                analysisControls(storedTranscription)
                    .padding(.bottom, MeetingNotchTheme.sectionSpacing)

                let transcript = storedTranscription.transcript
                let allowsInlineTextSelection = TranscriptPresentationPolicy
                    .allowsInlineTextSelection(segmentCount: transcript.segments.count)

                sectionHeader("Transkript", assetName: "FigmaVoice") {
                    Text("\(transcript.segments.count) bölüm")
                        .font(MeetingNotchTheme.dataFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                }
                .padding(.bottom, MeetingNotchTheme.contentSpacing)

                if transcript.segments.isEmpty {
                    Text(transcript.text)
                        .font(MeetingNotchTheme.bodyFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
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
            }

            utilityActions
                .padding(.top, MeetingNotchTheme.sectionSpacing)
        }
        .onDisappear { player.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .desktopDidClose)) { _ in player.pause() }
        .sheet(isPresented: Binding(get: { editingSpeakerID != nil }, set: { if !$0 { editingSpeakerID = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Konuşmacıyı adlandır", systemImage: "person.crop.circle")
                    .font(MeetingNotchTheme.titleFont)
                TextField("Ad", text: $editingSpeakerName)
                    .focused($speakerFieldFocused).meetingFieldSurface(focused: speakerFieldFocused).accessibilityLabel("Konuşmacının adı")
                HStack {
                    Button("Vazgeç") { editingSpeakerID = nil }.disabled(savingSpeaker)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Kaydet") {
                        guard let speakerID = editingSpeakerID else { return }
                        savingSpeaker = true
                        Task {
                            let result = await analysisActions.renameSpeaker(content.id, speakerID, editingSpeakerName)
                            recordResult(result)
                            savingSpeaker = false
                            if case .succeeded = result { editingSpeakerID = nil }
                        }
                    }.buttonStyle(MeetingNotchActionButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(savingSpeaker || isProcessing || editingSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if savingSpeaker { ProgressView("Kaydediliyor…").controlSize(.small) }
                if let analysisMessage { MeetingNotchFeedback(message: analysisMessage, isFailure: analysisFailed) }
            }.padding(28).frame(width: 420)
                .buttonStyle(MeetingNotchActionButtonStyle())
                .background(MeetingNotchTheme.workspaceBackground)
                .preferredColorScheme(.dark)
                .onAppear { speakerFieldFocused = true }
        }
        .task(id: notesCopyRevision) {
            guard copiedNotes else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            copiedNotes = false
        }
    }

    private func analysisControls(_ stored: StoredTranscription) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(stored.summary?.model == nil ? "Özet oluştur" : "Özeti yenile") {
                    onRetry(content.meeting)
                }.buttonStyle(MeetingNotchActionButtonStyle())
                    .disabled(isProcessing || savingSpeaker)
                if isProcessing { ProgressView().controlSize(.small) }
                Spacer()
                Menu("Konuşmacılar") {
                    ForEach(Array(Set(stored.transcript.segments.map(\.speakerID))).sorted(), id: \.self) { id in
                        let name = stored.transcript.segments.first { $0.speakerID == id }?.speakerName
                        Button(name ?? TranscriptTextFormatter.fallbackSpeakerName(id)) {
                            editingSpeakerID = id
                            editingSpeakerName = name ?? ""
                            analysisMessage = nil
                        }
                    }
                }.menuStyle(.borderlessButton)
                    .frame(minHeight: 40).padding(.horizontal, 12)
                    .meetingControlFeedback(radius: 12)
                    .disabled(isProcessing)
            }
            if let failure = stored.summaryFailure {
                MeetingNotchFeedback(message: failure, isFailure: true)
                DesktopSettingsLink(category: .ai) { Text("OpenAI bağlantısını aç") }
            }
            if let analysisMessage { MeetingNotchFeedback(message: analysisMessage, isFailure: analysisFailed) }
        }
    }

    private func recordResult(_ result: SettingsActionResult) {
        switch result {
        case .succeeded(let message): analysisMessage = message ?? "Kaydedildi."; analysisFailed = false
        case .failed(let message): analysisMessage = message; analysisFailed = true
        }
    }

    private var utilityActions: some View {
        HStack {
            Spacer(minLength: 0)

            Menu {
                Button {
                    onRevealAudio(content.audioURL)
                } label: {
                    Label("Sesi Finder’da göster", systemImage: "waveform.path")
                }

                if let markdown = content.markdown {
                    Button {
                        onExportMarkdown(markdown)
                    } label: {
                        Label("Markdown kaydet", systemImage: "arrow.down.doc")
                    }
                }

                if content.meeting.processingStatus == .failed
                    || content.meeting.processingStatus == .recorded {
                    Button {
                        onRetry(content.meeting)
                    } label: {
                        Label("İşlemeyi tekrar dene", systemImage: "arrow.clockwise")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    onDelete(content.meeting)
                } label: {
                    Label("Toplantıyı sil", systemImage: "trash")
                }
            } label: {
                Label("Diğer işlemler", systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(minHeight: 40).padding(.horizontal, 12)
            .meetingControlFeedback(radius: 12)
            .fixedSize()
            .help("Ses, dışa aktarma ve toplantı işlemleri")
        }
        .font(MeetingNotchTheme.controlFont)
        .foregroundStyle(MeetingNotchTheme.secondaryText)
        .padding(.horizontal, 2)
    }

    private func summarySection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.contentSpacing) {
            sectionHeader("Notlar", assetName: "FigmaTasks") {
                Button {
                    onCopyText(MeetingMarkdownFormatter.notes(summary))
                    copiedNotes = true
                    notesCopyRevision += 1
                } label: {
                    Image(systemName: copiedNotes ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(MeetingNotchIconButtonStyle(tint: copiedNotes ? MeetingNotchTheme.success : MeetingNotchTheme.secondaryText, isActive: copiedNotes))
                .help(copiedNotes ? "Notlar kopyalandı" : "Notları kopyala")
                .accessibilityLabel("Toplantı notlarını kopyala")
            }

            Text(
                summary.overview.isEmpty
                    ? "Transkript özetlenecek yeterli içerik taşımıyor."
                    : summary.overview
            )
            .font(MeetingNotchTheme.bodyFont)
            .foregroundStyle(
                summary.overview.isEmpty
                    ? MeetingNotchTheme.secondaryText
                    : MeetingNotchTheme.primaryText
            )
            .textSelection(.enabled)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            if !summary.decisions.isEmpty {
                CompactSummaryList(title: "Kararlar", values: summary.decisions)
            }

            if !summary.actionItems.isEmpty {
                Text("Yapılacaklar").font(MeetingNotchTheme.titleFont)
                VStack(spacing: 0) {
                    ForEach(Array(summary.actionItems.prefix(showsAllActions ? summary.actionItems.count : 6))) { action in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                importingActions.insert(action.id)
                                Task {
                                    recordResult(await analysisActions.importAction(content.id, action))
                                    importingActions.remove(action.id)
                                }
                            } label: {
                                Image(systemName: importedActionIDs.contains(action.id) ? "checkmark.circle.fill" : "plus.circle")
                            }
                            .buttonStyle(MeetingNotchIconButtonStyle(tint: importedActionIDs.contains(action.id) ? MeetingNotchTheme.success : MeetingNotchTheme.secondaryText))
                            .help(importedActionIDs.contains(action.id) ? "Görevlerde" : "Görevlere ekle")
                            .accessibilityLabel(importedActionIDs.contains(action.id) ? "Görevlerde" : "Görevlere ekle: " + action.title)
                            .disabled(importedActionIDs.contains(action.id) || importingActions.contains(action.id) || isProcessing)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.title).font(MeetingNotchTheme.bodyFont).fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    if let assignee = action.assignee { Text(assignee) }
                                    if let date = action.dueDate { Text(date, style: .date) }
                                }.font(.caption).foregroundStyle(MeetingNotchTheme.secondaryText)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            if let time = action.sourceTime {
                                Button(TranscriptTextFormatter.timestamp(time)) { player.play(from: time) }
                                    .buttonStyle(MeetingNotchActionButtonStyle())
                                    .help("Kaynağı dinle")
                            }
                        }
                        Divider().opacity(0.4)
                    }
                    if summary.actionItems.count > 6 {
                        Button {
                            showsAllActions.toggle()
                        } label: {
                            Label(showsAllActions ? "Daha az göster" : "Diğer \(summary.actionItems.count - 6) madde",
                                  systemImage: showsAllActions ? "chevron.up" : "chevron.down")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(MeetingNotchActionButtonStyle()).padding(.top, 8)
                    }
                }
            }
        }
        .padding(.horizontal, MeetingNotchTheme.panelHorizontalPadding)
        .padding(.vertical, MeetingNotchTheme.panelVerticalPadding)
        .background(
            MeetingNotchTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
        )
    }

    private var processingState: some View {
        HStack(spacing: 10) {
            Image(processingAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(processingColor)
                .frame(width: 20, height: 20)
                .padding(10)
                .background(
                    processingColor.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: MeetingNotchTheme.controlRadius,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(processingTitle)
                    .font(MeetingNotchTheme.titleFont)
                Text(processingDetail)
                    .font(MeetingNotchTheme.bodyFont)
                    .foregroundStyle(MeetingNotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MeetingNotchTheme.panelHorizontalPadding)
        .padding(.vertical, MeetingNotchTheme.panelVerticalPadding)
        .background(
            MeetingNotchTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
        )
    }

    private func sectionHeader<Accessory: View>(
        _ title: String,
        assetName: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: MeetingNotchTheme.itemSpacing) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(MeetingNotchTheme.primaryText)
            Text(title)
                .font(MeetingNotchTheme.titleFont)
                .foregroundStyle(MeetingNotchTheme.primaryText)
            Spacer()
            accessory()
        }
    }

    private var processingAsset: String {
        switch content.meeting.processingStatus {
        case .failed, .completed: "FigmaWarning"
        case .recorded, .processing: "FigmaVoice"
        }
    }

    private var processingColor: Color {
        content.meeting.processingStatus == .failed
            ? MeetingNotchTheme.danger
            : MeetingNotchTheme.cyan
    }

    private var processingTitle: String {
        switch content.meeting.processingStatus {
        case .failed: "Transkripsiyon tamamlanamadı"
        case .recorded: "Transkripsiyon sırada"
        case .processing: "Transkripsiyon hazırlanıyor"
        case .completed: "Transkript okunamadı"
        }
    }

    private var processingDetail: String {
        switch content.meeting.processingStatus {
        case .failed: "Ses kaydı korunuyor. Tekrar deneyebilirsiniz."
        case .recorded, .processing: "İşleme arka planda devam ediyor."
        case .completed: "Ses kaydı korunuyor; işlemeyi yeniden deneyebilirsiniz."
        }
    }
}

private struct CompactSummaryList: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MeetingNotchTheme.sectionTitleFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)

            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(MeetingNotchTheme.accent)
                        .frame(width: 4, height: 4)
                    Text(value)
                        .font(MeetingNotchTheme.bodyFont)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct CompactAudioPlayer: View {
    @ObservedObject var player: MeetingAudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubbing = false
    @State private var scrubTime: TimeInterval = 0

    var body: some View {
        HStack(spacing: 8) {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .offset(x: player.isPlaying ? 0 : 1)
            }
            .buttonStyle(
                MeetingNotchIconButtonStyle(
                    tint: MeetingNotchTheme.accent,
                    isActive: player.isPlaying
                )
            )
            .accessibilityLabel(player.isPlaying ? "Sesi duraklat" : "Sesi oynat")

            Text(TranscriptTextFormatter.timestamp(scrubbing ? scrubTime : player.currentTime))
                .font(MeetingNotchTheme.dataFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .frame(width: player.duration >= 3600 ? 62 : 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubbing ? scrubTime : player.currentTime },
                    set: { scrubTime = $0; if !scrubbing { player.seek(to: $0) } }
                ),
                in: 0...player.duration,
                onEditingChanged: { editing in
                    if editing { scrubTime = player.currentTime; scrubbing = true }
                    else { player.seek(to: scrubTime); scrubbing = false }
                }
            )
            .controlSize(.mini)
            .tint(MeetingNotchTheme.accent)
            .accessibilityLabel("Kayıt konumu")

            Text(TranscriptTextFormatter.timestamp(player.duration))
                .font(MeetingNotchTheme.dataFont)
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .frame(width: player.duration >= 3600 ? 62 : 44, alignment: .leading)
        }
        .padding(16)
        .background(
            MeetingNotchTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
        )
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(displaySpeakerName)
                    .font(MeetingNotchTheme.rowTitleFont)
                    .foregroundStyle(MeetingNotchTheme.cyan)
                    .lineLimit(1)

                Button(action: onSeek) {
                    Text(TranscriptTextFormatter.timestamp(segment.startTime))
                        .font(MeetingNotchTheme.dataFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText)
                }
                .buttonStyle(MeetingNotchActionButtonStyle())
                .help("Bu noktadan oynat")
                .accessibilityLabel("\(TranscriptTextFormatter.timestamp(segment.startTime)) konumundan oynat")

                Spacer()

                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(MeetingNotchIconButtonStyle(tint: MeetingNotchTheme.secondaryText))
                    .help("Bu bölümü kopyala").accessibilityLabel("Konuşma bölümünü kopyala")
            }

            segmentText
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isHovering ? MeetingNotchTheme.surfaceHover : MeetingNotchTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.controlRadius,
                style: .continuous
            )
        )
        .padding(.bottom, MeetingNotchTheme.MainPanel.rowSpacing)
        .onHover { isHovering = $0 }
        .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: isHovering)
        .contextMenu {
            Button("Segmenti kopyala", action: onCopy)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var segmentText: some View {
        let text = Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(MeetingNotchTheme.bodyFont)
            .lineSpacing(4)
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
        languageCode: "tr",
        segments: [
            TranscriptSegment(
                speakerID: "speaker_0",
                speakerName: "Ayhan",
                startTime: 12,
                endTime: 29,
                text: "Notch içindeki toplantı detayını ana sonuç yüzeyi olarak kullanalım."
            ),
            TranscriptSegment(
                speakerID: "speaker_1",
                speakerName: "Deniz",
                startTime: 31,
                endTime: 48,
                text: "Transkript ve Markdown kopyalama aksiyonları her zaman üst satırda kalsın."
            )
        ]
    )
    let content = MeetingDetailContent(
        meeting: meeting,
        storedTranscription: StoredTranscription(
            transcript: transcript,
            summary: MeetingSummary(
                overview: "Toplantı sonuçları ayrı pencere açmadan notch içinde tüketilecek.",
                decisions: ["Detay paneli tüm notch ekranlarıyla aynı 600 px genişlikte tutuldu."],
                actionItems: [ActionItem(title: "Koyu ve açık görünüm matrisini doğrula.")]
            )
        ),
        markdown: "# Product sync",
        audioURL: URL(fileURLWithPath: "/tmp/meeting-notch-preview.m4a")
    )

    VStack(spacing: MeetingNotchTheme.sectionSpacing) {
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
    .padding(.horizontal, MeetingNotchTheme.panelHorizontalPadding)
    .padding(.vertical, MeetingNotchTheme.panelVerticalPadding)
    .frame(width: MeetingNotchTheme.detailPanelWidth, height: 600)
    .background(.black)
    .environment(\.colorScheme, .dark)
}
