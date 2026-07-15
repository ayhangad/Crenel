import Foundation

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    static let maximumTitleLength = 500

    let id: UUID
    var title: String
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var isArchived: Bool {
        completedAt != nil
    }

    static func normalizedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumTitleLength))
    }
}
