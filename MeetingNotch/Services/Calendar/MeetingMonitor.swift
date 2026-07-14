import EventKit
import Foundation

@MainActor
final class MeetingMonitor {
    var onAccessStateChange: ((CalendarAccessState) -> Void)?
    var onSnapshotChange: ((MeetingReminderSnapshot, Bool) -> Void)?

    private let provider: any CalendarMeetingProviding
    private let refreshInterval: TimeInterval
    private let now: () -> Date
    private var pollingTask: Task<Void, Never>?
    private var calendarChangeTask: Task<Void, Never>?
    private var timeZoneChangeTask: Task<Void, Never>?
    private var lastPresentationKey: String?

    init(
        provider: any CalendarMeetingProviding,
        refreshInterval: TimeInterval = 30,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.refreshInterval = refreshInterval
        self.now = now
    }

    func start() {
        guard pollingTask == nil else { return }

        calendarChangeTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .EKEventStoreChanged
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }

        timeZoneChangeTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .NSSystemTimeZoneDidChange
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.refreshInterval))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        calendarChangeTask?.cancel()
        timeZoneChangeTask?.cancel()
        pollingTask = nil
        calendarChangeTask = nil
        timeZoneChangeTask = nil
    }

    func requestAccess() async {
        onAccessStateChange?(.requesting)

        do {
            let granted = try await provider.requestAccess()
            onAccessStateChange?(granted ? .authorized : .denied)
            if granted {
                await refresh()
            }
        } catch {
            onAccessStateChange?(.failed("Takvim erişimi istenirken bir hata oluştu."))
        }
    }

    func refresh() async {
        let accessState = await provider.authorizationState()
        onAccessStateChange?(accessState)

        guard accessState == .authorized else {
            publish(MeetingReminderSnapshot(nextMeeting: nil, level: .none, secondsUntilStart: nil))
            return
        }

        let currentDate = now()
        do {
            let meetings = try await provider.meetings(
                from: currentDate.addingTimeInterval(-60 * 60),
                to: currentDate.addingTimeInterval(24 * 60 * 60)
            )
            publish(.evaluate(meetings: meetings, now: currentDate))
        } catch {
            onAccessStateChange?(.failed("Yaklaşan toplantılar okunamadı."))
        }
    }

    private func publish(_ snapshot: MeetingReminderSnapshot) {
        let newKey = snapshot.presentationKey
        let shouldPresent = newKey != nil && newKey != lastPresentationKey
        lastPresentationKey = newKey
        onSnapshotChange?(snapshot, shouldPresent)
    }
}
