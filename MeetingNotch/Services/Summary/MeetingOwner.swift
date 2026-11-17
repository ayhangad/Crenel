import Foundation

/// The person who recorded the meeting. Action items are kept only when they belong to this
/// person (product decision 2026-11-16): other people's tasks are not shown. No extra speaker
/// identification is done; ownership comes from what the transcript already knows — the
/// on-device microphone track ("You"), names the user gave speakers, and the account name.
struct MeetingOwner: Equatable, Sendable {
    /// Lower-cased names that refer to the owner ("ayhan", "ayhan gad", "you", …).
    var names: [String]
    /// Transcript speaker IDs that are the owner (the local microphone track).
    var speakerIDs: [String]

    static let selfReferences = ["you", "me", "myself", "ben", "sen", "bana", "sana"]

    init(names: [String], speakerIDs: [String] = [LocalTranscriptSpeaker.microphone.id]) {
        var seen = Set<String>()
        self.names = (names + Self.selfReferences)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        self.speakerIDs = speakerIDs
    }

    /// The macOS account name and its first word.
    static func current(fullName: String = NSFullUserName()) -> MeetingOwner {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: " ").first.map(String.init) ?? ""
        return MeetingOwner(names: [trimmed, first])
    }

    /// The account name to show the model ("Ayhan Gad"), without the generic self references.
    var displayName: String? {
        names.first { !Self.selfReferences.contains($0) }?
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// One line for prompts. The model is told who the owner is so it returns only their tasks.
    var promptDescription: String {
        let name = displayName.map { "named \"\($0)\"" } ?? "with an unknown name"
        return "the person who recorded this meeting, \(name); lines with speakerID \(speakerIDs.map { "\"\($0)\"" }.joined(separator: " or ")) or speaker name \"You\" are this person"
    }

    // MARK: Ownership

    func isOwner(name: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !name.isEmpty else { return false }
        return names.contains { $0 == name || name.hasPrefix($0 + " ") || $0.hasPrefix(name + " ") }
    }

    /// Keeps the owner's actions and those whose owner is unknown (no name, or only a label
    /// like "Speaker 2"; the model was asked to return only the owner's). Drops actions
    /// clearly assigned to someone else: another person's name or named speaker.
    func ownActions(_ actions: [ActionItem], in transcript: Transcript) -> [ActionItem] {
        let speakerNames = Dictionary(
            transcript.segments.compactMap { segment in segment.speakerName.map { (segment.speakerID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return actions.filter { action in
            if let assignee = action.assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
               !Self.isGenericSpeakerName(assignee) {
                return isOwner(name: assignee)
            }
            if let speakerID = action.speakerID {
                if speakerIDs.contains(speakerID) { return true }
                // A named speaker who is not the owner owns it.
                if let name = speakerNames[speakerID], !Self.isGenericSpeakerName(name) { return isOwner(name: name) }
            }
            return true
        }
    }

    func ownActions(of summary: MeetingSummary, in transcript: Transcript) -> MeetingSummary {
        var summary = summary
        summary.actionItems = ownActions(summary.actionItems, in: transcript)
        return summary
    }

    /// "Speaker 2", "Participants": labels, not people.
    static func isGenericSpeakerName(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.isEmpty || lower == LocalTranscriptSpeaker.systemAudio.name.lowercased()
            || lower == LocalTranscriptSpeaker.single.name.lowercased()
            || lower.range(of: #"^(speaker|konuşmacı)[ _]?\d*$"#, options: .regularExpression) != nil
    }
}
