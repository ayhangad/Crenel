import Foundation

enum MeetingMarkdownFormatter {
    static func markdown(
        meeting: StoredMeeting,
        transcription: StoredTranscription
    ) -> String {
        var sections = [
            "# \(escapedHeading(meeting.title))",
            metadata(meeting: meeting, transcription: transcription)
        ]

        if let summary = transcription.summary {
            sections.append(summaryMarkdown(summary))
        }
        sections.append(transcriptMarkdown(transcription.transcript))
        return sections.joined(separator: "\n\n") + "\n"
    }

    static func notes(_ summary: MeetingSummary) -> String {
        summaryMarkdown(summary) + "\n"
    }

    private static func metadata(
        meeting: StoredMeeting,
        transcription: StoredTranscription
    ) -> String {
        let language = transcription.transcript.languageCode?.uppercased() ?? "Otomatik"
        return [
            "- Tarih: \(meeting.startedAt.formatted(date: .long, time: .shortened))",
            "- Süre: \(TranscriptTextFormatter.timestamp(meeting.duration))",
            "- Transkripsiyon: ElevenLabs Scribe v2",
            "- Dil: \(language)"
        ].joined(separator: "\n")
    }

    private static func summaryMarkdown(_ summary: MeetingSummary) -> String {
        let overview = summary.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        let decisions = summary.decisions.isEmpty
            ? "- Açıkça belirtilmiş karar bulunamadı."
            : summary.decisions.map { "- \($0)" }.joined(separator: "\n")
        let actions = summary.actionItems.isEmpty
            ? "- Açıkça belirtilmiş aksiyon maddesi bulunamadı."
            : summary.actionItems.map(actionMarkdown).joined(separator: "\n")

        return """
        ## Kısa Özet

        \(overview.isEmpty ? "Transkript özetlenecek yeterli içerik taşımıyor." : overview)

        ## Kararlar

        \(decisions)

        ## Aksiyon Maddeleri

        \(actions)
        """
    }

    private static func transcriptMarkdown(_ transcript: Transcript) -> String {
        guard !transcript.segments.isEmpty else {
            return "## Transkript\n\n\(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        let body = transcript.segments.map { segment in
            let speaker = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = speaker.flatMap { $0.isEmpty ? nil : $0 }
                ?? TranscriptTextFormatter.fallbackSpeakerName(segment.speakerID)
            let time = TranscriptTextFormatter.timestamp(segment.startTime)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "### \(escapedHeading(displayName)) · \(time)\n\n\(text)"
        }
        .joined(separator: "\n\n")
        return "## Transkript\n\n\(body)"
    }

    private static func actionMarkdown(_ action: ActionItem) -> String {
        var details: [String] = []
        if let assignee = action.assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assignee.isEmpty {
            details.append("Sorumlu: \(assignee)")
        }
        if action.assignee == nil, let speakerID = action.speakerID {
            details.append("Sorumlu: \(TranscriptTextFormatter.fallbackSpeakerName(speakerID))")
        }
        if let time = action.sourceTime {
            details.append("Kaynak: \(TranscriptTextFormatter.timestamp(time))")
        }
        if let dueDate = action.dueDate {
            details.append("Tarih: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        let suffix = details.isEmpty ? "" : " _(\(details.joined(separator: ", ")))_"
        return "- \(action.title)\(suffix)"
    }

    private static func escapedHeading(_ value: String) -> String {
        value.replacingOccurrences(of: "#", with: "\\#")
    }
}
