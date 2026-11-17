@preconcurrency import AVFoundation
import SwiftUI

// MARK: - Playback

/// Plays a recording for the desktop sheet, with a speed control.
@MainActor
final class DesktopAudioPlayer: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1

    static let rates: [Float] = [1, 1.25, 1.5, 2]

    let duration: TimeInterval
    private let player: AVPlayer
    private var timeObserver: Any?

    init(url: URL, duration: TimeInterval) {
        self.duration = max(duration, 0.1)
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = min(max(time.seconds, 0), self.duration)
                if self.currentTime >= self.duration - 0.1 { self.isPlaying = false }
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    func pause() { player.pause(); isPlaying = false }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            if currentTime >= duration - 0.1 { seek(to: 0) }
            start()
        }
    }

    func play(from seconds: TimeInterval) {
        seek(to: seconds)
        start()
    }

    func seek(to seconds: TimeInterval) {
        let clamped = min(max(seconds, 0), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func nextRate() {
        let index = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(index + 1) % Self.rates.count]
        if isPlaying { player.rate = rate }
    }

    var rateLabel: String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(String(format: "%g", rate))×"
    }

    private func start() {
        player.play()
        player.rate = rate
        isPlaying = true
    }
}

// MARK: - Waveform

/// Peak levels of an audio file, read off the main thread.
enum DesktopWaveform {
    enum Failure: Error { case noAudio, unreadable }

    @MainActor private static var cache: [URL: [Double]] = [:]

    /// 0…1 peaks for the whole file, or `nil` when the audio can't be read.
    @MainActor
    static func peaks(for url: URL, buckets: Int = 240) async -> [Double]? {
        if let cached = cache[url] { return cached }
        let task = Task.detached(priority: .utility) { try? await read(url, buckets: buckets) }
        let peaks = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard let peaks else { return nil }
        if cache.count >= 12 { cache.removeAll() }
        cache[url] = peaks
        return peaks
    }

    static func read(_ url: URL, buckets: Int) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noAudio }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, buckets > 0 else { throw Failure.unreadable }
        let sampleRate = 8_000.0
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw Failure.unreadable }

        let total = max(1, Int(duration * sampleRate))
        var peaks = [Int16](repeating: 0, count: buckets)
        var position = 0
        var scratch = [Int16]()
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Int16>.size
            guard count > 0 else { continue }
            if scratch.count < count { scratch = [Int16](repeating: 0, count: count) }
            let status = scratch.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Int16>.size, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            scratch.withUnsafeBufferPointer { samples in
                for offset in 0..<count {
                    let bucket = min(buckets - 1, (position + offset) * buckets / total)
                    let sample = samples[offset]
                    let magnitude = sample == .min ? Int16.max : abs(sample)
                    if magnitude > peaks[bucket] { peaks[bucket] = magnitude }
                }
            }
            position += count
        }
        guard reader.status == .completed, position > 0 else { throw Failure.unreadable }
        let loudest = Double(peaks.max() ?? 0)
        guard loudest > 0 else { return [Double](repeating: 0, count: buckets) }
        // Square root lifts quiet speech so the shape of the call stays readable.
        return peaks.map { (Double($0) / loudest).squareRoot() }
    }

    /// Fits the stored peaks to the number of bars that fit the well.
    static func resample(_ peaks: [Double], to count: Int) -> [Double] {
        guard count > 0, !peaks.isEmpty else { return [] }
        return (0..<count).map { index in
            let start = index * peaks.count / count
            let end = max(start + 1, (index + 1) * peaks.count / count)
            return peaks[start..<min(end, peaks.count)].max() ?? 0
        }
    }
}

// MARK: - Detail

/// The meeting sheet (`tpl-ddetail`): title and chips, the player well, notes on the
/// left, and a rail with what you owe, who talked and where it came from.
struct DesktopMeetingDetail: View {
    let content: MeetingDetailContent
    let actions: DesktopActions
    let isProcessing: Bool
    let importedActionIDs: Set<UUID>
    let openSettings: (SettingsCategory) -> Void
    /// The stored meeting changed (a speaker was renamed); the page reloads it.
    let onChanged: () -> Void

    @StateObject private var player: DesktopAudioPlayer
    @State private var copied = false
    @State private var editingSpeakerID: String?
    @State private var editingSpeakerName = ""
    @State private var savingSpeaker = false
    @State private var message: String?
    @State private var messageFailed = false
    @State private var importing = Set<UUID>()
    @State private var hoveredSegment: AnyHashable?
    @FocusState private var speakerFieldFocused: Bool
    @Namespace private var transcriptSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let inlineSelectionLimit = 80

    init(content: MeetingDetailContent, actions: DesktopActions, isProcessing: Bool, importedActionIDs: Set<UUID>,
         openSettings: @escaping (SettingsCategory) -> Void, onChanged: @escaping () -> Void) {
        self.content = content
        self.actions = actions
        self.isProcessing = isProcessing
        self.importedActionIDs = importedActionIDs
        self.openSettings = openSettings
        self.onChanged = onChanged
        _player = StateObject(wrappedValue: DesktopAudioPlayer(url: content.audioURL, duration: content.meeting.duration))
    }

    private var meeting: StoredMeeting { content.meeting }
    private var stored: StoredTranscription? { content.storedTranscription }
    private var summary: MeetingSummary? { stored?.summary }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
            DesktopPlayerWell(player: player, audioURL: content.audioURL,
                              lane: stored.map { DesktopStats.lane($0.transcript, duration: meeting.duration) } ?? [])
                .padding(.horizontal, 28)
                .padding(.top, 20)
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    notes
                        .padding(.horizontal, -Hud.Row.inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .desktopEnter(0)
                    rail
                        .frame(width: Hud.Window.detailRailWidth)
                        .desktopEnter(1)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.never)
        }
        .onDisappear { player.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .desktopDidClose)) { _ in player.pause() }
        .sheet(isPresented: Binding(get: { editingSpeakerID != nil }, set: { if !$0 { editingSpeakerID = nil } })) { renameSheet }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
        .animation(reduceMotion ? nil : Hud.Motion.card, value: message)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: meeting.title).hud(.page).lineLimit(1).truncationMode(.tail)
                    .help(meeting.title)
                    .accessibilityAddTraits(.isHeader)
                DesktopFlow(spacing: 6) {
                    HudChip(dateChip, glyph: .calendar, style: .tag)
                    HudChip(DesktopFormat.minutes(meeting.duration), glyph: .clock, style: .tag)
                    if let source = meeting.sourceMeeting, let venue = DesktopFormat.venue(source) {
                        HudChip(venue, glyph: DesktopFormat.venueGlyph(source), style: .tag)
                    }
                    if let people = people {
                        HudChip(people, glyph: .people, style: .tag)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                moreMenu
                exportMenu
                HudButton(copied ? "Copied" : "Copy notes", glyph: .copy, key: "⇧⌘C", size: .small) {
                    guard let text = notesText else { return }
                    actions.copyText(text)
                    copied = true
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(notesText == nil)
            }
            .padding(.top, 2)
        }
    }

    private var dateChip: String {
        let day = Calendar.current.isDateInToday(meeting.startedAt) ? "Today"
            : (Calendar.current.isDateInYesterday(meeting.startedAt) ? "Yesterday" : DesktopFormat.format(meeting.startedAt, "EEE d MMM"))
        return "\(day) \(DesktopFormat.clock(meeting.startedAt))"
    }

    /// Who was invited, from the calendar ("Deniz, Ece, you"); else who spoke.
    private var people: String? {
        if let invited = meeting.sourceMeeting.flatMap({ MeetingPeopleFormatter.withYou($0.attendees) }) { return invited }
        return speakers.isEmpty ? nil : speakers.prefix(4).joined(separator: ", ")
    }

    private var speakers: [String] {
        var seen = Set<String>()
        return (stored?.transcript.segments ?? []).compactMap { segment in
            let name = DesktopFormat.speakerName(segment)
            return seen.insert(name).inserted ? name : nil
        }
    }

    private var notesText: String? {
        if let summary { return MeetingMarkdownFormatter.notes(summary) }
        if let markdown = content.markdown { return markdown }
        return stored.map { TranscriptTextFormatter.plainText($0.transcript) }
    }

    private var canRetry: Bool {
        meeting.processingStatus == .failed || meeting.processingStatus == .recorded
    }

    private var moreMenu: some View {
        Menu {
            if let stored {
                Button("Copy as text") { actions.copyText(TranscriptTextFormatter.plainText(stored.transcript)) }
            }
            if let markdown = content.markdown {
                Button("Save as Markdown") { actions.exportMarkdown(markdown, meeting) }
            }
            Button("Show audio in Finder") { actions.revealAudio(content.audioURL) }
            if canRetry {
                Button("Retry processing") { actions.retryProcessing(meeting) }
            }
            Divider()
            Button("Delete meeting", role: .destructive) { actions.deleteMeeting(meeting) }
        } label: {
            HudIcon(.more, size: 14)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HudButtonStyle(kind: .iconFramed, size: .small))
        .fixedSize()
        .help("More")
        .accessibilityLabel("More actions")
    }

    private var exportMenu: some View {
        Menu {
            if let markdown = content.markdown {
                Button("Markdown…") { actions.exportMarkdown(markdown, meeting) }
            }
            Divider()
            Button("Audio in Finder") { actions.revealAudio(content.audioURL) }
        } label: {
            HudButtonLabel("Export", glyph: .share, trailingGlyph: .chevronDown)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HudButtonStyle(kind: .secondary, size: .small))
        .fixedSize()
    }

    // MARK: Notes column

    @ViewBuilder private var notes: some View {
        if let stored {
            LazyVStack(alignment: .leading, spacing: 0) {
                summaryHeader(stored)
                if let failure = stored.summaryFailure {
                    HudActions {
                        HudStatusShape(.warn)
                        Text(verbatim: failure)
                    } buttons: {
                        HudButton("AI settings", size: .small) { openSettings(.ai) }
                    }
                    .padding(.horizontal, Hud.Row.inset)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                if let summary {
                    Text(verbatim: summary.overview.isEmpty ? "The transcript doesn’t have enough content to summarize." : summary.overview)
                        .hud(.read, summary.overview.isEmpty ? Hud.Ink.ink3 : Hud.Ink.ink1)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Hud.Row.inset)
                        .padding(.top, 4)
                    if !summary.decisions.isEmpty {
                        HudGroupHeader(title: "Decided").padding(.top, 16).accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(summary.decisions.enumerated()), id: \.offset) { offset, decision in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(verbatim: "\(offset + 1)").hud(.micro, Hud.Ink.ink3)
                                        .frame(width: 12, alignment: .leading).padding(.top, 5)
                                    Text(verbatim: decision).hud(.read)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.horizontal, Hud.Row.inset)
                    }
                } else if stored.summaryFailure == nil {
                    Text("The transcript is ready; notes will appear once a model is set.")
                        .hud(.read, Hud.Ink.ink3)
                        .padding(.horizontal, Hud.Row.inset)
                        .padding(.top, 4)
                }
                HudGroupHeader(title: "Transcript").padding(.top, 16).accessibilityAddTraits(.isHeader)
                transcript(stored.transcript)
            }
        } else {
            pendingRow
        }
    }

    private func summaryHeader(_ stored: StoredTranscription) -> some View {
        HStack(spacing: 8) {
            Text("Summary").hud(.label, Hud.Ink.ink3).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if isProcessing { HudBusy() }
            Button { actions.retryProcessing(meeting) } label: {
                HudButtonLabel(stored.summary == nil ? "Write notes" : "Rewrite", glyph: .spark)
            }
            .buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))
            .disabled(isProcessing || savingSpeaker)
            .help("Write the notes again")
        }
        .padding(.horizontal, Hud.Row.inset)
        .frame(height: 32)
    }

    @ViewBuilder private func transcript(_ transcript: Transcript) -> some View {
        if transcript.segments.isEmpty {
            Text(verbatim: transcript.text)
                .hud(.read)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Hud.Row.inset)
                .padding(.vertical, 8)
        } else {
            let selectable = transcript.segments.count <= Self.inlineSelectionLimit
            let order = speakerOrder(transcript)
            ForEach(transcript.segments) { segment in
                segmentRow(segment, speaker: order[segment.speakerID] ?? 0, selectable: selectable)
            }
        }
    }

    private func speakerOrder(_ transcript: Transcript) -> [String: Int] {
        var order: [String: Int] = [:]
        for segment in transcript.segments where order[segment.speakerID] == nil { order[segment.speakerID] = order.count }
        return order
    }

    private func segmentRow(_ segment: TranscriptSegment, speaker: Int, selectable: Bool) -> some View {
        let stamp = DesktopFormat.length(segment.startTime)
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .top, spacing: 12) {
            Button { player.play(from: segment.startTime) } label: {
                Text(verbatim: stamp).hud(.micro, Hud.Ink.ink3)
                    .frame(width: 36, alignment: .leading).padding(.top, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Play from here")
            .accessibilityLabel(Text(verbatim: "Play from \(stamp)"))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: DesktopFormat.speakerName(segment))
                    .hud(.label, speaker == 0 ? Hud.Ink.ink1 : (speaker == 1 ? Hud.Ink.ink2 : Hud.Ink.ink3))
                Group {
                    if selectable {
                        Text(verbatim: text).textSelection(.enabled)
                    } else {
                        Text(verbatim: text)
                    }
                }
                .hud(.read)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Hud.Row.inset)
        .padding(.vertical, 10)
        .hudGlide(segment.id, hovered: $hoveredSegment, in: transcriptSpace)
        .contextMenu {
            Button("Copy") { actions.copyText(text) }
            Button("Play from here") { player.play(from: segment.startTime) }
        }
    }

    /// No transcript yet: one row that says where the recording stands.
    private var pendingRow: some View {
        let status = isProcessing ? StoredMeeting.ProcessingStatus.processing : meeting.processingStatus
        return HudActions {
            switch status {
            case .failed: HudStatusShape(.err)
            case .recorded: HudStatusShape(.wait)
            case .processing: HudBusy()
            case .completed: HudStatusShape(.warn)
            }
            Text(verbatim: {
                switch status {
                case .failed: "Transcription didn’t finish"
                case .recorded: "Waiting to be transcribed"
                case .processing: "Preparing the transcript"
                case .completed: "Couldn’t read the transcript"
                }
            }()).hud(.body)
        } buttons: {
            if status == .failed || status == .completed || status == .recorded {
                HudButton(status == .recorded ? "Transcribe" : "Try again", size: .small) { actions.retryProcessing(meeting) }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Hud.Radius.console, style: .continuous).fill(Color(white: 1, opacity: 0.035)))
        .hudScanner(status == .processing, radius: Hud.Radius.console)
        .padding(.horizontal, Hud.Row.inset)
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let summary {
                forYou(summary.actionItems)
            }
            if let stored {
                let shares = DesktopStats.talkTime(stored.transcript)
                if !shares.isEmpty { talkTime(shares) }
            }
            details
        }
    }

    private func forYou(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("For you").hud(.label, Hud.Ink.ink3).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                HudSegmentDigits("\(items.count)", height: 11, color: items.isEmpty ? Hud.Ink.ink3 : Hud.Ink.signal)
            }
            .frame(height: 28)
            if items.isEmpty {
                Text("Nothing for you from this meeting.").hud(.meta)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in actionRow(item) }
            }
            if let message {
                HStack(spacing: 8) {
                    if messageFailed { HudStatusShape(.err) } else { HudLamp(.teal) }
                    Text(verbatim: message).hud(.meta, Hud.Ink.ink2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
    }

    private func actionRow(_ item: ActionItem) -> some View {
        let imported = importedActionIDs.contains(item.id)
        var meta: [String] = []
        if let due = item.dueDate { meta.append("by \(DesktopFormat.format(due, "EEE d"))") }
        if let time = item.sourceTime { meta.append(DesktopFormat.length(time)) }
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if let time = item.sourceTime { player.play(from: time) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.title).hud(.label, imported ? Hud.Ink.ink2 : Hud.Ink.ink1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(verbatim: meta.joined(separator: " · ")).hud(.meta)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.sourceTime == nil)
            .help(item.sourceTime == nil ? "" : "Play where this was said")
            if imported {
                HudStatusWord(.ok, "In Tasks").frame(height: 22)
            } else {
                Button {
                    importing.insert(item.id)
                    Task {
                        let result = await actions.analysis.importAction(content.id, item)
                        importing.remove(item.id)
                        if case .failed(let text) = result { show(text, failed: true) }
                    }
                } label: {
                    HudButtonLabel("Add", glyph: .plus)
                }
                .buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))
                .disabled(importing.contains(item.id) || isProcessing)
                .accessibilityLabel(Text(verbatim: "Add to tasks: \(item.title)"))
            }
        }
    }

    private func talkTime(_ shares: [DesktopStats.TalkShare]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Talk time").hud(.label, Hud.Ink.ink3).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Menu {
                    ForEach(shares.sorted { $0.index < $1.index }) { share in
                        Button(share.name) {
                            editingSpeakerName = stored?.transcript.segments.first { $0.speakerID == share.speakerID }?.speakerName ?? ""
                            editingSpeakerID = share.speakerID
                        }
                    }
                } label: {
                    Text("Rename")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(HudButtonStyle(kind: .ghost, size: .mini))
                .fixedSize()
                .disabled(isProcessing)
                .accessibilityLabel("Rename a speaker")
            }
            .frame(height: 28)
            ForEach(shares) { share in
                let ink = share.index == 0 ? Hud.Ink.ink1 : (share.index == 1 ? Hud.Ink.ink2 : Hud.Ink.ink3)
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: share.name).hud(.label, ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "\(DesktopFormat.minutes(share.seconds)) · \(Int((share.share * 100).rounded()))%").hud(.meta)
                    }
                    HudTrack(value: share.share, tint: share.index == 0 ? Hud.Ink.ink1 : (share.index == 1 ? Hud.Ink.ink2 : Hud.Ink.ink4),
                             glows: share.index == 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var details: some View {
        HudFrame("Details") {
            keyValue("Recorded from", meeting.sourceMeeting.flatMap(DesktopFormat.venue) ?? "This Mac")
            if let organizer = meeting.sourceMeeting?.organizer {
                keyValue("Invited by", organizer)
            }
            keyValue("Audio", audioText)
            if let stored {
                keyValue("Transcript", transcriptText(stored.transcript))
                keyValue("Notes", stored.summary.map { $0.model ?? "Ready" } ?? "None")
            } else {
                keyValue("Transcript", "None")
            }
        }
    }

    private func keyValue(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).hud(.meta)
            Spacer(minLength: 4)
            Text(verbatim: value).hud(.meta, Hud.Ink.ink2).lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 5)
    }

    private var audioText: String {
        let tracks = [meeting.microphoneFileName, meeting.systemAudioFileName].compactMap { $0 }.count
        var parts = [tracks > 1 ? "\(tracks) tracks" : "1 track"]
        if let bytes = (try? FileManager.default.attributesOfItem(atPath: content.audioURL.path))?[.size] as? Int64, bytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private func transcriptText(_ transcript: Transcript) -> String {
        let lines = transcript.segments.count
        let language = transcript.languageCode.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
        return [lines > 0 ? "\(lines) lines" : nil, language].compactMap { $0 }.joined(separator: " · ").ifEmpty("Ready")
    }

    private func show(_ text: String, failed: Bool) {
        message = text
        messageFailed = failed
    }

    // MARK: Rename speaker

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename speaker").hud(.title)
            TextField("", text: $editingSpeakerName, prompt: Text("Name").foregroundStyle(Hud.Ink.ink3))
                .textFieldStyle(.plain)
                .hud(.body)
                .focused($speakerFieldFocused)
                .hudField(height: 36, radius: 10, isFocused: speakerFieldFocused, padding: 10)
                .accessibilityLabel("Speaker name")
            HudActions {
                if savingSpeaker { HudBusy() }
                if let message, messageFailed { Text(verbatim: message) }
            } buttons: {
                HudButton("Cancel", key: "esc") { editingSpeakerID = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(savingSpeaker)
                HudButton("Save", key: "↩", kind: .primary) { saveSpeaker() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(savingSpeaker || isProcessing || editingSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { speakerFieldFocused = true }
    }

    private func saveSpeaker() {
        guard let speakerID = editingSpeakerID else { return }
        savingSpeaker = true
        Task {
            let result = await actions.analysis.renameSpeaker(content.id, speakerID, editingSpeakerName)
            savingSpeaker = false
            switch result {
            case .succeeded:
                message = nil
                editingSpeakerID = nil
                onChanged()
            case .failed(let text):
                show(text, failed: true)
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Player well

/// The player (`.well`, 78 pt): knob, segment time, the whole call as a waveform, who
/// spoke when as a lane under it, and the speed key. The only view that follows playback.
private struct DesktopPlayerWell: View {
    @ObservedObject var player: DesktopAudioPlayer
    let audioURL: URL
    let lane: [(share: Double, speaker: Int)]
    @State private var peaks: [Double]?
    @State private var scrubTime: TimeInterval?

    private var position: TimeInterval { scrubTime ?? player.currentTime }

    var body: some View {
        HStack(spacing: 16) {
            HudKnob(player.isPlaying ? .pause : .play, help: player.isPlaying ? "Pause" : "Play", action: player.togglePlayback)
            VStack(alignment: .leading, spacing: 6) {
                HudSegmentDigits(DesktopFormat.length(position), height: 14)
                Text(verbatim: "of \(DesktopFormat.length(player.duration))").hud(.micro)
            }
            .frame(width: player.duration >= 3_600 ? 76 : 58, alignment: .leading)
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let bars = max(8, Int(proxy.size.width / 3))
                    // Until the file is read (or if it can't be), the bars stay unlit ghosts.
                    HudWaveform(samples: peaks.map { DesktopWaveform.resample($0, to: bars) } ?? [Double](repeating: 0, count: bars),
                                progress: peaks == nil ? 0 : position / player.duration, headOverhang: (4, 4)) { fraction in
                        scrubTime = fraction * player.duration
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in
                        if let scrubTime { player.seek(to: scrubTime) }
                        scrubTime = nil
                    })
                    .opacity(peaks == nil ? 0.5 : 1)
                }
                .frame(height: 28)
                if lane.isEmpty {
                    Capsule().fill(Hud.Ink.track).frame(height: 3)
                } else {
                    HudLane(segments: lane)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(Text(verbatim: DesktopFormat.length(position)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: player.seek(to: min(player.duration, player.currentTime + 5))
                case .decrement: player.seek(to: max(0, player.currentTime - 5))
                @unknown default: break
                }
            }
            Button(action: player.nextRate) { Text(verbatim: player.rateLabel) }
                .buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))
                .help("Playback speed")
                .accessibilityLabel(Text(verbatim: "Playback speed \(player.rateLabel)"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 78)
        .hudWell()
        .task(id: audioURL) { peaks = await DesktopWaveform.peaks(for: audioURL) }
    }
}
