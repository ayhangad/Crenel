import SwiftUI

/// After the recording stops: four stations on one rail — Saved, Uploaded,
/// Transcribing, Notes. The live station blinks; under the rail stands its detail: a
/// number when progress is known, a scanner when it is not.
struct ProcessingSurface: View {
    enum Station: Int, CaseIterable, Sendable {
        case saving, uploading, transcribing, summarizing
    }

    let station: Station
    /// The meeting being processed.
    var title: String?
    /// How much was recorded, in seconds.
    var recorded: TimeInterval?
    /// 0…1 while uploading.
    var uploadProgress: Double?
    /// nil hides Stop (saving cannot be stopped).
    var onStop: (() -> Void)?
    /// A fixed scanner position, for renders and tests.
    var scannerPhase: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: headline).hudTrimmed(.title)
                if let recorded {
                    Text("\(HudFormat.elapsed(recorded)) recorded").hudTrimmed(.meta).fixedSize()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Hud.Layout.rowPad)
            .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)

            HudStations(titles: stationTitles, current: station.rawValue)
                .padding(.horizontal, Hud.Layout.rowPad)
                .padding(.top, Hud.Layout.block)
                .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: stationTitles[station.rawValue]))
                .accessibilityValue("Step \(station.rawValue + 1) of 4")

            detail
                .padding(.top, Hud.Layout.section)
                .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)

            HudActions {
                HudIcon(.shield, size: 12).foregroundStyle(Hud.Ink.ink4)
                Text("The audio is already safe on this Mac")
            } buttons: {
                if let onStop {
                    HudButton("Stop", key: "esc", size: .small, action: onStop)
                        .hudShortcut(.cancelAction)
                        .accessibilityLabel("Stop processing")
                }
            }
            .padding(.horizontal, Hud.Layout.rowPad)
            .padding(.top, Hud.Layout.section)
            .hudStagger(3, shown: appeared, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }

    private var headline: String {
        if let title, !title.isEmpty { return title }
        return String(localized: "Recording")
    }

    /// Each station's word in its current tense.
    private var stationTitles: [String] {
        switch station {
        case .saving: ["Saving", "Upload", "Transcript", "Notes"]
        case .uploading: ["Saved", "Uploading", "Transcript", "Notes"]
        case .transcribing: ["Saved", "Uploaded", "Transcribing", "Notes"]
        case .summarizing: ["Saved", "Uploaded", "Transcribed", "Writing notes"]
        }
    }

    private var detailText: String {
        switch station {
        case .saving:
            if let recorded, recorded >= 60 {
                return "Writing \(Int((recorded / 60).rounded())) min of audio to disk"
            }
            return String(localized: "Writing the audio to disk")
        case .uploading: return String(localized: "Sending the audio for transcription")
        case .transcribing: return String(localized: "Telling the speakers apart")
        case .summarizing: return String(localized: "Writing the summary and what to do")
        }
    }

    private var detail: some View {
        HStack(spacing: 12) {
            Text(verbatim: detailText).hudTrimmed(.meta, Hud.Ink.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if station == .uploading, let uploadProgress {
                let percent = Int((min(1, max(0, uploadProgress)) * 100).rounded())
                HudReadout("\(percent)", unit: "%", height: 13, cells: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(percent) percent uploaded")
            }
        }
        // A lit band: its text sits on the content edge, the band 10 out like a slab.
        .padding(.horizontal, Hud.Layout.rowPad)
        .frame(height: Hud.Layout.field)
        .background(RoundedRectangle(cornerRadius: Hud.Layout.hitRadius, style: .continuous).fill(Color(white: 1, opacity: 0.04)))
        .hudScanner(!(station == .uploading && uploadProgress != nil), radius: Hud.Layout.hitRadius, fixedPhase: scannerPhase)
    }
}

/// Before the recording runs: the capture is being set up.
struct PreparingSurface: View {
    var onCancel: () -> Void = {}

    var body: some View {
        HudActions {
            HudBusy()
            Text("Starting the recording")
        } buttons: {
            HudButton("Cancel", key: "esc", size: .small, action: onCancel)
                .hudShortcut(.cancelAction)
        }
        .padding(.horizontal, Hud.Layout.rowPad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Result

/// What a finished meeting measured. `nil` values print as a dash.
struct MeetingResultStats: Equatable, Sendable {
    var speakers: Int?
    var actionItems: Int?
    /// False when the transcript is there but the notes could not be written.
    var hasNotes = true

    init(speakers: Int? = nil, actionItems: Int? = nil, hasNotes: Bool = true) {
        self.speakers = speakers
        self.actionItems = actionItems
        self.hasNotes = hasNotes
    }

    init(transcription: StoredTranscription) {
        speakers = Set(transcription.transcript.segments.map(\.speakerID)).count
        actionItems = transcription.summary?.actionItems.count
        hasNotes = transcription.summary != nil
    }
}

/// Ready: three readouts in one well and one way in.
struct ReadySurface: View {
    var title: String?
    var recorded: TimeInterval?
    var stats: MeetingResultStats?
    var onDone: () -> Void = {}
    /// nil when the meeting is no longer stored.
    var onOpen: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Hud.Layout.block) {
            HStack(spacing: 12) {
                HudLamp(.teal).frame(width: 13)
                Text(stats?.hasNotes == false ? "Transcript is ready" : "Notes are ready").hudTrimmed(.title)
                if let title, !title.isEmpty {
                    Text(verbatim: title).hudTrimmed(.meta)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Hud.Layout.rowPad)
            .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)

            HStack(spacing: 0) {
                readout(recorded.map { HudFormat.elapsed($0) } ?? "-", "recorded")
                HudWellDivider()
                readout(stats?.speakers.map { String($0) } ?? "-", "speakers")
                HudWellDivider()
                readout(stats?.actionItems.map { String($0) } ?? "-", "action items",
                        color: (stats?.actionItems ?? 0) > 0 ? Hud.Ink.signal : Hud.Ink.ink1)
            }
            .padding(.vertical, Hud.Layout.edge - Hud.Layout.rowPad)
            .hudWell(radius: Hud.Layout.hitRadius + 2)
            .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)

            HudActions {
                Text("Kept in Recordings")
            } buttons: {
                HudButton("Done", key: "esc", action: onDone)
                    .hudShortcut(.cancelAction)
                if let onOpen {
                    HudButton("Open notes", key: "↩", kind: .primary, action: onOpen)
                        .hudShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, Hud.Layout.rowPad)
            .padding(.top, Hud.Layout.section - Hud.Layout.block)
            .hudStagger(2, shown: appeared, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }

    private func readout(_ value: String, _ label: LocalizedStringKey, color: Color = Hud.Ink.ink1) -> some View {
        VStack(alignment: .leading, spacing: Hud.Layout.pair) {
            HudSegmentDigits(value, height: 20, color: color)
            Text(label).hudTrimmed(.meta)
        }
        .padding(.vertical, Hud.Layout.rowPad)
        .padding(.horizontal, Hud.Layout.rowPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: value) + Text(verbatim: " ") + Text(label))
    }
}

/// Failed or stopped: the big status shape in a lit well, what happened in two lines,
/// and the way out at the trailing edge.
struct FlowOutcomeSurface: View {
    struct Action {
        let title: String
        var glyph: HudGlyph?
        let run: () -> Void
    }

    let status: HudStatus
    var tint: Color?
    let title: String
    var message: String?
    var secondary: Action?
    /// Carries ↩.
    var primary: Action?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Hud.Layout.section) {
            HStack(alignment: .top, spacing: 12) {
                HudStatusWell(status, tint: tint)
                VStack(alignment: .leading, spacing: Hud.Layout.pair) {
                    Text(verbatim: title).hudTrimmed(.title)
                    if let message, !message.isEmpty {
                        Text(verbatim: message).hud(.meta).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .hudStagger(0, shown: appeared, reduceMotion: reduceMotion)

            HudActions {
                if let secondary {
                    HudButton(secondary.title, glyph: secondary.glyph, action: secondary.run)
                }
                if let primary {
                    HudButton(primary.title, glyph: primary.glyph, key: "↩", kind: .primary, action: primary.run)
                        .hudShortcut(.defaultAction)
                }
            }
            .hudStagger(1, shown: appeared, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, Hud.Layout.rowPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }
}
