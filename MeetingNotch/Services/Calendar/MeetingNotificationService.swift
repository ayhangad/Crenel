import AppKit
import UserNotifications

struct MeetingNotificationPlan: Equatable {
    let id: String
    let meeting: Meeting
    let date: Date

    static func make(meetings: [Meeting], leadTime: TimeInterval, now: Date) -> [Self] {
        meetings.filter { $0.endDate > now }.flatMap { meeting in
            Set([max(60, leadTime), 60]).compactMap { offset -> Self? in
                let date = meeting.startDate.addingTimeInterval(-offset)
                guard date > now, meeting.meetingURL != nil else { return nil }
                let id = "meeting.\(meeting.id).\(Int(meeting.startDate.timeIntervalSince1970)).\(Int(offset))"
                return Self(id: id, meeting: meeting, date: date)
            }
        }.sorted { $0.date < $1.date }.prefix(60).map { $0 }
    }
}

@MainActor
final class MeetingNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "Checking notification access"
    private let center = UNUserNotificationCenter.current()
    private var meetings: [Meeting] = []
    private var leadTime: TimeInterval = 600
    private var enabled = true
    private var generation = 0
    private var syncTask: Task<Void, Never>?
    var onOpenMeeting: ((URL) -> Void)?

    override init() {
        super.init()
        center.delegate = self
        let join = UNNotificationAction(identifier: "join", title: "Join meeting", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze 5 min", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "meeting", actions: [join, snooze], intentIdentifiers: [])])
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: status = "Notifications on"
        case .denied: status = "Notifications are off in System Settings"
        case .notDetermined: status = "Notification access needed"
        default: status = "Notifications unavailable"
        }
    }

    func requestAccess() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { status = "Couldn’t get notification access"; return }
        await refreshStatus()
        update(meetings: meetings, leadTime: leadTime, enabled: enabled)
    }

    func update(meetings: [Meeting], leadTime: TimeInterval, enabled: Bool) {
        self.meetings = meetings; self.leadTime = leadTime; self.enabled = enabled
        generation += 1
        let current = generation
        // Serialize mutation of system requests; a stale sync is followed by the latest plan.
        let preceding = syncTask
        syncTask = Task { [weak self] in
            await preceding?.value
            guard let self, self.generation == current else { return }
            await self.synchronize(generation: current)
        }
    }

    private func synchronize(generation: Int) async {
        let plans = enabled ? MeetingNotificationPlan.make(meetings: meetings, leadTime: leadTime, now: Date()) : []
        let pending = await center.pendingNotificationRequests()
        guard self.generation == generation else { return }
        let desired = Set(plans.map(\.id))
        let validMeetingIDs = Set(enabled ? meetings.map { $0.id.uuidString } : [])
        let obsolete = pending.filter {
            guard $0.identifier.hasPrefix("meeting.") else { return false }
            if $0.identifier.hasSuffix(".snooze") {
                return !validMeetingIDs.contains($0.content.userInfo["meetingID"] as? String ?? "")
            }
            return !desired.contains($0.identifier)
        }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let settings = await center.notificationSettings()
        guard self.generation == generation,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        for plan in plans {
            guard self.generation == generation else { return }
            if let old = existing[plan.id], old.content.title == plan.meeting.title,
               old.content.userInfo["url"] as? String == plan.meeting.meetingURL?.absoluteString { continue }
            let content = UNMutableNotificationContent()
            content.title = plan.meeting.title
            content.body = "Starts at \(plan.meeting.startDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale)))."
            content.categoryIdentifier = "meeting"
            content.sound = .default
            content.userInfo = ["url": plan.meeting.meetingURL?.absoluteString ?? "", "meetingID": plan.meeting.id.uuidString]
            let interval = plan.date.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let request = UNNotificationRequest(identifier: plan.id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
            do { try await center.add(request) }
            catch { status = "Couldn’t schedule meeting notification" }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self else { return }
            if response.actionIdentifier == "snooze" {
                let id = response.notification.request.content.userInfo["meetingID"] as? String ?? ""
                guard self.enabled, self.meetings.contains(where: { $0.id.uuidString == id && $0.endDate > Date() }) else { return }
                let request = UNNotificationRequest(identifier: "meeting.\(id).snooze",
                    content: response.notification.request.content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false))
                try? await center.add(request)
            } else if response.actionIdentifier == "join" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                guard let raw = response.notification.request.content.userInfo["url"] as? String,
                      let url = MeetingURLMatcher().firstMeetingURL(explicitURL: URL(string: raw), location: nil, notes: nil) else { return }
                self.onOpenMeeting?(url)
            }
        }
    }
}
