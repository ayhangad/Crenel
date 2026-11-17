import Accelerate
@preconcurrency import AVFoundation
import os
import SwiftUI

// MARK: - Peaks

/// Real waveform peaks for a meeting's audio file: the file is decoded once, off the main
/// thread, folded into `bars` peak values (0…1) and kept in memory.
///
///     let peaks = await MeetingWaveformPeaks.shared.peaks(for: audioURL)      // nil when unreadable
///     let ready = MeetingWaveformPeaks.shared.cached(for: audioURL)           // sync, memory only
final class MeetingWaveformPeaks: Sendable {
    static let shared = MeetingWaveformPeaks()
    /// The prototype draws 110 bars across the player.
    static let defaultBars = 110

    private struct State {
        var entries: [String: [Double]] = [:]
        var order: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let capacity = 24

    /// Peaks already in memory, if any. Never touches the disk beyond a file stat.
    func cached(for url: URL, bars: Int = MeetingWaveformPeaks.defaultBars) -> [Double]? {
        guard let key = Self.key(url, bars: bars) else { return nil }
        return state.withLock { $0.entries[key] }
    }

    /// Decodes the file on a background task. Failures are not cached: a recording that
    /// is still being written can be read later.
    func peaks(for url: URL, bars: Int = MeetingWaveformPeaks.defaultBars) async -> [Double]? {
        guard let key = Self.key(url, bars: bars) else { return nil }
        if let hit = state.withLock({ $0.entries[key] }) { return hit }
        let result = await Task.detached(priority: .utility) {
            await Self.decode(url: url, bars: bars)
        }.value
        guard let result else { return nil }
        let capacity = capacity
        state.withLock { state in
            if state.entries[key] == nil { state.order.append(key) }
            state.entries[key] = result
            while state.order.count > capacity {
                state.entries[state.order.removeFirst()] = nil
            }
        }
        return result
    }

    /// Path, size and modification date: a re-recorded or replaced file gets new peaks.
    private static func key(_ url: URL, bars: Int) -> String? {
        guard url.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        guard size > 0 else { return nil }
        return "\(url.path)|\(size)|\(modified)|\(bars)"
    }

    /// Reads the first audio track as 32-bit float PCM and keeps the largest magnitude in
    /// each of `bars` equal slices of the file.
    static func decode(url: URL, bars: Int) async -> [Double]? {
        guard bars > 0 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let timeRange = try? await track.load(.timeRange),
              let formats = try? await track.load(.formatDescriptions),
              let format = formats.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              let reader = try? AVAssetReader(asset: asset) else { return nil }

        let sampleRate = basic.mSampleRate
        let totalFrames = timeRange.duration.seconds * sampleRate
        guard sampleRate > 0, totalFrames.isFinite, totalFrames >= 1 else { return nil }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var peaks = [Float](repeating: 0, count: bars)
        var frame = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            guard let block = CMSampleBufferGetDataBuffer(buffer),
                  let description = CMSampleBufferGetFormatDescription(buffer),
                  let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { continue }
            let channels = max(1, Int(stream.mChannelsPerFrame))
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            let frames = data.count / channels
            var offset = 0
            data.withUnsafeBufferPointer { samples in
                while offset < frames {
                    let bar = min(bars - 1, Int((frame + Double(offset)) / totalFrames * Double(bars)))
                    // Frames left in this bar's slice of the file.
                    let barEnd = (Double(bar + 1) * totalFrames / Double(bars)).rounded(.up)
                    let run = bar == bars - 1 ? frames - offset : max(1, min(frames - offset, Int(barEnd - frame) - offset))
                    var magnitude: Float = 0
                    vDSP_maxmgv(samples.baseAddress! + offset * channels, 1, &magnitude, vDSP_Length(run * channels))
                    if magnitude > peaks[bar] { peaks[bar] = magnitude }
                    offset += run
                }
            }
            frame += Double(frames)
        }
        guard reader.status == .completed, frame > 0 else { return nil }
        return normalised(peaks)
    }

    /// Scales against the loud end of the recording (95th percentile), so one click does
    /// not flatten an hour of speech.
    static func normalised(_ peaks: [Float]) -> [Double] {
        let sorted = peaks.sorted()
        guard let loudest = sorted.last, loudest > 0 else { return peaks.map { _ in 0 } }
        let reference = max(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], loudest * 0.25)
        return peaks.map { min(1, Double($0 / reference)) }
    }
}

// MARK: - Views

/// The whole meeting as bars. With peaks it is `HudWaveform`; while they load, or when the
/// audio cannot be read, the bars rest as unlit ghosts — nothing is invented.
///
///     MeetingWaveformView(peaks: peaks, progress: 0.25) { fraction in player.seek(to: fraction * duration) }
///     MeetingWaveformView(peaks: nil, progress: 0)                               // ghost
///     MeetingWaveformView(peaks: peaks, progress: p, headOverhang: (4, 4))       // desktop player
struct MeetingWaveformView: View {
    let peaks: [Double]?
    var progress: Double
    var headOverhang: (top: CGFloat, bottom: CGFloat) = (2, 9)
    var height: CGFloat = 28
    var onScrub: ((Double) -> Void)?

    init(peaks: [Double]?, progress: Double, headOverhang: (top: CGFloat, bottom: CGFloat) = (2, 9),
         height: CGFloat = 28, onScrub: ((Double) -> Void)? = nil) {
        self.peaks = peaks
        self.progress = progress
        self.headOverhang = headOverhang
        self.height = height
        self.onScrub = onScrub
    }

    var body: some View {
        if let peaks, !peaks.isEmpty {
            HudWaveform(samples: peaks, progress: progress, headOverhang: headOverhang, height: height, onScrub: onScrub)
        } else {
            ghost
        }
    }

    /// Unlit bars at their resting height; the needle and seeking still work.
    private var ghost: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in
                let count = MeetingWaveformPeaks.defaultBars
                let gap: CGFloat = 2
                let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                var bars = Path()
                for index in 0..<count {
                    bars.addRoundedRect(
                        in: CGRect(x: CGFloat(index) * (barWidth + gap), y: (size.height - 3) / 2, width: barWidth, height: 3),
                        cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                    )
                }
                context.fill(bars, with: .color(Color(white: 1, opacity: 0.09)))
            }
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Hud.Ink.signal)
                    .frame(width: 1, height: size.height + headOverhang.top + headOverhang.bottom)
                    .shadow(color: Hud.Ink.signal.opacity(0.8), radius: 3)
                    .offset(x: size.width * min(1, max(0, progress)), y: -headOverhang.top)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    guard size.width > 0 else { return }
                    onScrub?(min(1, max(0, value.location.x / size.width)))
                },
                including: onScrub == nil ? .none : .all
            )
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The waveform wired to a player: loads the file's peaks, follows playback, seeks on
/// click or drag. Reusable in any player layout (notch and desktop).
///
///     MeetingWaveformScrubber(player: player, audioURL: content.audioURL)
///     MeetingWaveformScrubber(player: player, audioURL: url, headOverhang: (4, 4))   // desktop
struct MeetingWaveformScrubber: View {
    @ObservedObject var player: MeetingAudioPlayer
    let audioURL: URL
    var headOverhang: (top: CGFloat, bottom: CGFloat) = (2, 9)
    var height: CGFloat = 28
    @State private var peaks: [Double]?

    init(player: MeetingAudioPlayer, audioURL: URL, headOverhang: (top: CGFloat, bottom: CGFloat) = (2, 9), height: CGFloat = 28) {
        self.player = player
        self.audioURL = audioURL
        self.headOverhang = headOverhang
        self.height = height
        _peaks = State(initialValue: MeetingWaveformPeaks.shared.cached(for: audioURL))
    }

    var body: some View {
        MeetingWaveformView(
            peaks: peaks,
            progress: player.duration > 0 ? player.currentTime / player.duration : 0,
            headOverhang: headOverhang,
            height: height
        ) { fraction in
            player.seek(to: fraction * player.duration)
        }
        .task(id: audioURL) {
            guard peaks == nil else { return }
            peaks = await MeetingWaveformPeaks.shared.peaks(for: audioURL)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(TranscriptTextFormatter.timestamp(player.currentTime)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(to: player.currentTime + 5)
            case .decrement: player.seek(to: player.currentTime - 5)
            @unknown default: break
            }
        }
    }
}
