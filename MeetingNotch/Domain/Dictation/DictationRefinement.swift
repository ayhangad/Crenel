import Foundation

/// Where dictated text is going; used for tone and safety decisions.
struct DictationContext: Equatable, Sendable {
    var appBundleIdentifier: String?
    var appName: String?
    var selectedText: String?
    var localeIdentifier: String
    var vocabulary: [String]
}

enum DictationRefinementOutcome: Equatable, Sendable {
    case insert(String)
    case replaceSelection(String)
    case createTask(String)
}

protocol DictationTextRefining: Sendable {
    func refine(transcript: String, context: DictationContext) async -> DictationRefinementOutcome
}

struct PassthroughDictationRefiner: DictationTextRefining {
    func refine(transcript: String, context: DictationContext) async -> DictationRefinementOutcome {
        .insert(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
