import EventKit
import Foundation

/// The authorization status Crenel trusts for calendars and reminders.
///
/// `EKEventStore.authorizationStatus(for:)` is cached for the life of the process. After a
/// grant (the system prompt or a switch in System Settings) it kept answering
/// `notDetermined`/`denied` until relaunch, so the app showed "Allow" while it already had
/// access, and a second request returned `true` without a prompt. Here a grant seen in this
/// process sticks, and when the cached status says no, a fresh store that can see lists
/// proves access.
enum EventKitAccess {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var grantedTypes: Set<UInt> = []
    nonisolated(unsafe) private static var lastProbe: [UInt: Date] = [:]
    /// A fresh store costs ~25 ms and setup polls every second; probe at most this often.
    static let probeInterval: TimeInterval = 10

    static func markGranted(_ type: EKEntityType) {
        lock.withLock { _ = grantedTypes.insert(type.rawValue) }
    }

    static func status(for type: EKEntityType) -> EKAuthorizationStatus {
        let cached = EKEventStore.authorizationStatus(for: type)
        if cached == .fullAccess || cached == .authorized || cached == .restricted {
            return cached
        }
        if lock.withLock({ grantedTypes.contains(type.rawValue) }) {
            return .fullAccess
        }
        // A store made now reads with the current grant even when the cached status is stale.
        let now = Date()
        let shouldProbe = lock.withLock { () -> Bool in
            if let last = lastProbe[type.rawValue], now.timeIntervalSince(last) < probeInterval { return false }
            lastProbe[type.rawValue] = now
            return true
        }
        if shouldProbe, !EKEventStore().calendars(for: type).isEmpty {
            markGranted(type)
            return .fullAccess
        }
        return cached
    }

    static func hasFullAccess(_ type: EKEntityType) -> Bool {
        let status = status(for: type)
        return status == .fullAccess || status == .authorized
    }
}
