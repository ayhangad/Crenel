import Foundation

struct ProcessingJob: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case queued
        case running
        case failed
    }

    enum FailureKind: String, Codable, Equatable, Sendable {
        case authentication
        case settingsUnavailable
        case rateLimited
        case timeout
        case networkUnavailable
        case providerUnavailable
        case invalidFile
        case invalidResponse
        case unsupportedFeature
        case cancelled
    }

    let id: UUID
    let meetingID: UUID
    let idempotencyKey: UUID
    let createdAt: Date
    var updatedAt: Date
    var state: State
    var attemptCount: Int
    var nextAttemptAt: Date?
    var lastFailure: FailureKind?

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        idempotencyKey: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        state: State = .queued,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastFailure: FailureKind? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.state = state
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastFailure = lastFailure
    }
}

extension ProcessingJob.FailureKind {
    init(_ error: TranscriptionServiceError) {
        switch error {
        case .settingsUnavailable: self = .settingsUnavailable
        case .authentication: self = .authentication
        case .rateLimited: self = .rateLimited
        case .timeout: self = .timeout
        case .networkUnavailable: self = .networkUnavailable
        case .providerUnavailable: self = .providerUnavailable
        case .invalidFile: self = .invalidFile
        case .invalidResponse: self = .invalidResponse
        case .unsupportedFeature: self = .unsupportedFeature
        case .cancelled: self = .cancelled
        }
    }
}
