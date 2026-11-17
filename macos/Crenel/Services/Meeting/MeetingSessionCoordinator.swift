import Foundation

struct MeetingSessionDetectionSnapshot: Equatable, Sendable {
    let session: MeetingSession
    let audioProcess: AudioProcessSnapshot?
    let client: MeetingClientSnapshot?

    var microphoneState: MeetingMicrophoneState {
        client?.microphoneState ?? .unknown
    }

    var adapterAvailability: MeetingClientAdapterAvailability? {
        client?.availability
    }
}

actor MeetingSessionCoordinator {
    typealias UpdateHandler = @Sendable (MeetingSessionDetectionSnapshot) async -> Void

    private struct Candidate: Sendable {
        let audioProcess: AudioProcessSnapshot
        let client: MeetingClientSnapshot
        let score: Int
    }

    private let audioProcessMonitor: any AudioProcessMonitoring
    private let clientAdapter: any MeetingClientAdapting
    private let processMatcher: MeetingClientProcessMatcher
    private var machine: MeetingSessionMachine
    private var calendarMeeting: Meeting?
    private var preferredClientID: MeetingClientID?
    private var activeAudioProcess: AudioProcessSnapshot?
    private var activeClientSnapshot: MeetingClientSnapshot?
    private var onUpdate: UpdateHandler?
    private var lastPublishedSnapshot: MeetingSessionDetectionSnapshot?

    init(
        audioProcessMonitor: any AudioProcessMonitoring = CoreAudioProcessMonitor(),
        clientAdapter: any MeetingClientAdapting = AccessibilityMeetingClientAdapter(),
        processMatcher: MeetingClientProcessMatcher = MeetingClientProcessMatcher(),
        initialSession: MeetingSession = MeetingSession()
    ) {
        self.audioProcessMonitor = audioProcessMonitor
        self.clientAdapter = clientAdapter
        self.processMatcher = processMatcher
        machine = MeetingSessionMachine(session: initialSession)
    }

    func start(onUpdate: @escaping UpdateHandler) async {
        self.onUpdate = onUpdate
        await audioProcessMonitor.start { [weak self] snapshots in
            await self?.ingestAudioProcessSnapshots(snapshots)
        }
        await publish(force: true)
    }

    func stop() async {
        await audioProcessMonitor.stop()
        onUpdate = nil
        lastPublishedSnapshot = nil
    }

    func refresh() async {
        await audioProcessMonitor.refresh()
    }

    func updateCalendarMeeting(_ meeting: Meeting?, at date: Date = Date()) async {
        let previousMeeting = calendarMeeting
        let previousIdentifier = previousMeeting.map(calendarIdentifier)
        let nextIdentifier = meeting.map(calendarIdentifier)

        if machine.session.state == .ended,
           let nextIdentifier,
           nextIdentifier != previousIdentifier {
            resetSession(at: date)
        }

        calendarMeeting = meeting
        if let url = meeting?.meetingURL {
            preferredClientID = clientID(for: url) ?? preferredClientID
        }

        if let meeting {
            machine.observe(
                .calendarContext(
                    meetingID: calendarIdentifier(for: meeting),
                    isWithinScheduledWindow: meeting.startDate...meeting.endDate ~= date
                ),
                at: date
            )
        } else if let previousMeeting {
            machine.observe(
                .calendarContext(
                    meetingID: calendarIdentifier(for: previousMeeting),
                    isWithinScheduledWindow: false
                ),
                at: date
            )
        }
        await publish()
    }

    func recordJoinAction(
        meeting: Meeting?,
        url: URL,
        at date: Date = Date()
    ) async {
        if machine.session.state == .ended {
            resetSession(at: date)
        }
        if let meeting {
            calendarMeeting = meeting
            machine.observe(
                .calendarContext(
                    meetingID: calendarIdentifier(for: meeting),
                    isWithinScheduledWindow: meeting.startDate...meeting.endDate ~= date
                ),
                at: date
            )
        }
        preferredClientID = clientID(for: url)
        machine.observe(.joinAction, at: date)
        await publish()
        await audioProcessMonitor.refresh()
    }

    func recordingStarted(at date: Date = Date()) async {
        if machine.session.state == .ended {
            resetSession(at: date)
        }
        machine.recordingStarted(at: date)
        await publish()
    }

    func recordingStopped(at date: Date = Date()) async {
        machine.recordingStopped(at: date)
        await publish()
    }

    private func ingestAudioProcessSnapshots(
        _ snapshots: [AudioProcessSnapshot],
        at date: Date = Date()
    ) async {
        let candidate = selectCandidate(from: snapshots)

        if machine.session.state == .ended,
           candidate?.client.meetingWindowPresent == true,
           candidate?.client.callControlsPresent == true {
            resetSession(at: date)
            if let calendarMeeting {
                machine.observe(
                    .calendarContext(
                        meetingID: calendarIdentifier(for: calendarMeeting),
                        isWithinScheduledWindow:
                            calendarMeeting.startDate...calendarMeeting.endDate ~= date
                    ),
                    at: date
                )
            }
        }

        guard let candidate else {
            if let previousProcess = activeAudioProcess {
                machine.observe(
                    .process(processID: previousProcess.processID, isRunning: false),
                    at: date
                )
                machine.observe(
                    .audioIO(
                        processID: previousProcess.processID,
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    at: date
                )
            }
            if let previousClient = activeClientSnapshot {
                machine.observe(
                    .clientUI(
                        clientID: previousClient.clientID,
                        meetingWindowPresent: false,
                        callControlsPresent: false
                    ),
                    at: date
                )
            }
            activeAudioProcess = nil
            activeClientSnapshot = nil
            await publish()
            return
        }

        activeAudioProcess = candidate.audioProcess
        activeClientSnapshot = candidate.client
        machine.observe(
            .process(processID: candidate.audioProcess.processID, isRunning: true),
            at: date
        )
        machine.observe(
            .audioIO(
                processID: candidate.audioProcess.processID,
                isRunningInput: candidate.audioProcess.isRunningInput,
                isRunningOutput: candidate.audioProcess.isRunningOutput
            ),
            at: date
        )
        machine.observe(candidate.client.evidence, at: date)
        await publish()
    }

    private func selectCandidate(
        from snapshots: [AudioProcessSnapshot]
    ) -> Candidate? {
        let existingProcessID = activeAudioProcess?.processID ?? machine.session.processID
        let uniqueProcesses = Dictionary(
            snapshots.compactMap { snapshot -> (Int32, AudioProcessSnapshot)? in
                guard processMatcher.clientID(
                    bundleIdentifier: snapshot.bundleIdentifier
                ) != nil else {
                    return nil
                }
                return (snapshot.processID, snapshot)
            },
            uniquingKeysWith: { lhs, rhs in
                if lhs.hasActiveIO != rhs.hasActiveIO {
                    return lhs.hasActiveIO ? lhs : rhs
                }
                return lhs.audioObjectID < rhs.audioObjectID ? lhs : rhs
            }
        ).values

        return uniqueProcesses.compactMap { process -> Candidate? in
            guard let clientID = processMatcher.clientID(
                bundleIdentifier: process.bundleIdentifier
            ),
            let client = clientAdapter.inspect(
                processID: process.processID,
                bundleIdentifier: process.bundleIdentifier,
                promptForAccessibility: false
            ) else {
                return nil
            }

            let isExistingProcess = process.processID == existingProcessID
            let isPreferredClient = clientID == preferredClientID
            let hasMeetingUI = client.meetingWindowPresent || client.callControlsPresent
            guard isExistingProcess || isPreferredClient || process.hasActiveIO || hasMeetingUI else {
                return nil
            }

            var score = 0
            if client.callControlsPresent { score += 10_000 }
            if client.meetingWindowPresent { score += 5_000 }
            if isExistingProcess { score += 1_000 }
            if isPreferredClient { score += 500 }
            if process.hasActiveIO { score += 100 }
            if clientID == .zoom { score += 1 }
            return Candidate(audioProcess: process, client: client, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.audioProcess.processID != rhs.audioProcess.processID {
                return lhs.audioProcess.processID < rhs.audioProcess.processID
            }
            return lhs.audioProcess.audioObjectID < rhs.audioProcess.audioObjectID
        }
        .first
    }

    private func resetSession(at date: Date) {
        machine = MeetingSessionMachine(
            session: MeetingSession(lastChangedAt: date)
        )
        activeAudioProcess = nil
        activeClientSnapshot = nil
        lastPublishedSnapshot = nil
    }

    private func calendarIdentifier(for meeting: Meeting) -> String {
        meeting.externalIdentifier ?? meeting.id.uuidString
    }

    private func clientID(for url: URL) -> MeetingClientID? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "meet.google.com" {
            return .googleMeetChrome
        }
        if host == "zoom.us"
            || host.hasSuffix(".zoom.us")
            || host == "zoomgov.com"
            || host.hasSuffix(".zoomgov.com") {
            return .zoom
        }
        return nil
    }

    private func publish(force: Bool = false) async {
        let snapshot = MeetingSessionDetectionSnapshot(
            session: machine.session,
            audioProcess: activeAudioProcess,
            client: activeClientSnapshot
        )
        guard force || snapshot != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = snapshot
        await onUpdate?(snapshot)
    }
}
