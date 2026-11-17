import Foundation

/// The meeting exports besides Markdown (which is stored with the meeting already).
///
///     let data = MeetingExportFormat.pdf.data(meeting: meeting, transcription: stored)
enum MeetingExportFormat: CaseIterable, Sendable {
    case pdf
    case plainText

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .plainText: "txt"
        }
    }

    /// Name for the save panel and the failure alert: "PDF", "Plain text".
    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .plainText: "Plain text"
        }
    }

    func data(meeting: StoredMeeting, transcription: StoredTranscription) -> Data {
        switch self {
        case .pdf: MeetingPDFRenderer.pdfData(meeting: meeting, transcription: transcription)
        case .plainText: Data(MeetingPlainTextFormatter.text(meeting: meeting, transcription: transcription).utf8)
        }
    }
}

/// A meeting as readable text with no Markdown syntax: title, date, summary, decisions,
/// action items, then the transcript with speaker names and timestamps. The Plain text…
/// export writes `text`; the PDF… export sets the same `blocks` in type.
///
///     MeetingPlainTextFormatter.text(meeting: meeting, transcription: stored)
enum MeetingPlainTextFormatter {
    /// One piece of the export, in reading order.
    enum Block: Equatable {
        case title(String)
        case meta(String)
        case heading(String)
        case paragraph(String)
        case item(String)
        case speaker(name: String, time: String)
    }

    static func text(meeting: StoredMeeting, transcription: StoredTranscription) -> String {
        var lines: [String] = []
        for block in blocks(meeting: meeting, transcription: transcription) {
            switch block {
            case .title(let title):
                lines.append(title)
            case .meta(let text):
                lines.append(text)
            case .heading(let heading):
                lines.append("")
                lines.append(heading.uppercased(with: AppLanguage.locale))
                lines.append("")
            case .paragraph(let text):
                lines.append(text)
                lines.append("")
            case .item(let text):
                lines.append("• \(text)")
            case .speaker(let name, let time):
                if lines.last?.isEmpty == false { lines.append("") }
                lines.append("\(name) · \(time)")
            }
        }
        // One blank line between sections, none at the end.
        var output: [String] = []
        for line in lines where !(line.isEmpty && output.last?.isEmpty == true) {
            output.append(line)
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n") + "\n"
    }

    static func blocks(meeting: StoredMeeting, transcription: StoredTranscription) -> [Block] {
        var blocks: [Block] = [.title(meeting.title.trimmingCharacters(in: .whitespacesAndNewlines))]
        let date = meeting.startedAt.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: AppLanguage.locale))
        blocks.append(.meta("\(date) · \(TranscriptTextFormatter.timestamp(meeting.duration))"))

        if let summary = transcription.summary {
            let overview = summary.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(.heading("Summary"))
            blocks.append(.paragraph(overview.isEmpty ? "The transcript doesn’t have enough content to summarize." : overview))

            blocks.append(.heading("Decisions"))
            if summary.decisions.isEmpty {
                blocks.append(.item("No explicit decisions found."))
            } else {
                blocks += summary.decisions.map { .item($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }

            blocks.append(.heading("Action items"))
            if summary.actionItems.isEmpty {
                blocks.append(.item("No explicit action items found."))
            } else {
                blocks += summary.actionItems.map { .item(actionText($0)) }
            }
        }

        blocks.append(.heading("Transcript"))
        let transcript = transcription.transcript
        if transcript.segments.isEmpty {
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
        } else {
            for segment in transcript.segments {
                let speaker = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = speaker.flatMap { $0.isEmpty ? nil : $0 }
                    ?? TranscriptTextFormatter.fallbackSpeakerName(segment.speakerID)
                blocks.append(.speaker(name: name, time: TranscriptTextFormatter.timestamp(segment.startTime)))
                blocks.append(.paragraph(segment.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return blocks
    }

    /// "Send the deck (Ayşe, 12:40, due 4 Dec 2026)".
    private static func actionText(_ action: ActionItem) -> String {
        var details: [String] = []
        if let assignee = action.assignee?.trimmingCharacters(in: .whitespacesAndNewlines), !assignee.isEmpty {
            details.append(assignee)
        } else if let speakerID = action.speakerID {
            details.append(TranscriptTextFormatter.fallbackSpeakerName(speakerID))
        }
        if let time = action.sourceTime {
            details.append(TranscriptTextFormatter.timestamp(time))
        }
        if let dueDate = action.dueDate {
            details.append("due \(dueDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLanguage.locale)))")
        }
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? title : "\(title) (\(details.joined(separator: ", ")))"
    }
}
