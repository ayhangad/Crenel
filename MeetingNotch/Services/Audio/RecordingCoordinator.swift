import Foundation

@MainActor
final class RecordingCoordinator {
    typealias SourceFactory = () -> any AudioCaptureSource

    var onStatusChange: ((RecordingCaptureStatus) -> Void)?

    private let microphoneFactory: SourceFactory
    private let systemAudioFactory: SourceFactory
    private let fileManager: FileManager
    private let minimumFreeDiskSpace: Int64
    private let storageRoot: URL?
    private let mixer: any AudioTrackMixing

    private var microphone: (any AudioCaptureSource)?
    private var systemAudio: (any AudioCaptureSource)?
    private var session: RecordingSession?
    private var sessionDirectory: URL?
    private var status = RecordingCaptureStatus.idle

    init(
        microphoneFactory: @escaping SourceFactory = { MicrophoneCaptureSource() },
        systemAudioFactory: @escaping SourceFactory = { SystemAudioCaptureSource() },
        fileManager: FileManager = .default,
        minimumFreeDiskSpace: Int64 = 500 * 1_024 * 1_024,
        storageRoot: URL? = nil,
        mixer: (any AudioTrackMixing)? = nil
    ) {
        self.microphoneFactory = microphoneFactory
        self.systemAudioFactory = systemAudioFactory
        self.fileManager = fileManager
        self.minimumFreeDiskSpace = minimumFreeDiskSpace
        self.storageRoot = storageRoot
        self.mixer = mixer ?? AudioTrackMixer()
    }

    func start(meeting: Meeting?) async throws -> RecordingSession {
        guard session == nil else { throw RecordingCaptureError.alreadyRecording }

        let session = RecordingSession(
            meetingID: meeting?.id,
            sourceMeeting: meeting,
            startedAt: Date()
        )
        let directory = try makeSessionDirectory(sessionID: session.id)
        try verifyDiskSpace(at: directory)

        let microphone = microphoneFactory()
        let systemAudio = systemAudioFactory()
        bindLevelUpdates(microphone: microphone, systemAudio: systemAudio)

        self.session = session
        sessionDirectory = directory
        self.microphone = microphone
        self.systemAudio = systemAudio

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
            return session
        } catch {
            await cancel()
            throw error
        }
    }

    func stop() async throws -> RecordingCaptureResult {
        guard let session, let microphone, let systemAudio, let directory = sessionDirectory else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Devam eden kayıt yok.")
        }

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
        await microphone?.cancel()
        await systemAudio?.cancel()
        if let sessionDirectory {
            try? fileManager.removeItem(at: sessionDirectory)
        }
        reset()
    }

    private func makeSessionDirectory(sessionID: UUID) throws -> URL {
        let applicationSupport = try storageRoot ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let temporaryRoot = applicationSupport
            .appending(path: "MeetingNotch", directoryHint: .isDirectory)
            .appending(path: "Temporary", directoryHint: .isDirectory)
        let directory = temporaryRoot.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func verifyDiskSpace(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage,
           capacity < minimumFreeDiskSpace {
            throw RecordingCaptureError.insufficientDiskSpace
        }
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
    }

    private func updateReady(_ source: AudioSourceKind, isReady: Bool) {
        switch source {
        case .microphone: status.microphone.isReady = isReady
        case .systemAudio: status.systemAudio.isReady = isReady
        }
        onStatusChange?(status)
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

    private func reset() {
        microphone = nil
        systemAudio = nil
        session = nil
        sessionDirectory = nil
        status = .idle
        onStatusChange?(status)
    }
}
