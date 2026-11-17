import Foundation

protocol MeetingSummaryGenerating: Sendable {
    func generate(from transcript: Transcript) async throws -> MeetingSummary
    func generate(from transcript: Transcript, meeting: StoredMeeting) async throws -> MeetingSummary
}

extension MeetingSummaryGenerating {
    func generate(from transcript: Transcript, meeting: StoredMeeting) async throws -> MeetingSummary {
        try await generate(from: transcript)
    }
}

/// Produces conservative, extractive notes without sending the transcript to another service.
/// Every output sentence is taken from the transcript; missing decisions or owners stay missing.
struct ExtractiveMeetingSummaryService: MeetingSummaryGenerating, Sendable {
    private static let decisionMarkers = [
        "karar verdik", "kararlaştırdık", "kararlaştırıldı", "kararımız", "karar:",
        "decided", "we agreed", "decision:", "agreed to"
    ]
    private static let actionMarkers = [
        "aksiyon:", "aksiyon maddesi", "yapacağım", "yapacağız", "yapacak",
        "tamamlayacağım", "göndereceğim", "hazırlayacağım", "gerekiyor", "gerekli",
        "action item", "i will", "i'll", "we will", "needs to", "need to", "todo"
    ]
    private static let firstPersonActionMarkers = [
        "yapacağım", "tamamlayacağım", "göndereceğim", "hazırlayacağım",
        "i will", "i'll"
    ]

    func generate(from transcript: Transcript) async throws -> MeetingSummary {
        try Task.checkCancellation()

        let candidates = sentenceCandidates(from: transcript)
        let overviewSentences = Array(candidates.prefix(3).map(\.text))
        let decisions = uniqueMatches(in: candidates, markers: Self.decisionMarkers)
            .map(\.text)
        let actions = uniqueMatches(in: candidates, markers: Self.actionMarkers).map { candidate in
            ActionItem(
                title: candidate.text,
                assignee: explicitAssignee(for: candidate),
                dueDate: explicitDate(in: candidate.text)
            )
        }

        return MeetingSummary(
            overview: overviewSentences.joined(separator: " "),
            decisions: decisions,
            actionItems: actions
        )
    }

    private func sentenceCandidates(from transcript: Transcript) -> [Candidate] {
        let segments = transcript.segments.isEmpty
            ? [TranscriptSegment(
                speakerID: "speaker_0",
                startTime: 0,
                endTime: 0,
                text: transcript.text
            )]
            : transcript.segments

        return segments.flatMap { segment in
            splitSentences(segment.text).map { sentence in
                Candidate(
                    text: sentence,
                    normalizedText: sentence.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: transcript.languageCode ?? "tr")
                    ),
                    speakerName: normalizedSpeakerName(segment.speakerName)
                )
            }
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { ".!?".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 12 }
            .map { sentence in
                guard sentence.count > 320 else { return sentence }
                return String(sentence.prefix(317)) + "…"
            }
    }

    private func uniqueMatches(in candidates: [Candidate], markers: [String]) -> [Candidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            guard markers.contains(where: {
                candidate.normalizedText.contains(normalizedMarker($0))
            }) else { return false }
            let key = candidate.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return seen.insert(key).inserted
        }
    }

    private func explicitAssignee(for candidate: Candidate) -> String? {
        guard Self.firstPersonActionMarkers.contains(where: {
            candidate.normalizedText.contains(normalizedMarker($0))
        }) else {
            return nil
        }
        return candidate.speakerName
    }

    private func explicitDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }

    private func normalizedSpeakerName(_ name: String?) -> String? {
        guard let value = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func normalizedMarker(_ marker: String) -> String {
        marker.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr")
        )
    }

    private struct Candidate {
        let text: String
        let normalizedText: String
        let speakerName: String?
    }
}
