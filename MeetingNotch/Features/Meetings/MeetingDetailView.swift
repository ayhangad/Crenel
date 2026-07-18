@preconcurrency import AVFoundation
import AppKit
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
            guard let self else { return }
            self.currentTime = min(max(time.seconds, 0), self.duration)
            if self.currentTime >= self.duration - 0.1 {
                self.isPlaying = false
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

struct MeetingDetailView: View {
    let meeting: StoredMeeting
    let storedTranscription: StoredTranscription?
    let markdown: String?
    let audioURL: URL
    let onCopyTranscript: (String) -> Void
    let onExportMarkdown: (String) -> Void
    let onRevealAudio: (URL) -> Void
    let onRetry: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void

    @StateObject private var player: MeetingAudioPlayer
    @State private var showsDeleteConfirmation = false

    init(
        meeting: StoredMeeting,
        storedTranscription: StoredTranscription?,
        markdown: String? = nil,
        audioURL: URL,
        onCopyTranscript: @escaping (String) -> Void,
        onExportMarkdown: @escaping (String) -> Void = { _ in },
        onRevealAudio: @escaping (URL) -> Void,
        onRetry: @escaping (StoredMeeting) -> Void,
        onDelete: @escaping (StoredMeeting) -> Void
    ) {
        self.meeting = meeting
        self.storedTranscription = storedTranscription
        self.markdown = markdown
        self.audioURL = audioURL
        self.onCopyTranscript = onCopyTranscript
        self.onExportMarkdown = onExportMarkdown
        self.onRevealAudio = onRevealAudio
        self.onRetry = onRetry
        self.onDelete = onDelete
        _player = StateObject(
            wrappedValue: MeetingAudioPlayer(url: audioURL, duration: meeting.duration)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    AudioPlayerCard(player: player)

                    if let storedTranscription {
                        if let summary = storedTranscription.summary {
                            summarySection(summary)
                        }
                        transcriptSection(storedTranscription.transcript)
                    } else {
                        processingState
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 680, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Toplantı silinsin mi?", isPresented: $showsDeleteConfirmation) {
            Button("Sil", role: .destructive) { onDelete(meeting) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("“\(meeting.title)” kaydı, ses dosyası ve transkripti kalıcı olarak silinecek.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(meeting.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text("\(meeting.startedAt.formatted(date: .long, time: .shortened)) · \(TranscriptTextFormatter.timestamp(meeting.duration))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let storedTranscription {
                Menu {
                    Button("Düz Metni Kopyala", systemImage: "doc.on.doc") {
                        onCopyTranscript(TranscriptTextFormatter.plainText(storedTranscription.transcript))
                    }
                    if let markdown {
                        Button("Markdown Kopyala", systemImage: "text.document") {
                            onCopyTranscript(markdown)
                        }
                        Button("Markdown Dosyası Kaydet…", systemImage: "square.and.arrow.down") {
                            onExportMarkdown(markdown)
                        }
                    }
                } label: {
                    Label("Kopyala / Dışa Aktar", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                onRevealAudio(audioURL)
            } label: {
                Label("Sesi Göster", systemImage: "folder")
            }

            if meeting.processingStatus == .failed || meeting.processingStatus == .recorded {
                Button {
                    onRetry(meeting)
                } label: {
                    Label("Tekrar Dene", systemImage: "arrow.clockwise")
                }
            }

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .help("Toplantıyı sil")
            .accessibilityLabel("Toplantıyı sil")
        }
        .buttonStyle(.bordered)
        .padding(20)
    }

    private func summarySection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Toplantı Notları", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button("Notları Kopyala", systemImage: "doc.on.doc") {
                    onCopyTranscript(MeetingMarkdownFormatter.notes(summary))
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Kısa Özet")
                    .font(.subheadline.weight(.semibold))
                Text(summary.overview.isEmpty
                    ? "Transkript özetlenecek yeterli içerik taşımıyor."
                    : summary.overview)
                    .textSelection(.enabled)
            }

            SummaryList(
                title: "Kararlar",
                emptyText: "Açıkça belirtilmiş karar bulunamadı.",
                values: summary.decisions
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("Aksiyon Maddeleri")
                    .font(.subheadline.weight(.semibold))
                if summary.actionItems.isEmpty {
                    Text("Açıkça belirtilmiş aksiyon maddesi bulunamadı.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.actionItems) { action in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.title)
                                    .textSelection(.enabled)
                                if let detail = actionDetail(action) {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionDetail(_ action: ActionItem) -> String? {
        var details: [String] = []
        if let assignee = action.assignee { details.append("Sorumlu: \(assignee)") }
        if let dueDate = action.dueDate {
            details.append("Tarih: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    @ViewBuilder
    private func transcriptSection(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Transkript", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text("\(transcript.segments.count) segment")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if transcript.segments.isEmpty {
                Text(transcript.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(transcript.segments) { segment in
                        TranscriptSegmentRow(segment: segment) {
                            player.seek(to: segment.startTime)
                        }
                    }
                }
            }
        }
    }

    private var processingState: some View {
        VStack(spacing: 12) {
            Image(systemName: processingIcon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(processingColor)
            Text(processingTitle)
                .font(.headline)
            Text(processingDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private var processingIcon: String {
        switch meeting.processingStatus {
        case .failed: "exclamationmark.triangle"
        case .recorded: "clock"
        case .processing: "waveform.badge.magnifyingglass"
        case .completed: "text.badge.xmark"
        }
    }

    private var processingColor: Color {
        meeting.processingStatus == .failed ? .orange : .accentColor
    }

    private var processingTitle: String {
        switch meeting.processingStatus {
        case .failed: "Transkripsiyon tamamlanamadı"
        case .recorded: "Transkripsiyon kuyruğa alınacak"
        case .processing: "Transkripsiyon hazırlanıyor"
        case .completed: "Transkript okunamadı"
        }
    }

    private var processingDetail: String {
        switch meeting.processingStatus {
        case .failed: "Ses kaydınız korunuyor. Üstteki Tekrar Dene düğmesiyle işlemi yeniden başlatabilirsiniz."
        case .recorded, .processing: "Bu pencereyi kapatabilirsiniz; işleme arka planda devam eder."
        case .completed: "Ses kaydı korunuyor. Transkript dosyası için işlemeyi yeniden deneyebilirsiniz."
        }
    }
}

private struct SummaryList: View {
    let title: String
    let emptyText: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if values.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(.secondary)
                        Text(value)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct AudioPlayerCard: View {
    @ObservedObject var player: MeetingAudioPlayer

    var body: some View {
        HStack(spacing: 14) {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(player.isPlaying ? "Sesi duraklat" : "Sesi oynat")

            Text(TranscriptTextFormatter.timestamp(player.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...player.duration
            )
            .accessibilityLabel("Kayıt konumu")

            Text(TranscriptTextFormatter.timestamp(player.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let onSeek: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displaySpeakerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Button(action: onSeek) {
                    Text(TranscriptTextFormatter.timestamp(segment.startTime))
                        .font(.caption2.monospacedDigit().weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Bu noktadan oynat")
            }
            .frame(width: 92, alignment: .leading)

            Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .contain)
    }

    private var displaySpeakerName: String {
        let name = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 }
            ?? TranscriptTextFormatter.fallbackSpeakerName(segment.speakerID)
    }
}
