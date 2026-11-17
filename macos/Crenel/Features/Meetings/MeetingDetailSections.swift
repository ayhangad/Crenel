import SwiftUI

// Building blocks of the meeting detail (`tpl-detail-body`). The notch composes them in
// `MeetingDetailView`; the desktop window lays the same pieces out differently.
// Every block carries its own 10 pt row inset, so it sits directly in a panel whose
// content inset is `Hud.Notch.openInset`.

// MARK: - Talk time

/// Who spoke for how long, from the transcript's segments. Speakers are ordered by
/// talk time; `share` values add up to 1.
struct MeetingTalkTime: Equatable {
    struct Speaker: Equatable, Identifiable {
        let id: String
        /// The stored name, or "Speaker N".
        let name: String
        /// The stored name only (nil when the speaker is unnamed).
        let storedName: String?
        let seconds: TimeInterval
        let share: Double
    }

    let speakers: [Speaker]

    init(transcript: Transcript) {
        var seconds: [String: TimeInterval] = [:]
        var names: [String: String] = [:]
        var order: [String] = []
        for segment in transcript.segments {
            if seconds[segment.speakerID] == nil { order.append(segment.speakerID) }
            seconds[segment.speakerID, default: 0] += max(0, segment.endTime - segment.startTime)
            if names[segment.speakerID] == nil,
               let name = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                names[segment.speakerID] = name
            }
        }
        let total = seconds.values.reduce(0, +)
        speakers = order
            .map { id in
                Speaker(id: id, name: names[id] ?? TranscriptTextFormatter.fallbackSpeakerName(id), storedName: names[id],
                        seconds: seconds[id] ?? 0, share: total > 0 ? (seconds[id] ?? 0) / total : 1 / Double(order.count))
            }
            .sorted { lhs, rhs in
                lhs.seconds != rhs.seconds ? lhs.seconds > rhs.seconds : (order.firstIndex(of: lhs.id) ?? 0) < (order.firstIndex(of: rhs.id) ?? 0)
            }
    }
}

/// The talk-time bar with its legend (notch). The legend is one button: it opens the
/// speakers menu ("Rename", then each speaker) when `onRename` is set.
///
///     MeetingTalkTimeBar(talk: MeetingTalkTime(transcript: transcript)) { speaker in rename(speaker) }
struct MeetingTalkTimeBar: View {
    let talk: MeetingTalkTime
    var isDisabled = false
    var onRename: ((MeetingTalkTime.Speaker) -> Void)?
    @State private var isHovering = false

    /// The legend names at most this many speakers; the bar still shows everyone.
    private static let legendLimit = 4

    init(talk: MeetingTalkTime, isDisabled: Bool = false, onRename: ((MeetingTalkTime.Speaker) -> Void)? = nil) {
        self.talk = talk
        self.isDisabled = isDisabled
        self.onRename = onRename
    }

    var body: some View {
        HStack(spacing: 12) {
            HudTalkBar(shares: talk.speakers.map(\.share))
                .frame(maxWidth: .infinity)
            if let onRename {
                Menu {
                    Section("Rename") {
                        ForEach(talk.speakers) { speaker in
                            Button(speaker.name) { onRename(speaker) }
                        }
                    }
                } label: {
                    legend
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(isDisabled)
                .onHover { isHovering = $0 }
                .help("Rename a speaker")
                .accessibilityLabel("Speakers")
            } else {
                legend
            }
        }
        .padding(.horizontal, Hud.Row.inset)
        .animation(Hud.Motion.hover, value: isHovering)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(Array(talk.speakers.prefix(Self.legendLimit).enumerated()), id: \.element.id) { index, speaker in
                HStack(spacing: 6) {
                    HudSpeakerDot(index: index)
                    Text(speaker.name).hud(.meta, isHovering ? Hud.Ink.ink2 : Hud.Ink.ink3).lineLimit(1)
                }
            }
            if talk.speakers.count > Self.legendLimit {
                Text(verbatim: "+\(talk.speakers.count - Self.legendLimit)").hud(.meta, isHovering ? Hud.Ink.ink2 : Hud.Ink.ink3)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Header

/// Title and one meta line: when · how long · who.
///
///     MeetingDetailHeader(meeting: meeting, transcript: stored?.transcript)
struct MeetingDetailHeader: View {
    let meeting: StoredMeeting
    var transcript: Transcript?
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).hud(.hero).lineLimit(2).help(meeting.title)
            Text(Self.meta(meeting: meeting, transcript: transcript, now: now)).hud(.meta).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Hud.Row.inset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    static func meta(meeting: StoredMeeting, transcript: Transcript?, now: Date) -> String {
        var parts = [
            "\(RecordingsFormat.day(meeting.startedAt, now: now)) \(HudFormat.clock(meeting.startedAt))",
            duration(meeting.duration)
        ]
        if let transcript {
            let names = MeetingTalkTime(transcript: transcript).speakers.compactMap(\.storedName)
            if !names.isEmpty {
                let shown = names.prefix(3).joined(separator: ", ")
                parts.append(names.count > 3 ? "\(shown) +\(names.count - 3)" : shown)
            }
        }
        return parts.joined(separator: " · ")
    }

    static func duration(_ interval: TimeInterval) -> String {
        interval >= 60
            ? String(localized: "\(Int((interval / 60).rounded())) min")
            : String(localized: "\(max(0, Int(interval))) s")
    }
}

// MARK: - Player

/// The notch player: a small knob with the time under it, the whole meeting as a
/// waveform with an amber needle, and the tuner scale (one tick a minute) below.
///
///     MeetingPlayerView(player: player, audioURL: content.audioURL)
struct MeetingPlayerView: View {
    @ObservedObject var player: MeetingAudioPlayer
    let audioURL: URL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                HudKnob(player.isPlaying ? .pause : .play, small: true, help: player.isPlaying ? "Pause" : "Play",
                        action: player.togglePlayback)
                Text(TranscriptTextFormatter.timestamp(player.currentTime))
                    .hud(.micro, Hud.Ink.ink2)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 32)
            VStack(spacing: 4) {
                MeetingWaveformScrubber(player: player, audioURL: audioURL)
                HudTunerScale(minutes: Int((player.duration / 60).rounded()))
            }
            .padding(.top, 2)
        }
        .padding(.leading, 4)
        .padding(.trailing, Hud.Row.inset)
    }
}

// MARK: - Section header

/// A group header with something on its right edge, centred on a 32 pt line
/// (`.group-h !h-8`): "Summary" + Rewrite.
struct MeetingSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).hud(.label, Hud.Ink.ink3)
            if let count {
                Text(verbatim: "\(count)").hud(.label, Hud.Ink.ink4)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .lineLimit(1)
        .padding(.horizontal, Hud.Row.inset)
        .frame(height: 32)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Summary

/// "Summary" with Rewrite (xs) on its right, then the overview.
///
///     MeetingSummarySection(overview: summary.overview, isRewriting: isProcessing) { rewrite() }
///     MeetingSummarySection(overview: nil, placeholder: "The transcript is ready; …")   // no notes yet
struct MeetingSummarySection: View {
    /// nil: there are no notes; `placeholder` is printed dim instead.
    let overview: String?
    var placeholder: String = String(localized: "The transcript is ready; notes will appear once a model is set.")
    var isRewriting = false
    var isDisabled = false
    /// nil hides Rewrite.
    var onRewrite: (() -> Void)?

    init(overview: String?, placeholder: String? = nil, isRewriting: Bool = false, isDisabled: Bool = false,
         onRewrite: (() -> Void)? = nil) {
        self.overview = overview
        if let placeholder { self.placeholder = placeholder }
        self.isRewriting = isRewriting
        self.isDisabled = isDisabled
        self.onRewrite = onRewrite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetingSectionHeader(title: "Summary") {
                if isRewriting {
                    HStack(spacing: 8) {
                        HudBusy()
                        Text("Writing new notes…").hud(.meta, Hud.Ink.ink2)
                    }
                    .transition(.opacity)
                } else if let onRewrite {
                    Button(action: onRewrite) { HudButtonLabel("Rewrite", glyph: .spark) }
                        .buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))
                        .disabled(isDisabled)
                        .help("Write the notes again")
                        .transition(.opacity)
                }
            }
            .animation(Hud.Motion.hover, value: isRewriting)

            if let overview {
                let isEmpty = overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text(isEmpty ? String(localized: "The transcript doesn’t have enough content to summarize.") : overview)
                    .hud(.read, isEmpty ? Hud.Ink.ink3 : Hud.Ink.ink1)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Hud.Row.inset)
                    .padding(.top, 6)
            } else {
                Text(placeholder)
                    .hud(.read, Hud.Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Hud.Row.inset)
                    .padding(.top, 2)
            }
        }
    }
}

/// The transcript is there, the notes are not (`o-detail-summaryfailed`): a diamond, the
/// reason on one line, and the way to the AI settings.
///
///     MeetingNotesMissingConsole(failure: stored.summaryFailure)
struct MeetingNotesMissingConsole: View {
    /// The stored reason, if the summary failed; nil when no model has written notes.
    let failure: String?
    /// Writes the notes again with the current model; nil hides the button.
    var onRewrite: (() -> Void)? = nil
    var isRewriting = false
    var onOpenSettings: () -> Void = MeetingNotesMissingConsole.openAISettings

    var body: some View {
        HudConsole {
            HudStatusShape(.warn)
            Text(Self.line(failure)).help(failure ?? "")
        } buttons: {
            if let onRewrite, !Self.mentionsKey(failure) {
                HudButton("Write notes", lamp: .teal, size: .small, action: onRewrite)
                    .disabled(isRewriting)
                    .help("Write the notes again from the transcript")
            }
            HudButton(Self.mentionsKey(failure) ? "Add key" : "AI settings", size: .small, action: onOpenSettings)
                .help("Open AI settings")
        }
        .accessibilityElement(children: .contain)
    }

    /// "No notes — " and the first sentence of the reason.
    static func line(_ failure: String?) -> String {
        guard let failure = failure?.trimmingCharacters(in: .whitespacesAndNewlines), !failure.isEmpty else {
            return String(localized: "No notes — no model has written them yet")
        }
        return String(localized: "No notes — \(sentences(failure).first)")
    }

    /// What the one-line console could not say: the rest of the reason, or all of it
    /// when its first sentence is too long for the line. nil: nothing more to add.
    static func remainder(_ failure: String?) -> String? {
        guard let failure = failure?.trimmingCharacters(in: .whitespacesAndNewlines), !failure.isEmpty else { return nil }
        let parts = sentences(failure)
        if parts.first.count > 56 { return failure }
        return parts.rest.isEmpty ? nil : parts.rest
    }

    private static func sentences(_ text: String) -> (first: String, rest: String) {
        guard let end = text.range(of: ". ") else {
            return (text.hasSuffix(".") ? String(text.dropLast()) : text, "")
        }
        return (String(text[..<end.lowerBound]), String(text[end.upperBound...]))
    }

    static func mentionsKey(_ failure: String?) -> Bool {
        failure?.localizedCaseInsensitiveContains("key") ?? false
    }

    static func openAISettings() {
        NotificationCenter.default.post(name: .openDesktopSettings, object: nil, userInfo: ["category": SettingsCategory.ai.rawValue])
    }
}

// MARK: - Decided

/// "Decided": numbered lines.
///
///     MeetingDecidedSection(decisions: summary.decisions)
struct MeetingDecidedSection: View {
    let decisions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: "Decided").accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(decisions.enumerated()), id: \.offset) { index, decision in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .hud(.micro, Hud.Ink.ink3)
                            .frame(width: 12, alignment: .leading)
                            .padding(.top, 5)
                        Text(decision)
                            .hud(.read)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, Hud.Row.inset)
        }
    }
}

// MARK: - Timestamped rows

/// A timestamp that plays from its moment (36 pt column). Quiet until hovered.
struct MeetingTimestampButton: View {
    let time: TimeInterval?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Group {
            if let time {
                Button(action: action) {
                    Text(TranscriptTextFormatter.timestamp(time))
                        .hud(.micro, isHovering ? Hud.Ink.ink1 : Hud.Ink.ink3)
                        .frame(width: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in withAnimation(Hud.Motion.hover) { isHovering = hovering } }
                .help("Play from here")
                .accessibilityLabel("Play from \(TranscriptTextFormatter.timestamp(time))")
            } else {
                Color.clear.frame(width: 36, height: 1)
            }
        }
        .padding(.top, 4)
    }
}

/// The layout For you and Transcript share (`.trow !h-auto py-2.5 !items-start`): the
/// timestamp on the left, the text, an action on the right.
struct MeetingTimestampedRow<Content: View, Trailing: View>: View {
    let time: TimeInterval?
    let onPlay: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MeetingTimestampButton(time: time, action: onPlay)
            VStack(alignment: .leading, spacing: 3) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, Hud.Row.inset)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - For you

/// "For you": action items. An item that is not in Tasks carries "+ Add" (xs secondary);
/// once added, a teal lamp and "In Tasks" take its place, flashing once.
///
///     MeetingForYouSection(items: summary.actionItems, importedIDs: imported,
///                          onPlay: { player.play(from: $0) }) { item in await add(item) }
struct MeetingForYouSection: View {
    let items: [ActionItem]
    let importedIDs: Set<UUID>
    var isDisabled = false
    let onPlay: (TimeInterval) -> Void
    let onAdd: (ActionItem) async -> Void

    @State private var adding = Set<UUID>()
    @State private var justAdded = Set<UUID>()
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    init(items: [ActionItem], importedIDs: Set<UUID>, isDisabled: Bool = false,
         onPlay: @escaping (TimeInterval) -> Void, onAdd: @escaping (ActionItem) async -> Void) {
        self.items = items
        self.importedIDs = importedIDs
        self.isDisabled = isDisabled
        self.onPlay = onPlay
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HudGroupHeader(title: "For you", count: items.count).accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                row(item).hudGlide(item.id, hovered: $hovered, in: glide)
            }
        }
    }

    private func row(_ item: ActionItem) -> some View {
        let imported = importedIDs.contains(item.id)
        return MeetingTimestampedRow(time: item.sourceTime, onPlay: { if let time = item.sourceTime { onPlay(time) } }) {
            Text(item.title)
                .hud(.body, imported ? Hud.Ink.ink2 : Hud.Ink.ink1)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.meta(item)).hud(.meta).lineLimit(1)
        } trailing: {
            if imported {
                MeetingInTasksWord(flashes: justAdded.contains(item.id))
            } else {
                Button {
                    adding.insert(item.id)
                    justAdded.insert(item.id)
                    Task {
                        await onAdd(item)
                        adding.remove(item.id)
                    }
                } label: {
                    HudButtonLabel("Add", glyph: .plus)
                }
                .buttonStyle(HudButtonStyle(kind: .secondary, size: .mini))
                .disabled(isDisabled || adding.contains(item.id))
                .help("Add to Tasks")
                .accessibilityLabel("Add to Tasks: \(item.title)")
            }
        }
    }

    /// "Deniz · by Fri 20", "by Fri 20", "no date".
    static func meta(_ item: ActionItem) -> String {
        var parts: [String] = []
        if let assignee = item.assignee?.trimmingCharacters(in: .whitespacesAndNewlines), !assignee.isEmpty {
            parts.append(assignee)
        }
        if let date = item.dueDate {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.locale
            formatter.dateFormat = "EEE d"
            parts.append(String(localized: "by \(formatter.string(from: date))"))
        } else {
            parts.append(String(localized: "no date"))
        }
        return parts.joined(separator: " · ")
    }
}

/// "In Tasks" behind a teal lamp, 22 pt tall like the key it replaces. `flashes`: it
/// lights up once as it appears (0.38 s).
struct MeetingInTasksWord: View {
    var flashes = false
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HudStatusWord(.ok, "In Tasks")
            .frame(height: 22)
            .brightness(flashes && !lit && !reduceMotion ? 0.6 : 0)
            .opacity(flashes && !lit ? 0 : 1)
            .onAppear {
                guard flashes else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.38)) { lit = true }
            }
    }
}

// MARK: - Transcript

/// One transcript segment: timestamp left, speaker and text. Right-click: Copy, Play
/// from here.
struct MeetingTranscriptRow: View, Equatable {
    let segment: TranscriptSegment
    let allowsInlineTextSelection: Bool
    let onPlay: () -> Void
    let onCopy: () -> Void

    var body: some View {
        MeetingTimestampedRow(time: segment.startTime, onPlay: onPlay) {
            Text(displaySpeakerName).hud(.label, Hud.Ink.ink2).lineLimit(1)
            segmentText
        } trailing: {
            EmptyView()
        }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Play from here", action: onPlay)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var segmentText: some View {
        let text = Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .hud(.read)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        if allowsInlineTextSelection {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segment == rhs.segment && lhs.allowsInlineTextSelection == rhs.allowsInlineTextSelection
    }

    private var displaySpeakerName: String {
        let name = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? TranscriptTextFormatter.fallbackSpeakerName(segment.speakerID)
    }
}

/// "Transcript" and its rows, sharing one sliding hover slab. Its body is a flat list of
/// rows, so inside a `LazyVStack` the rows stay lazy.
///
///     MeetingTranscriptSection(transcript: transcript, onPlay: { player.play(from: $0) }, onCopy: copy)
struct MeetingTranscriptSection: View {
    let transcript: Transcript
    let onPlay: (TimeInterval) -> Void
    let onCopy: (String) -> Void

    @State private var hovered: AnyHashable?
    @Namespace private var glide

    var body: some View {
        HudGroupHeader(title: "Transcript").accessibilityAddTraits(.isHeader)
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
                    onPlay: { onPlay(segment.startTime) },
                    onCopy: { onCopy(segment.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                )
                .equatable()
                .hudGlide(segment.id, hovered: $hovered, in: glide)
            }
        }
    }
}

// MARK: - No transcript yet

/// Why there is no transcript, as a shape and a sentence (`o-detail-failed`, `-queued`,
/// `-preparing`, `-unreadable`).
enum MeetingTranscriptState: Equatable {
    case failed, queued, preparing, unreadable

    /// A meeting without a stored transcription.
    init(_ status: StoredMeeting.ProcessingStatus) {
        switch status {
        case .failed: self = .failed
        case .recorded: self = .queued
        case .processing: self = .preparing
        case .completed: self = .unreadable
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .failed: "Transcription didn’t finish"
        case .queued: "Waiting to be transcribed"
        case .preparing: "Preparing the transcript"
        case .unreadable: "Couldn’t read the transcript"
        }
    }

    var canRetry: Bool { self == .failed || self == .unreadable }
}

/// The one line shown in place of notes and transcript; the scanner runs while the
/// transcript is being prepared.
///
///     MeetingTranscriptStateConsole(state: MeetingTranscriptState(meeting.processingStatus)) { retry() }
struct MeetingTranscriptStateConsole: View {
    let state: MeetingTranscriptState
    let onRetry: () -> Void

    var body: some View {
        HudConsole(height: 48) {
            Group {
                switch state {
                case .failed: HudStatusShape(.err)
                case .queued: HudStatusShape(.wait)
                case .preparing: HudBusy()
                case .unreadable: HudStatusShape(.warn)
                }
            }
            Text(state.title).hud(.body).padding(.leading, 2)
        } buttons: {
            if state.canRetry {
                HudButton("Try again", size: .small, action: onRetry)
            }
        }
        .hudScanner(state == .preparing, radius: Hud.Radius.console)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rename speaker

/// The rename-speaker sheet (`al-rename`): a title, one field, Cancel `esc` · Save `↩`.
///
///     MeetingRenameSpeakerSheet(name: $name, isSaving: saving, message: error, onCancel: close, onSave: save)
struct MeetingRenameSpeakerSheet: View {
    @Binding var name: String
    var isSaving = false
    /// A failure to show under the actions.
    var message: String?
    var isDisabled = false
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename speaker").hud(.title)

            TextField("", text: $name, prompt: Text("Name").foregroundStyle(Hud.Ink.ink3))
                .textFieldStyle(.plain)
                .hud(.body)
                .focused($isFocused)
                .onSubmit { if canSave { onSave() } }
                .hudField(height: 36, radius: 10, isFocused: isFocused, padding: 10)
                .accessibilityLabel("Speaker name")

            HudActions {
                if isSaving {
                    HudBusy()
                    Text("Saving…")
                } else if let message {
                    HudStatusShape(.err)
                    Text(message).help(message)
                }
            } buttons: {
                HudButton("Cancel", key: "esc", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                HudButton("Save", key: "↩", kind: .primary, action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.black)
        .overlay(RoundedRectangle(cornerRadius: Hud.Radius.sheet, style: .continuous).strokeBorder(Color(white: 1, opacity: 0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Hud.Radius.sheet, style: .continuous))
        .preferredColorScheme(.dark)
        .onAppear { isFocused = true }
    }

    private var canSave: Bool {
        !isSaving && !isDisabled && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
