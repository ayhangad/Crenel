import EventKit
import Foundation

@MainActor
final class MeetingMonitor {
    var onAccessStateChange: ((CalendarAccessState) -> Void)?
    var onSnapshotChange: ((MeetingReminderSnapshot, Bool) -> Void)?
    var onMeetingsChange: (([Meeting]) -> Void)?
    var onIntegrationSnapshotChange: ((CalendarIntegrationSnapshot?) -> Void)?
    var onRefreshStateChange: ((Bool) -> Void)?

    private let provider: any CalendarMeetingProviding
    private let refreshInterval: TimeInterval
    private let now: () -> Date
    private var isEnabled = true
    private var selectedCalendarIDs: [String]?
    private var configurationVersion = 0
    private var reminderLeadTime: TimeInterval
    private var pollingTask: Task<Void, Never>?
    private var calendarChangeTask: Task<Void, Never>?
    private var timeZoneChangeTask: Task<Void, Never>?
    private var lastPresentationKey: String?
    private var isRefreshing = false
    private var refreshRequestedWhileRunning = false

    init(
        provider: any CalendarMeetingProviding,
        refreshInterval: TimeInterval = 30,
        reminderLeadTime: TimeInterval = 10 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.refreshInterval = refreshInterval
        self.reminderLeadTime = reminderLeadTime
        self.now = now
    }

    func configure(isEnabled: Bool, reminderLeadTime: TimeInterval, selectedCalendarIDs: [String]? = nil) {
        configurationVersion += 1
        self.selectedCalendarIDs = selectedCalendarIDs
        self.isEnabled = isEnabled
        self.reminderLeadTime = max(60, reminderLeadTime)
        if isEnabled {
            start()
            Task { await refresh() }
        } else {
            stop()
            onAccessStateChange?(.notDetermined)
            onIntegrationSnapshotChange?(nil)
            onMeetingsChange?([])
            publish(MeetingReminderSnapshot(nextMeeting: nil, level: .none, secondsUntilStart: nil))
        }
    }

    func start() {
        guard isEnabled, pollingTask == nil else { return }

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

    /// How far ahead the agenda reads. A day was too short: with nothing in the next
    /// 24 hours the notch looked disconnected even though access was fine.
    static let agendaHorizon: TimeInterval = 7 * 24 * 60 * 60

    func requestAccess() async {
        onAccessStateChange?(.requesting)

        do {
            let granted = try await provider.requestAccess()
            onAccessStateChange?(granted ? .authorized : .denied)
            if granted, isEnabled {
                await refresh()
            }
        } catch {
            onAccessStateChange?(.failed("Couldn’t request calendar access."))
        }
    }

    func refresh() async {
        guard isEnabled else { return }
        guard !isRefreshing else {
            refreshRequestedWhileRunning = true
            return
        }
        isRefreshing = true
        onRefreshStateChange?(true)
        defer {
            isRefreshing = false
            onRefreshStateChange?(false)
            if refreshRequestedWhileRunning {
                refreshRequestedWhileRunning = false
                Task { [weak self] in await self?.refresh() }
            }
        }

        let version = configurationVersion
        await provider.selectCalendars(selectedCalendarIDs)
        let accessState = await provider.authorizationState()
        guard isEnabled, version == configurationVersion else { return }
        onAccessStateChange?(accessState)

        guard accessState == .authorized else {
            onIntegrationSnapshotChange?(nil)
            onMeetingsChange?([])
            publish(MeetingReminderSnapshot(nextMeeting: nil, level: .none, secondsUntilStart: nil))
            return
        }

        let currentDate = now()
        do {
            let result = try await provider.query(
                from: currentDate.addingTimeInterval(-60 * 60),
                to: currentDate.addingTimeInterval(Self.agendaHorizon)
            )
            guard isEnabled, version == configurationVersion else { return }
            onIntegrationSnapshotChange?(CalendarIntegrationSnapshot(
                sources: result.sources,
                scannedEventCount: result.scannedEventCount,
                matchedMeetingCount: result.meetings.count,
                refreshedAt: currentDate,
                calendars: result.calendars
            ))
            onMeetingsChange?(result.meetings.filter { $0.endDate > currentDate })
            // Recording offers and reminders are for meetings; personal events and
            // all-day items only appear in the agenda and the notch countdown.
            publish(.evaluate(
                meetings: result.meetings.filter(\.isReminderCandidate),
                now: currentDate,
                reminderLeadTime: reminderLeadTime
            ))
        } catch {
            guard isEnabled, version == configurationVersion else { return }
            onIntegrationSnapshotChange?(nil)
            onAccessStateChange?(.failed("Couldn’t read upcoming events."))
            onMeetingsChange?([])
            publish(MeetingReminderSnapshot(nextMeeting: nil, level: .none, secondsUntilStart: nil))
        }
    }

    private func publish(_ snapshot: MeetingReminderSnapshot) {
        let newKey = snapshot.presentationKey
        let shouldPresent = newKey != nil && newKey != lastPresentationKey
        lastPresentationKey = newKey
        onSnapshotChange?(snapshot, shouldPresent)
    }
}
