import Foundation

/// The people of a meeting in one short line, the same way everywhere they appear.
enum MeetingPeopleFormatter {
    /// "Deniz", "Deniz and Ece", "Deniz, Ece and Mert", "Deniz, Ece and 2 others".
    /// nil when there is nobody to name.
    static func short(_ names: [String]) -> String? {
        let names = cleaned(names)
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case 2: return String(localized: "\(names[0]) and \(names[1])")
        case 3: return String(localized: "\(names[0]), \(names[1]) and \(names[2])")
        default:
            let rest = names.count - 2
            return rest == 1
                ? String(localized: "\(names[0]), \(names[1]) and 1 other")
                : String(localized: "\(names[0]), \(names[1]) and \(rest) others")
        }
    }

    /// The others and the user, for a meeting that was recorded: "Deniz, Ece, you";
    /// past three names, "Deniz, Ece, you and 3 others". nil when nobody else was invited.
    static func withYou(_ names: [String]) -> String? {
        let names = cleaned(names)
        guard !names.isEmpty else { return nil }
        let you = String(localized: "you")
        if names.count <= 3 { return (names + [you]).joined(separator: ", ") }
        let rest = names.count - 2
        return String(localized: "\(names[0]), \(names[1]), \(you) and \(rest) others")
    }

    /// Head count with the user: "5 people". nil when nobody else was invited.
    static func count(_ names: [String]) -> String? {
        let others = cleaned(names).count
        guard others > 0 else { return nil }
        return String(localized: "\(others + 1) people")
    }

    /// Initials for stacked faces: the first three people, then "+N" for the rest.
    static func initials(_ names: [String], limit: Int = 3) -> [String] {
        let names = cleaned(names)
        var result = names.prefix(limit).map { name in
            name.first.map { String($0).uppercased() } ?? "?"
        }
        if names.count > limit { result.append("+\(names.count - limit)") }
        return result
    }

    private static func cleaned(_ names: [String]) -> [String] {
        names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
