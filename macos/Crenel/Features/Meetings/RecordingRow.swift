@preconcurrency import AVFoundation
import SwiftUI

// MARK: - Preview data

/// What a Recordings row shows beyond the stored meeting: the first line of the notes,
/// how many action items they hold, and where the audio is (for the waveform and Play).
struct RecordingPreview: Equatable, Sendable {
    var overview: String?
    var actionCount: Int?
    var audioURL: URL?
}

/// Loads a row's preview. The app reads it from the meeting repository; galleries and
/// tests pass fixed values, and without a loader rows show only what the meeting knows.
struct RecordingPreviewLoader: Sendable {
    let load: @Sendable (StoredMeeting) async -> RecordingPreview?
}

private struct RecordingPreviewLoaderKey: EnvironmentKey {
    static let defaultValue: RecordingPreviewLoader? = nil
}

extension EnvironmentValues {
    var recordingPreviewLoader: RecordingPreviewLoader? {
        get { self[RecordingPreviewLoaderKey.self] }
        set { self[RecordingPreviewLoaderKey.self] = newValue }
    }
}

/// Previews already read, keyed by meeting and processing state, so reopening the panel
/// does not decode every transcript again; a reprocessed meeting gets a fresh entry.
actor RecordingPreviewCache {
    static let shared = RecordingPreviewCache()
    private var entries: [String: RecordingPreview] = [:]

    func preview(for meeting: StoredMeeting, load: () async -> RecordingPreview?) async -> RecordingPreview? {
        let key = "\(meeting.id)|\(meeting.processingStatus.rawValue)|\(meeting.summaryNeedsAttention == true)"
        if let hit = entries[key] { return hit }
        guard let value = await load() else { return nil }
        entries[key] = value
        return value
    }
}

extension RecordingPreview {
    /// The notes' overview, cut to its first sentence-ish line.
    static func firstLine(_ overview: String?) -> String? {
        guard let text = overview?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }
}

// MARK: - Inline playback

/// One recording plays at a time from the list, without opening it.
@MainActor
final class RecordingInlinePlayback: ObservableObject {
    @Published private(set) var playingID: UUID?
    @Published private(set) var progress: Double = 0

    private var player: AVPlayer?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(_ id: UUID, url: URL, duration: TimeInterval) {
        if playingID == id {
            stop()
            return
        }
        stop()
        let player = AVPlayer(url: url)
        let length = max(duration, 0.1)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.progress = min(1, max(0, time.seconds / length)) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        self.player = player
        playingID = id
        progress = 0
        player.play()
    }

    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil
        endObserver = nil
        player = nil
        playingID = nil
        progress = 0
    }
}

// MARK: - Date tile

/// The day a recording was made (`HudDateTile` with the month). A corner lamp appears
/// only when the recording needs something: notes want a look (amber), failed (red),
/// processing (blinking amber) or not transcribed yet (dim). Ready recordings stay quiet.
struct RecordingDateTile: View {
    let date: Date
    let attention: RecordingAttention

    static let width = HudDateTile.width

    var body: some View {
        HudDateTile(date: date, caption: .month, lamp: lamp.color, lampLoop: lamp.loop)
    }

    private var lamp: (color: Hud.LampColor?, loop: HudLoop) {
        switch attention {
        case .none: (nil, .steady)
        case .noNotes: (.amber, .steady)
        case .failed: (.red, .steady)
        case .processing: (.amber, .blink)
        case .notTranscribed: (.dim, .steady)
        }
    }
}

// MARK: - Mini waveform

/// A short row of bars that reads as a recording. It is drawn, not decoded: the shape is
/// a speech-like pattern seeded by the meeting, so every row has its own and nothing
/// waits on the audio file. The played part lights up while it plays inline.
struct RecordingMiniWaveform: View {
    let peaks: [Double]
    var progress: Double = 0

    init(seed: UUID, progress: Double = 0) {
        peaks = Self.pattern(seed: seed)
        self.progress = progress
    }

    /// Bursts and pauses like speech, from a seed: same meeting, same bars.
    static func pattern(seed: UUID, bars: Int = bars) -> [Double] {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        withUnsafeBytes(of: seed.uuid) { bytes in
            for byte in bytes { value = (value ^ UInt64(byte)) &* 0x100_0000_01B3 }
        }
        func next() -> Double {
            value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(value >> 11) / Double(1 << 53)
        }
        var envelope = 0.5
        return (0..<bars).map { index in
            if index % 5 == 0 { envelope = 0.25 + 0.75 * next() }
            return min(1, max(0.08, envelope * (0.45 + 0.55 * next())))
        }
    }

    static let bars = 34
    static let size = CGSize(width: 102, height: 18)

    var body: some View {
        Canvas { context, size in
            let count = Self.bars
            let gap: CGFloat = 1
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            var played = Path(), rest = Path()
            for index in 0..<count {
                let sample = peaks.indices.contains(index) ? peaks[index] : 0
                let height = max(3, min(size.height, 3 + CGFloat(sample) * (size.height - 3)))
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                let bar = Path(roundedRect: rect, cornerRadius: width / 2)
                if progress > 0, Double(index) / Double(count) < progress { played.addPath(bar) } else { rest.addPath(bar) }
            }
            context.fill(rest, with: .color(Hud.Ink.ink4))
            context.fill(played, with: .color(Hud.Ink.ink1))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Row

/// One recording: the date tile, then title · when, where and what came of it · the
/// first line of the notes, and the length over the waveform at the trailing edge. On
/// hover Play and Open take the waveform's place; while it plays inline the waveform
/// lights up as it goes.
struct RecordingRow: View {
    let meeting: StoredMeeting
    let isHovered: Bool
    @ObservedObject var playback: RecordingInlinePlayback
    let onOpen: () -> Void

    @Environment(\.recordingPreviewLoader) private var loader
    @State private var preview: RecordingPreview?

    /// Vertical padding inside the row; the list adds `RecordingRow.spacing` between rows
    /// so hover slabs never touch.
    static let verticalPadding: CGFloat = 7
    static let spacing: CGFloat = 4
    static let trailingWidth: CGFloat = 140

    var body: some View {
        let attention = RecordingAttention(meeting)
        let isPlaying = playback.playingID == meeting.id
        let isHovered = isHovered
        HStack(alignment: .top, spacing: Hud.Row.gap) {
            RecordingDateTile(date: meeting.startedAt, attention: attention)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).hud(.body).lineLimit(1)
                metaLine(attention)
                if let gist = RecordingPreview.firstLine(preview?.overview) {
                    Text(gist).hud(.meta, Hud.Ink.ink4).lineLimit(1).padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(verbatim: RecordingsFormat.length(meeting.duration))
                    .hud(.meta, Hud.Ink.ink2)
                    .monospacedDigit()
                    .fixedSize()
                ZStack(alignment: .trailing) {
                    RecordingMiniWaveform(seed: meeting.id, progress: isPlaying ? playback.progress : 0)
                        .opacity(isHovered ? 0 : 1)
                    if isHovered {
                        buttons(isPlaying: isPlaying)
                            .transition(.opacity)
                    }
                }
                .frame(height: RecordingMiniWaveform.size.height)
            }
            // Wide enough for Play and Open, so hovering never moves the text.
            .frame(width: Self.trailingWidth, alignment: .trailing)
        }
        // The tile stretches to the text's height; the row keeps its natural height.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Hud.Row.inset)
        .padding(.vertical, Self.verticalPadding)
        .contentShape(Rectangle())
        .task(id: "\(meeting.id)|\(meeting.processingStatus.rawValue)") { await load() }
    }

    @ViewBuilder
    private func metaLine(_ attention: RecordingAttention) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: HudFormat.clock(meeting.startedAt)).monospacedDigit()
            if let venue = meeting.sourceMeeting.flatMap(NotchClosedText.venue) {
                dot
                Text(verbatim: venue)
            }
            if let word = attention.word {
                dot
                HStack(spacing: 5) {
                    attention.shape.scaleEffect(0.8)
                    Text(word).foregroundStyle(attention == .noNotes ? Hud.Ink.signal : Hud.Ink.ink2)
                }
            } else if let count = preview?.actionCount, count > 0 {
                dot
                Text(count == 1 ? String(localized: "1 action") : String(localized: "\(count) actions"))
                    .foregroundStyle(Hud.Ink.ink2)
            }
        }
        .hud(.meta)
        .lineLimit(1)
    }

    private var dot: some View {
        Text(verbatim: "·").foregroundStyle(Hud.Ink.ink5)
    }

    private func buttons(isPlaying: Bool) -> some View {
        HStack(spacing: 6) {
            if let url = preview?.audioURL {
                HudButton(isPlaying ? "Pause" : "Play", glyph: isPlaying ? .pause : .play, size: .mini) {
                    playback.toggle(meeting.id, url: url, duration: meeting.duration)
                }
            }
            HudButton("Open", key: "↩", kind: .primary, size: .mini, action: onOpen)
        }
        .fixedSize()
    }

    private func load() async {
        guard let loader else { return }
        let meeting = meeting
        let loaded = await RecordingPreviewCache.shared.preview(for: meeting) { await loader.load(meeting) }
        preview = loaded
    }
}
