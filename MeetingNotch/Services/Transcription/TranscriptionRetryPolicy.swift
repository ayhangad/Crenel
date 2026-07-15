import Foundation

struct TranscriptionRetryPolicy: Sendable {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    let maximumAttempts: Int
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval

    init(
        maximumAttempts: Int = 3,
        baseDelay: TimeInterval = 1,
        maximumDelay: TimeInterval = 30
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(0, maximumDelay)
    }

    func execute<Value: Sendable>(
        sleeper: @escaping Sleeper = { delay in
            try await Task.sleep(for: .seconds(delay))
        },
        operation: @Sendable (Int) async throws -> Value
    ) async throws -> Value {
        var attempt = 1

        while true {
            try Task.checkCancellation()
            do {
                return try await operation(attempt)
            } catch {
                let normalized = TranscriptionErrorNormalizer.normalize(error)
                guard normalized.isRetryable, attempt < maximumAttempts else {
                    throw normalized
                }
                try Task.checkCancellation()
                try await sleeper(delay(after: normalized, failedAttempt: attempt))
                attempt += 1
            }
        }
    }

    func delay(
        after error: TranscriptionServiceError,
        failedAttempt: Int
    ) -> TimeInterval {
        if case .rateLimited(let retryAfter?) = error {
            return min(max(0, retryAfter), maximumDelay)
        }
        let exponential = baseDelay * pow(2, Double(max(0, failedAttempt - 1)))
        return min(exponential, maximumDelay)
    }
}
