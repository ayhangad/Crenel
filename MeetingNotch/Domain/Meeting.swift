import Foundation

struct Meeting: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var meetingURL: URL?
    var calendarIdentifier: String?
    var externalIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        meetingURL: URL? = nil,
        calendarIdentifier: String? = nil,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.meetingURL = meetingURL
        self.calendarIdentifier = calendarIdentifier
        self.externalIdentifier = externalIdentifier
    }
}
