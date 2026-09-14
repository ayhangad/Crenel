import Foundation

/// A later calendar event must never silently label an unrelated manual recording.
enum RecordingMeetingContext {
    static func resolve(meetings: [Meeting], session: MeetingSession?, now: Date) -> Meeting? {
        let candidates = meetings.filter {
            $0.startDate.addingTimeInterval(-15 * 60) <= now && $0.endDate >= now
        }.filter { meeting in
            guard let client = session?.clientID else { return true }
            let host = meeting.meetingURL?.host?.lowercased() ?? ""
            switch client {
            case .zoom: return host == "zoom.us" || host.hasSuffix(".zoom.us")
            case .googleMeetChrome: return host == "meet.google.com"
            case .unsupported: return true
            }
        }
        if let id = session?.calendarMeetingID,
           let matching = candidates.first(where: { ($0.externalIdentifier ?? $0.id.uuidString) == id }) {
            return matching
        }
        // Ambiguous overlapping meetings remain unnamed until analysis/user context resolves them.
        return candidates.count == 1 ? candidates.first : nil
    }
}
