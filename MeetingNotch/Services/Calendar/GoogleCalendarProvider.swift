import Foundation

struct GoogleCalendarConfiguration: Sendable {
    let clientID: String
    let clientSecret: String
    var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    static var bundled: Self {
        Self(clientID: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? "",
             clientSecret: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String ?? "")
    }
}

actor GoogleCalendarProvider: CalendarMeetingProviding {
    static let keychainService = "gad.MeetingNotch.google-calendar-oauth"
    private let configuration: GoogleCalendarConfiguration
    private let keys: any APIKeyRepository
    private let http: any TranscriptionHTTPClient
    private var selectedIDs: [String]?
    private var generation = 0
    private var connecting = false
    private var connectionTask: Task<GoogleOAuthGrant, Error>?

    init(configuration: GoogleCalendarConfiguration = .bundled,
         keys: any APIKeyRepository = KeychainAPIKeyRepository(service: GoogleCalendarProvider.keychainService),
         http: any TranscriptionHTTPClient = URLSessionTranscriptionHTTPClient()) {
        self.configuration = configuration; self.keys = keys; self.http = http
    }

    func selectCalendars(_ ids: [String]?) async { selectedIDs = ids }

    func authorizationState() async -> CalendarAccessState {
        guard configuration.isConfigured else { return .failed(GoogleCalendarError.notConfigured.localizedDescription) }
        return (try? await keys.apiKey()) == nil ? .notDetermined : .authorized
    }

    func requestAccess() async throws -> Bool {
        guard configuration.isConfigured else { throw GoogleCalendarError.notConfigured }
        guard !connecting else { throw GoogleCalendarError.unavailable }
        connecting = true
        defer { connecting = false; connectionTask = nil }
        let revision = generation
        let configuration = self.configuration
        let task = Task { try await GoogleOAuthSession.authorize(clientID: configuration.clientID) }
        connectionTask = task
        let grant = try await task.value
        let tokens = try await exchange([
            "code": grant.code, "code_verifier": grant.verifier, "redirect_uri": grant.redirectURI,
            "grant_type": "authorization_code"
        ])
        guard revision == generation, tokens.refresh_token != nil else { throw GoogleCalendarError.authorization }
        try await save(tokens, oldRefreshToken: nil)
        return true
    }

    func disconnect() async throws {
        generation += 1
        connectionTask?.cancel()
        connectionTask = nil
        try await keys.deleteAPIKey()
    }

    func query(from startDate: Date, to endDate: Date) async throws -> CalendarMeetingQueryResult {
        let revision = generation
        let token = try await accessToken()
        let calendars: [CalendarEntry] = try await pages(
            path: "users/me/calendarList", query: [.init(name: "maxResults", value: "250")], token: token
        )
        let visible = calendars.filter { $0.deleted != true }
        let selected = selectedIDs
        var meetings: [Meeting] = []
        var scanned = 0
        for calendar in visible where selected?.contains("google:" + calendar.id) ?? true {
            try Task.checkCancellation()
            let escaped = calendar.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let events: [Event] = try await pages(path: "calendars/\(escaped)/events", query: [
                .init(name: "timeMin", value: ISO8601DateFormatter().string(from: startDate)),
                .init(name: "timeMax", value: ISO8601DateFormatter().string(from: endDate)),
                .init(name: "singleEvents", value: "true"), .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "250")
            ], token: token)
            scanned += events.count
            meetings += events.compactMap { Self.meeting(from: $0, calendarID: calendar.id) }
        }
        guard revision == generation else { throw GoogleCalendarError.cancelled }
        var seen = Set<String>()
        meetings = meetings.sorted { $0.startDate < $1.startDate }.filter {
            seen.insert("\($0.startDate.timeIntervalSince1970)|\($0.meetingURL?.absoluteString ?? "")|\($0.title)").inserted
        }
        return CalendarMeetingQueryResult(meetings: meetings,
            sources: [.init(kind: .google, calendarCount: visible.count)], scannedEventCount: scanned,
            calendars: visible.map { .init(id: "google:" + $0.id, title: $0.summary ?? "Google Calendar") })
    }

    struct Event: Decodable {
        let id: String
        let summary: String?
        let status: String?
        let start: EventDate?
        let end: EventDate?
        let hangoutLink: String?
        let location: String?
        let description: String?
        let attendees: [Attendee]?
        let conferenceData: Conference?
        struct EventDate: Decodable { let dateTime: String? }
        struct Attendee: Decodable {
            let isSelf: Bool?
            let responseStatus: String?
            enum CodingKeys: String, CodingKey { case isSelf = "self", responseStatus }
        }
        struct Conference: Decodable {
            let entryPoints: [Entry]?
            struct Entry: Decodable { let entryPointType: String?; let uri: String? }
        }
    }

    static func meeting(from event: Event, calendarID: String) -> Meeting? {
        guard event.status != "cancelled",
              !((event.attendees ?? []).contains { $0.isSelf == true && $0.responseStatus == "declined" }),
              let start = event.start?.dateTime.flatMap(parseDate),
              let end = event.end?.dateTime.flatMap(parseDate), end >= start else { return nil }
        let conferenceURL = event.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
        guard let url = MeetingURLMatcher().firstMeetingURL(
            explicitURL: (event.hangoutLink ?? conferenceURL).flatMap(URL.init(string:)),
            location: event.location, notes: event.description) else { return nil }
        let externalID = "google:\(calendarID)|\(event.id)|\(start.timeIntervalSince1970)"
        let title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Meeting(id: MeetingStableIdentifier.uuid(for: externalID),
            title: title.isEmpty ? "İsimsiz Toplantı" : title, startDate: start, endDate: end,
            meetingURL: url, calendarIdentifier: "google:" + calendarID, externalIdentifier: externalID)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text)
    }

    private struct CalendarEntry: Decodable { let id: String; let summary: String?; let deleted: Bool? }
    private struct Page<Item: Decodable>: Decodable { let items: [Item]?; let nextPageToken: String? }
    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: TimeInterval
        let refresh_token: String?
    }
    private struct StoredToken: Codable {
        let accessToken: String
        let expiresAt: Date
        let refreshToken: String
    }

    private func accessToken() async throws -> String {
        let revision = generation
        guard let value = try await keys.apiKey(),
              let token = try? JSONDecoder().decode(StoredToken.self, from: Data(value.utf8)) else {
            throw GoogleCalendarError.authorization
        }
        if token.expiresAt.timeIntervalSinceNow > 60 { return token.accessToken }
        let response = try await exchange(["grant_type": "refresh_token", "refresh_token": token.refreshToken])
        guard revision == generation else { throw GoogleCalendarError.cancelled }
        try await save(response, oldRefreshToken: token.refreshToken)
        return response.access_token
    }

    private func save(_ response: TokenResponse, oldRefreshToken: String?) async throws {
        guard let refresh = response.refresh_token ?? oldRefreshToken, !refresh.isEmpty,
              !response.access_token.isEmpty, response.expires_in > 0 else { throw GoogleCalendarError.invalidResponse }
        let stored = StoredToken(accessToken: response.access_token,
            expiresAt: Date().addingTimeInterval(response.expires_in), refreshToken: refresh)
        try await keys.saveAPIKey(String(decoding: JSONEncoder().encode(stored), as: UTF8.self))
    }

    private func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var fields = fields
        fields["client_id"] = configuration.clientID
        if !configuration.clientSecret.isEmpty { fields["client_secret"] = configuration.clientSecret }
        var components = URLComponents()
        components.queryItems = fields.sorted(by: { $0.key < $1.key }).map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let response = try await http.data(for: request)
        guard (200...299).contains(response.response.statusCode) else { throw GoogleCalendarError.authorization }
        do { return try JSONDecoder().decode(TokenResponse.self, from: response.data) }
        catch { throw GoogleCalendarError.invalidResponse }
    }

    private func pages<Item: Decodable>(path: String, query: [URLQueryItem], token: String) async throws -> [Item] {
        var all: [Item] = []
        var pageToken: String?
        for _ in 0..<40 {
            var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/" + path)!
            url.queryItems = query + (pageToken.map { [.init(name: "pageToken", value: $0)] } ?? [])
            var request = URLRequest(url: url.url!, timeoutInterval: 30)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let response = try await http.data(for: request)
            switch response.response.statusCode {
            case 200...299: break
            case 401, 403: throw GoogleCalendarError.authorization
            default: throw GoogleCalendarError.unavailable
            }
            let page: Page<Item>
            do { page = try JSONDecoder().decode(Page<Item>.self, from: response.data) }
            catch { throw GoogleCalendarError.invalidResponse }
            all += page.items ?? []
            guard let next = page.nextPageToken, !next.isEmpty else { return all }
            pageToken = next
        }
        throw GoogleCalendarError.invalidResponse
    }
}

enum CalendarConnectionKind: String, Codable, Sendable { case macOS, google }

actor CalendarProviderRouter: CalendarMeetingProviding {
    private let local: any CalendarMeetingProviding
    private let google: any CalendarMeetingProviding
    private var kind = CalendarConnectionKind.macOS
    init(local: any CalendarMeetingProviding = EventKitMeetingProvider(), google: any CalendarMeetingProviding) {
        self.local = local; self.google = google
    }
    func selectSource(_ kind: CalendarConnectionKind) async { self.kind = kind }
    private var provider: any CalendarMeetingProviding { kind == .google ? google : local }
    func selectCalendars(_ ids: [String]?) async { await provider.selectCalendars(ids) }
    func authorizationState() async -> CalendarAccessState { await provider.authorizationState() }
    func requestAccess() async throws -> Bool { try await provider.requestAccess() }
    func query(from startDate: Date, to endDate: Date) async throws -> CalendarMeetingQueryResult {
        try await provider.query(from: startDate, to: endDate)
    }
}
