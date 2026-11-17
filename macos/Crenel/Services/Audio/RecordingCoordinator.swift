import Foundation

@MainActor
final class RecordingCoordinator {
    typealias SystemAudioFactory = (SystemAudioCaptureScope) -> any AudioCaptureSource
    typealias MicrophoneFactory = (String?) -> any AudioCaptureSource
    typealias AvailableCapacityProvider = (URL) -> Int64?

    var onStatusChange: ((RecordingCaptureStatus) -> Void)?
    var onSourceConnectionChange: ((AudioSourceKind, AudioSourceConnectionState) -> Void)?
    var onMicrophoneGateChange: ((MeetingMicrophoneGate) -> Void)?
    var onSafetyInterruption: ((RecordingCaptureError) -> Void)?

    private let microphoneFactory: MicrophoneFactory
    private let systemAudioFactory: SystemAudioFactory
    private let fileManager: FileManager
    private let minimumFreeDiskSpace: Int64
    private let storageRoot: URL?
    private let mixer: any AudioTrackMixing
    private let availableCapacityProvider: AvailableCapacityProvider
    private let storageSafetyCheckInterval: Duration

    private var microphone: (any AudioCaptureSource)?
    private var systemAudio: (any AudioCaptureSource)?
    private var session: RecordingSession?
    private var sessionDirectory: URL?
    private var systemAudioScope: SystemAudioCaptureScope?
    private var microphoneGate: MeetingMicrophoneGate?
    private var status = RecordingCaptureStatus.idle
    private var storageSafetyTask: Task<Void, Never>?

    init(
        microphoneFactory: @escaping MicrophoneFactory = { MicrophoneCaptureSource(selectedDeviceID: $0) },
        systemAudioFactory: @escaping SystemAudioFactory = { SystemAudioCaptureSource(scope: $0) },
        fileManager: FileManager = .default,
        minimumFreeDiskSpace: Int64 = 500 * 1_024 * 1_024,
        storageRoot: URL? = nil,
        mixer: (any AudioTrackMixing)? = nil,
        availableCapacityProvider: AvailableCapacityProvider? = nil,
        storageSafetyCheckInterval: Duration = .seconds(30)
    ) {
        self.microphoneFactory = microphoneFactory
        self.systemAudioFactory = systemAudioFactory
        self.fileManager = fileManager
        self.minimumFreeDiskSpace = minimumFreeDiskSpace
        self.storageRoot = storageRoot
        self.mixer = mixer ?? AudioTrackMixer()
        self.availableCapacityProvider = availableCapacityProvider ?? { url in
            try? url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
        self.storageSafetyCheckInterval = storageSafetyCheckInterval
    }

    func start(
        meeting: Meeting?,
        microphoneDeviceID: String? = nil,
        systemAudioScope: SystemAudioCaptureScope
    ) async throws -> RecordingSession {
        guard session == nil else { throw RecordingCaptureError.alreadyRecording }

        let startedAt = Date()
        let microphoneGate = MeetingMicrophoneGate(recordingStartedAt: startedAt)
        let session = RecordingSession(
            meetingID: meeting?.id,
            sourceMeeting: meeting,
            startedAt: startedAt,
            microphoneGateEvents: microphoneGate.events
        )
        let directory = try makeSessionDirectory(sessionID: session.id)
        do {
            try verifyDiskSpace(at: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }

        let microphone = microphoneFactory(microphoneDeviceID)
        let systemAudio = systemAudioFactory(systemAudioScope)
        bindLevelUpdates(microphone: microphone, systemAudio: systemAudio)

        self.session = session
        sessionDirectory = directory
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.systemAudioScope = systemAudioScope
        self.microphoneGate = microphoneGate
        publishMicrophoneGate(microphoneGate)

        do {
            try await microphone.prepare(outputURL: directory.appending(path: "microphone.m4a"))
            try Task.checkCancellation()
            try await systemAudio.prepare(outputURL: directory.appending(path: "system-audio.m4a"))
            try Task.checkCancellation()

            try await microphone.start()
            updateReady(.microphone, isReady: true)
            try await systemAudio.start()
            updateReady(.systemAudio, isReady: true)

            try persist(session, to: directory.appending(path: "session.json"))
            startStorageSafetyMonitoring()
            return session
        } catch {
            await cancel()
            throw error
        }
    }

    func stop() async throws -> RecordingCaptureResult {
        guard let session, let microphone, let systemAudio, let directory = sessionDirectory else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "No recording in progress.")
        }
        stopStorageSafetyMonitoring()

        let tracks: [CapturedAudioTrack]
        do {
            async let microphoneTrack = microphone.stop()
            async let systemAudioTrack = systemAudio.stop()
            tracks = try await [microphoneTrack, systemAudioTrack]
        } catch {
            reset()
            throw error
        }

        var completedSession = session
        completedSession.endedAt = Date()
        completedSession.microphoneGateEvents = microphoneGate?.events ?? []
        do {
            completedSession.audioFileURL = try await mixer.mix(
                tracks: tracks,
                outputURL: directory.appending(path: "recording.m4a")
            )
        } catch {
            let recoveryResult = RecordingCaptureResult(session: completedSession, tracks: tracks)
            try? persist(recoveryResult, to: directory.appending(path: "capture.json"))
            reset()
            throw error
        }
        let result = RecordingCaptureResult(session: completedSession, tracks: tracks)
        try persist(result, to: directory.appending(path: "capture.json"))
        reset()
        return result
    }

    func cancel() async {
        stopStorageSafetyMonitoring()
        await microphone?.cancel()
        await systemAudio?.cancel()
        if let sessionDirectory {
            try? fileManager.removeItem(at: sessionDirectory)
        }
        reset()
    }

    func updateMicrophoneGate(
        from snapshot: MeetingSessionDetectionSnapshot,
        at timestamp: Date = Date()
    ) {
        guard var gate = microphoneGate else { return }

        if case .meetingProcesses(let objectIDs) = systemAudioScope,
           !objectIDs.contains(snapshot.audioProcess?.audioObjectID ?? 0) {
            if gate.meetingProcessChanged(at: timestamp) != nil {
                microphoneGate = gate
                publishMicrophoneGate(gate)
            }
            return
        }

        guard let client = snapshot.client,
              client.availability == .available else {
            if gate.adapterBecameUnavailable(at: timestamp) != nil {
                microphoneGate = gate
                publishMicrophoneGate(gate)
            }
            return
        }

        let confidence: DetectionConfidence = client.callControlsPresent
            ? .confirmed
            : .unknown
        if gate.observeClientState(
            client.microphoneState,
            confidence: confidence,
            at: timestamp
        ) != nil {
            microphoneGate = gate
            publishMicrophoneGate(gate)
        }
    }

    func setManualMicrophoneState(
        _ state: MeetingMicrophoneState,
        at timestamp: Date = Date()
    ) {
        guard var gate = microphoneGate,
              gate.setManualState(state, at: timestamp) != nil else { return }
        microphoneGate = gate
        publishMicrophoneGate(gate)
    }

    func failClosedForSystemInterruption(at timestamp: Date = Date()) {
        guard var gate = microphoneGate,
              gate.systemWasInterrupted(at: timestamp) != nil else { return }
        microphoneGate = gate
        publishMicrophoneGate(gate)
    }

    private func makeSessionDirectory(sessionID: UUID) throws -> URL {
        let applicationSupport = try storageRoot ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let temporaryRoot = applicationSupport
            .appending(path: "Crenel", directoryHint: .isDirectory)
            .appending(path: "Temporary", directoryHint: .isDirectory)
        let directory = temporaryRoot.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func verifyDiskSpace(at url: URL) throws {
        if let capacity = availableCapacityProvider(url),
           capacity < minimumFreeDiskSpace {
            throw RecordingCaptureError.insufficientDiskSpace
        }
    }

    func currentStorageSafetyIssue() -> RecordingCaptureError? {
        guard let sessionDirectory else { return nil }
        do {
            try verifyDiskSpace(at: sessionDirectory)
            return nil
        } catch let error as RecordingCaptureError {
            return error == .insufficientDiskSpace ? .diskSpaceBecameLow : error
        } catch {
            return .diskSpaceBecameLow
        }
    }

    private func startStorageSafetyMonitoring() {
        stopStorageSafetyMonitoring()
        let interval = storageSafetyCheckInterval
        storageSafetyTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self,
                      let issue = self.currentStorageSafetyIssue() else { continue }
                self.onSafetyInterruption?(issue)
                return
            }
        }
    }

    private func stopStorageSafetyMonitoring() {
        storageSafetyTask?.cancel()
        storageSafetyTask = nil
    }

    private func bindLevelUpdates(
        microphone: any AudioCaptureSource,
        systemAudio: any AudioCaptureSource
    ) {
        microphone.onLevelChange = { [weak self] level in
            Task { @MainActor in self?.updateLevel(.microphone, level: level) }
        }
        systemAudio.onLevelChange = { [weak self] level in
            Task { @MainActor in self?.updateLevel(.systemAudio, level: level) }
        }
        microphone.onConnectionStateChange = { [weak self] connectionState in
            Task { @MainActor in
                self?.updateConnectionState(.microphone, connectionState: connectionState)
            }
        }
        systemAudio.onConnectionStateChange = { [weak self] connectionState in
            Task { @MainActor in
                self?.updateConnectionState(.systemAudio, connectionState: connectionState)
            }
        }
    }

    private func updateReady(_ source: AudioSourceKind, isReady: Bool) {
        switch source {
        case .microphone:
            if !status.microphone.connectionState.needsAttention {
                status.microphone.connectionState = isReady ? .ready : .preparing
            }
        case .systemAudio:
            if !status.systemAudio.connectionState.needsAttention {
                status.systemAudio.connectionState = isReady ? .ready : .preparing
            }
        }
        onStatusChange?(status)
    }

    private func updateConnectionState(
        _ source: AudioSourceKind,
        connectionState: AudioSourceConnectionState
    ) {
        switch source {
        case .microphone: status.microphone.connectionState = connectionState
        case .systemAudio: status.systemAudio.connectionState = connectionState
        }
        onStatusChange?(status)
        onSourceConnectionChange?(source, connectionState)
    }

    private func updateLevel(_ source: AudioSourceKind, level: Float) {
        switch source {
        case .microphone: status.microphone.level = level
        case .systemAudio: status.systemAudio.level = level
        }
        onStatusChange?(status)
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func publishMicrophoneGate(_ gate: MeetingMicrophoneGate) {
        (microphone as? any MeetingMicrophoneGateUpdating)?.updateMicrophoneGate(gate)
        onMicrophoneGateChange?(gate)
    }

    private func reset() {
        stopStorageSafetyMonitoring()
        microphone = nil
        systemAudio = nil
        session = nil
        sessionDirectory = nil
        systemAudioScope = nil
        microphoneGate = nil
        status = .idle
        onStatusChange?(status)
    }
}
