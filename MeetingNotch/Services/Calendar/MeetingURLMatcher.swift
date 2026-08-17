import Foundation

struct MeetingURLMatcher: Sendable {
    struct HostRule: Sendable {
        let host: String

        func matches(_ candidate: String) -> Bool {
            candidate == host || candidate.hasSuffix(".\(host)")
        }
    }

    private let hostRules: [HostRule]
    private static let redirectQueryNames = ["q", "url", "target"]

    init(hosts: [String] = Self.defaultHosts) {
        self.hostRules = hosts.map { HostRule(host: $0.lowercased()) }
    }

    func firstMeetingURL(explicitURL: URL?, location: String?, notes: String?) -> URL? {
        if let explicitURL, let match = normalizedMeetingURL(from: explicitURL) {
            return match
        }

        for text in [location, notes].compactMap({ $0 }) {
            if let match = meetingURLs(in: text).first {
                return match
            }
        }

        return nil
    }

    func isSupported(_ url: URL) -> Bool {
        normalizedMeetingURL(from: url) != nil
    }

    func meetingURLs(in text: String) -> [URL] {
        let decoded = repeatedlyDecoded(htmlUnescaped(text))
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return []
        }

        let range = NSRange(decoded.startIndex..., in: decoded)
        let detected = detector.matches(in: decoded, options: [], range: range)
            .compactMap(\.url)
            .compactMap(normalizedMeetingURL)
        let schemeLess = schemeLessMeetingURLs(in: decoded)

        var seen = Set<String>()
        return (detected + schemeLess).filter { seen.insert($0.absoluteString).inserted }
    }

    private func normalizedMeetingURL(from url: URL) -> URL? {
        normalizedMeetingURL(from: url, remainingRedirectDepth: 2)
    }

    private func normalizedMeetingURL(
        from url: URL,
        remainingRedirectDepth: Int
    ) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        if hostRules.contains(where: { $0.matches(host) }) {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            components.scheme = "https"
            return components.url ?? url
        }

        guard remainingRedirectDepth > 0, isKnownRedirectHost(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        for name in Self.redirectQueryNames {
            guard let rawValue = components.queryItems?.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })?.value else { continue }
            let decoded = repeatedlyDecoded(rawValue)
            guard let nestedURL = URL(string: decoded),
                  let meetingURL = normalizedMeetingURL(
                    from: nestedURL,
                    remainingRedirectDepth: remainingRedirectDepth - 1
                  ) else { continue }
            return meetingURL
        }

        return nil
    }

    private func isKnownRedirectHost(_ host: String) -> Bool {
        host == "google.com"
            || host == "www.google.com"
            || host.hasSuffix(".safelinks.protection.outlook.com")
    }

    private func htmlUnescaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func repeatedlyDecoded(_ value: String) -> String {
        var decoded = value
        for _ in 0..<2 {
            guard let next = decoded.removingPercentEncoding, next != decoded else { break }
            decoded = next
        }
        return decoded
    }

    private func schemeLessMeetingURLs(in text: String) -> [URL] {
        let escapedHosts = hostRules
            .map(\.host)
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        guard !escapedHosts.isEmpty,
              let expression = try? NSRegularExpression(
                pattern: #"(?i)(?<![\w./-])((?:[a-z0-9-]+\.)?(?:\#(escapedHosts))(?:/[a-z0-9_~:/?#\[\]@!$&'()*+,;=%.-]*)?)"#
              ) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            let candidate = String(text[swiftRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"]}"))
            return URL(string: "https://\(candidate)").flatMap(normalizedMeetingURL)
        }
    }

    static let defaultHosts = [
        "zoom.us",
        "zoom.com",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "teams.cloud.microsoft",
        "msteams.link"
    ]
}
