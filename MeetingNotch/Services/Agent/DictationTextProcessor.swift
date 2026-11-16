import Foundation

/// Destination-app tone, derived from the frontmost app.
enum DictationTone: Equatable, Sendable {
    case formal
    case casual
    case code
    case terminal
    case neutral

    static func resolve(bundleIdentifier: String?, appName: String?) -> DictationTone {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let name = appName?.lowercased() ?? ""
        func matches(_ bundles: [String], _ names: [String]) -> Bool {
            bundles.contains { bundle == $0 || bundle.hasPrefix($0 + ".") } || names.contains { name.contains($0) }
        }
        if matches(["com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.warp-stable",
                    "dev.warp.warp"], ["terminal", "iterm", "ghostty", "warp"]) {
            return .terminal
        }
        if matches(["com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92",
                    "com.microsoft.vscodeinsiders"], ["xcode", "visual studio code", "vs code", "cursor"]) {
            return .code
        }
        if matches(["com.apple.mail", "com.microsoft.outlook"], ["mail", "outlook"]) {
            return .formal
        }
        if matches(["com.tinyspeck.slackmacgap", "com.apple.mobilesms", "net.whatsapp.whatsapp", "desktop.whatsapp",
                    "ru.keepcoder.telegram", "com.tdesktop.telegram", "org.telegram.desktop"],
                   ["slack", "messages", "mesajlar", "whatsapp", "telegram"]) {
            return .casual
        }
        return .neutral
    }
}

/// Deterministic, offline text pass. Always runs, including when the provider is off.
enum DictationTextProcessor {
    static let taskPrefixes = ["görev ekle", "yeni görev", "hatırlat bana", "add task", "add a task", "remind me to"]

    // MARK: Intent

    /// Returns the task text when the transcript starts with a task trigger phrase.
    static func taskText(in transcript: String, localeIdentifier: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in taskPrefixes {
            guard let range = caseInsensitivePrefixRange(prefix, in: trimmed) else { continue }
            let rest = trimmed[range.upperBound...]
            // Must be a whole-word prefix ("yeni görevler" is not a trigger).
            if let first = rest.first, first.isLetter || first.isNumber { continue }
            let body = String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " :,;.-–—\n\t"))
            var cleaned = removeFillers(from: body)
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
            guard !cleaned.isEmpty else { return nil }
            return capitalizeFirst(cleaned, localeIdentifier: localeIdentifier)
        }
        return nil
    }

    /// True when a short utterance reads like an editing instruction for the selected text.
    static func looksLikeCommand(_ transcript: String) -> Bool {
        func stripped(_ input: [String]) -> [String] {
            var words = input
            while let first = words.first, ["please", "lütfen", "can", "could", "you", "hey"].contains(first) {
                words.removeFirst()
            }
            while let last = words.last, ["please", "lütfen"].contains(last) { words.removeLast() }
            return words
        }
        let english = stripped(normalizedWords(transcript, localeIdentifier: "en"))
        let words = stripped(normalizedWords(transcript, localeIdentifier: "tr"))
        guard !words.isEmpty, words.count <= 12, let last = words.last else { return false }

        let englishVerbs: Set<String> = [
            "make", "shorten", "lengthen", "translate", "fix", "rewrite", "rephrase", "summarize", "summarise",
            "simplify", "expand", "condense", "convert", "turn", "correct", "proofread", "polish", "format"
        ]
        if let first = english.first, englishVerbs.contains(first) { return true }

        let turkishVerbs: Set<String> = [
            "kısalt", "uzat", "çevir", "düzelt", "özetle", "sadeleştir", "toparla", "dönüştür", "genişlet",
            "kısaltır", "çevirir", "düzeltir"
        ]
        if turkishVerbs.contains(last) { return true }
        // Generic verbs ("yap", "yaz", "getir") count only with an editing qualifier.
        if ["yap", "yaz", "getir", "hale"].contains(last) {
            let qualifiers: Set<String> = [
                "daha", "resmi", "samimi", "kısa", "uzun", "yeniden", "baştan", "madde", "maddeler", "haline",
                "büyük", "küçük", "profesyonel", "kibar", "net", "sade"
            ]
            return words.dropLast().contains { qualifiers.contains($0) }
        }
        return false
    }

    // MARK: Cleanup

    static func clean(_ transcript: String, context: DictationContext) -> String {
        let tone = DictationTone.resolve(bundleIdentifier: context.appBundleIdentifier, appName: context.appName)
        var text = removeFillers(from: transcript)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        switch tone {
        case .terminal:
            break // Commands and paths: never change case or add punctuation.
        case .code where wordCount == 1:
            break // Identifiers keep their casing.
        default:
            text = capitalizeFirst(text, localeIdentifier: context.localeIdentifier)
            let minimumWords = tone == .casual ? 9 : 4
            if wordCount >= minimumWords, let last = text.last, !".!?…:;\"')]»".contains(last) {
                text += isQuestion(text) ? "?" : "."
            }
        }
        return applyVocabulary(context.vocabulary, to: text)
    }

    static func removeFillers(from input: String) -> String {
        var text = input
        let boundaryStart = "(?<![\\p{L}\\p{N}])"
        let boundaryEnd = "(?![\\p{L}\\p{N}])"
        // Pure hesitation sounds, with any comma/ellipsis that follows them.
        let sounds = "(?:ı{2,}|ee+(?!\\?)|ım+|hm+|um+|uh+|erm)"
        text = replace("(?i)\(boundaryStart)\(sounds)\(boundaryEnd)\\s*[,…]*", in: text, with: "")
        // "şey" only as a comma-delimited filler at the start or between commas, never "bir şey".
        text = replace("(?i)^\\s*şey\\s*,\\s*", in: text, with: "")
        text = replace("(?i)([.!?]\\s+)şey\\s*,\\s*", in: text, with: "$1")
        text = replace("(?i),\\s*şey\\s*,", in: text, with: ",")
        // "you know" only when comma-delimited mid-sentence.
        text = replace("(?i),\\s*you know\\s*,", in: text, with: "")
        // Tidy spacing and punctuation left behind.
        text = replace("\\s+", in: text, with: " ")
        text = replace("\\s+([,.!?;:])", in: text, with: "$1")
        text = replace(",{2,}", in: text, with: ",")
        text = replace("^[\\s,;]+", in: text, with: "")
        text = replace(",\\s*([.!?])", in: text, with: "$1")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Personal dictionary terms replace case-insensitive whole-word matches with their exact casing.
    static func applyVocabulary(_ vocabulary: [String], to input: String) -> String {
        var text = input
        for term in vocabulary.sorted(by: { $0.count > $1.count }) {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let pattern = "(?i)(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: trimmed))(?![\\p{L}\\p{N}_])"
            text = replace(pattern, in: text, with: NSRegularExpression.escapedTemplate(for: trimmed))
        }
        return text
    }

    static func capitalizeFirst(_ text: String, localeIdentifier: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        // Leave words that already contain uppercase (iPhone, macOS-like) or URLs alone.
        let wordEnd = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
        let word = text[index..<wordEnd]
        if word.dropFirst().contains(where: \.isUppercase) || word.contains("://") || word.contains("@") {
            return text
        }
        let locale = Locale(identifier: localeIdentifier)
        let upper = String(text[index]).uppercased(with: locale)
        return text.replacingCharacters(in: index...index, with: upper)
    }

    // MARK: Helpers

    /// Lowercased words; Turkish rules map "İ"→"i" and "I"→"ı", English rules "I"→"i".
    static func normalizedWords(_ text: String, localeIdentifier: String = "tr") -> [String] {
        text.lowercased(with: Locale(identifier: localeIdentifier))
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(.nonBaseCharacters).inverted)
            .filter { !$0.isEmpty }
    }

    private static func isQuestion(_ text: String) -> Bool {
        let words = normalizedWords(text)
        let particles: Set<String> = [
            "mi", "mı", "mu", "mü", "misin", "mısın", "musun", "müsün", "miyiz", "mıyız", "muyuz", "müyüz",
            "misiniz", "mısınız", "musunuz", "müsünüz", "miyim", "mıyım", "muyum", "müyüm", "midir", "mıdır"
        ]
        if words.suffix(2).contains(where: particles.contains) { return true }
        let englishStarters: Set<String> = [
            "what", "why", "how", "when", "where", "who", "which", "can", "could", "would", "should", "do",
            "does", "did", "is", "are", "will", "shall"
        ]
        let english = text.lowercased().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return englishStarters.contains(english)
    }

    private static func caseInsensitivePrefixRange(_ prefix: String, in text: String) -> Range<String.Index>? {
        for locale in [Locale(identifier: "tr"), Locale(identifier: "en")] {
            if let range = text.range(of: prefix, options: [.caseInsensitive, .anchored], locale: locale) {
                return range
            }
        }
        return nil
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
