import Foundation

struct MeetingURLMatcher: Sendable {
    struct HostRule: Sendable {
        let host: String

        func matches(_ candidate: String) -> Bool {
            candidate == host || candidate.hasSuffix(".\(host)")
        }
    }

    private let hostRules: [HostRule]

    init(hosts: [String] = Self.defaultHosts) {
        self.hostRules = hosts.map { HostRule(host: $0.lowercased()) }
    }

    func firstMeetingURL(explicitURL: URL?, location: String?, notes: String?) -> URL? {
        if let explicitURL, isSupported(explicitURL) {
            return explicitURL
        }

        for text in [location, notes].compactMap({ $0 }) {
            if let match = meetingURLs(in: text).first {
                return match
            }
        }

        return nil
    }

    func isSupported(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hostRules.contains { $0.matches(host) }
    }

    func meetingURLs(in text: String) -> [URL] {
        let decoded = text.removingPercentEncoding ?? text
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return []
        }

        let range = NSRange(decoded.startIndex..., in: decoded)
        return detector.matches(in: decoded, options: [], range: range)
            .compactMap(\.url)
            .filter(isSupported)
    }

    static let defaultHosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "teams.cloud.microsoft",
        "msteams.link"
    ]
}
