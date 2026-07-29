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

    @State private var copiedFormat: CopyFormat?

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

                Text(detailLine)
                    .font(MeetingNotchTheme.metadataFont)
                    .foregroundStyle(.secondary)
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
    }

    private var detailLine: String {
        let date = content.meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
        let duration = TranscriptTextFormatter.timestamp(content.meeting.duration)
        return "\(date.uppercased())  /  \(duration)"
    }

    @ViewBuilder
    private func copyLabel(_ label: String, format: CopyFormat) -> some View {
        if copiedFormat == format {
            Image(systemName: "checkmark")
                .contentTransition(.symbolEffect(.replace))
        } else {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
    }

    private func copy(_ value: String, format: CopyFormat) {
        onCopyText(value)
        copiedFormat = format
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard copiedFormat == format else { return }
            copiedFormat = nil
        }
    }
}

struct MeetingDetailView: View {
    let content: MeetingDetailContent
    let onCopyText: (String) -> Void
    let onExportMarkdown: (String) -> Void
    let onRevealAudio: (URL) -> Void
    let onRetry: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void

    @StateObject private var player: MeetingAudioPlayer

    init(
        content: MeetingDetailContent,
        onCopyText: @escaping (String) -> Void,
        onExportMarkdown: @escaping (String) -> Void,
        onRevealAudio: @escaping (URL) -> Void,
        onRetry: @escaping (StoredMeeting) -> Void,
        onDelete: @escaping (StoredMeeting) -> Void
    ) {
        self.content = content
        self.onCopyText = onCopyText
        self.onExportMarkdown = onExportMarkdown
        self.onRevealAudio = onRevealAudio
        self.onRetry = onRetry
        self.onDelete = onDelete
        _player = StateObject(
            wrappedValue: MeetingAudioPlayer(
                url: content.audioURL,
                duration: content.meeting.duration
            )
        )
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: MeetingNotchTheme.sectionSpacing) {
            CompactAudioPlayer(player: player)

            if let storedTranscription = content.storedTranscription {
                if let summary = storedTranscription.summary {
                    summarySection(summary)
                }
                transcriptSection(storedTranscription.transcript)
            } else {
                processingState
            }

            utilityActions
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
            .fixedSize()
            .help("Ses, dışa aktarma ve toplantı işlemleri")
        }
        .font(MeetingNotchTheme.controlFont)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    private func summarySection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: MeetingNotchTheme.contentSpacing) {
            sectionHeader("Notlar", symbol: "sparkles") {
                Button {
                    onCopyText(MeetingMarkdownFormatter.notes(summary))
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Notları kopyala")
                .accessibilityLabel("Toplantı notlarını kopyala")
            }

            Text(
                summary.overview.isEmpty
                    ? "Transkript özetlenecek yeterli içerik taşımıyor."
                    : summary.overview
            )
            .font(MeetingNotchTheme.bodyFont)
            .foregroundStyle(summary.overview.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)

            if !summary.decisions.isEmpty {
                CompactSummaryList(title: "Kararlar", values: summary.decisions)
            }

            if !summary.actionItems.isEmpty {
                CompactSummaryList(
                    title: "Aksiyonlar",
                    values: summary.actionItems.map(\.title)
                )
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
        .overlay {
            RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
            .stroke(MeetingNotchTheme.subtleHairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func transcriptSection(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Transkript", symbol: "quote.bubble") {
                Text("\(transcript.segments.count) segment")
                    .font(MeetingNotchTheme.dataFont)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)

            if transcript.segments.isEmpty {
                Text(transcript.text)
                    .font(MeetingNotchTheme.bodyFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(transcript.segments.enumerated()), id: \.element.id) { index, segment in
                        TranscriptSegmentRow(segment: segment) {
                            player.seek(to: segment.startTime)
                        }

                        if index < transcript.segments.count - 1 {
                            Divider()
                                .overlay(MeetingNotchTheme.subtleHairline)
                        }
                    }
                }
            }
        }
    }

    private var processingState: some View {
        HStack(spacing: 10) {
            Image(systemName: processingIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(processingColor)
                .frame(width: 30, height: 30)
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
                    .foregroundStyle(.secondary)
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
        symbol: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MeetingNotchTheme.accent)
            Text(title)
                .font(MeetingNotchTheme.sectionTitleFont)
                .foregroundStyle(.secondary)
            Spacer()
            accessory()
        }
    }

    private var processingIcon: String {
        switch content.meeting.processingStatus {
        case .failed: "exclamationmark.triangle"
        case .recorded: "clock"
        case .processing: "waveform.badge.magnifyingglass"
        case .completed: "text.badge.xmark"
        }
    }

    private var processingColor: Color {
        content.meeting.processingStatus == .failed ? .orange : MeetingNotchTheme.accent
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
                .foregroundStyle(.tertiary)

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

    var body: some View {
        HStack(spacing: 8) {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(
                MeetingNotchIconButtonStyle(
                    tint: MeetingNotchTheme.accent,
                    isActive: player.isPlaying
                )
            )
            .accessibilityLabel(player.isPlaying ? "Sesi duraklat" : "Sesi oynat")

            Text(TranscriptTextFormatter.timestamp(player.currentTime))
                .font(MeetingNotchTheme.dataFont)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...player.duration
            )
            .controlSize(.mini)
            .tint(MeetingNotchTheme.accent)
            .accessibilityLabel("Kayıt konumu")

            Text(TranscriptTextFormatter.timestamp(player.duration))
                .font(MeetingNotchTheme.dataFont)
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .leading)
        }
        .padding(8)
        .background(
            MeetingNotchTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MeetingNotchTheme.surfaceRadius,
                style: .continuous
            )
            .stroke(MeetingNotchTheme.subtleHairline, lineWidth: 1)
        }
    }
}

private struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let onSeek: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(displaySpeakerName.uppercased())
                    .font(MeetingNotchTheme.sectionTitleFont)
                    .foregroundStyle(MeetingNotchTheme.accent)
                    .lineLimit(1)

                Button(action: onSeek) {
                    Text(TranscriptTextFormatter.timestamp(segment.startTime))
                        .font(MeetingNotchTheme.dataFont)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Bu noktadan oynat")

                Spacer()

                if isHovering {
                    Image(systemName: "play")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }

            Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(MeetingNotchTheme.bodyFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .background(
            isHovering ? MeetingNotchTheme.surfaceHover : .clear,
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.controlRadius,
                style: .continuous
            )
        )
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
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
                decisions: ["Detay paneli 520 px genişliğe çıkarıldı."],
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
