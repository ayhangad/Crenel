import Foundation

enum MeetingFileName {
    private static let maximumSlugLength = 48

    static func audioFileName(
        title: String,
        startedAt: Date,
        id: UUID,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let date = formatter.string(from: startedAt)
        return "\(date)_\(slug(title))_\(id.uuidString.prefix(8).lowercased()).m4a"
    }

    static func slug(_ title: String) -> String {
        let folded = title
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        var result = ""
        var lastWasSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !result.isEmpty, !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }

            if result.count >= maximumSlugLength { break }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "meeting" : trimmed
    }
}
