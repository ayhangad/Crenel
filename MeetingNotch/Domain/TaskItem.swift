import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case backlog
    case todo
    case inProgress
    case completed
    case blocked

    var id: Self { self }

    static let activeCases: [TaskStatus] = [.backlog, .todo, .inProgress, .blocked]

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .blocked: "Blocked"
        }
    }
}

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    static let maximumTitleLength = 500

    let id: UUID
    var title: String
    let createdAt: Date
    private(set) var status: TaskStatus
    private(set) var completedAt: Date?
    private(set) var archivedAt: Date?
    var assignee: String?
    var dueDate: Date?
    var sourceMeetingID: UUID?
    var sourceActionID: UUID?
    var sourceTime: TimeInterval?
    var sourceSpeakerID: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        status: TaskStatus = .backlog,
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        assignee: String? = nil,
        dueDate: Date? = nil,
        sourceMeetingID: UUID? = nil,
        sourceActionID: UUID? = nil,
        sourceTime: TimeInterval? = nil,
        sourceSpeakerID: String? = nil
    ) {
        self.id = id
        self.assignee = assignee
        self.dueDate = dueDate
        self.sourceMeetingID = sourceMeetingID
        self.sourceActionID = sourceActionID
        self.sourceTime = sourceTime
        self.sourceSpeakerID = sourceSpeakerID
        self.title = title
        self.createdAt = createdAt
        self.status = completedAt == nil ? status : .completed
        self.completedAt = status == .completed ? (completedAt ?? createdAt) : completedAt
        self.archivedAt = self.status == .completed
            ? (archivedAt ?? self.completedAt ?? createdAt)
            : archivedAt
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    mutating func setStatus(_ newStatus: TaskStatus, at date: Date = Date()) {
        status = newStatus
        if newStatus == .completed {
            completedAt = date
            archivedAt = archivedAt ?? date
        } else {
            completedAt = nil
        }
    }

    mutating func archive(at date: Date = Date()) {
        archivedAt = date
    }

    mutating func restore() {
        archivedAt = nil
        if status == .completed {
            status = .todo
            completedAt = nil
        }
    }

    static func normalizedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumTitleLength))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case status
        case completedAt
        case assignee, dueDate, sourceMeetingID, sourceActionID, sourceTime, sourceSpeakerID
        case archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        sourceMeetingID = try container.decodeIfPresent(UUID.self, forKey: .sourceMeetingID)
        sourceActionID = try container.decodeIfPresent(UUID.self, forKey: .sourceActionID)
        sourceTime = try container.decodeIfPresent(TimeInterval.self, forKey: .sourceTime)
        sourceSpeakerID = try container.decodeIfPresent(String.self, forKey: .sourceSpeakerID)
        let legacyCompletedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decodeIfPresent(TaskStatus.self, forKey: .status)
            ?? (legacyCompletedAt == nil ? .backlog : .completed)
        completedAt = status == .completed ? (legacyCompletedAt ?? createdAt) : nil
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        if status == .completed, archivedAt == nil {
            archivedAt = completedAt ?? createdAt
        }
    }
}
