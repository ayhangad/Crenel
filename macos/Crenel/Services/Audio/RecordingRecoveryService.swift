@preconcurrency import AVFoundation
import Foundation

actor RecordingRecoveryService {
    typealias DurationLoader = @Sendable (URL) async throws -> TimeInterval

    private let fileManager: FileManager
    private let layout: AppStorageLayout
    private let repository: any MeetingRepository
    private let mixer: any AudioTrackMixing
    private let durationLoader: DurationLoader
    private let decoder: JSONDecoder

    init(
        repository: any MeetingRepository,
        mixer: any AudioTrackMixing = AudioTrackMixer(),
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        durationLoader: DurationLoader? = nil
    ) {
        self.repository = repository
        self.mixer = mixer
        self.fileManager = fileManager

        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        layout = AppStorageLayout(
            root: rootURL ?? defaultRoot.appending(path: "Crenel", directoryHint: .isDirectory)
        )
        self.durationLoader = durationLoader ?? { url in
            try await RecordingRecoveryService.loadDuration(from: url)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func recoverInterruptedCaptures() async -> RecordingRecoveryReport {
        do {
            try layout.createDirectories(fileManager: fileManager)
            try await repository.prepare()
        } catch {
            AppLogger.persistenceFailed(
                operation: "prepare-recording-recovery",
                error: error
            )
            return .empty
        }

        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: layout.temporary,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            AppLogger.persistenceFailed(
                operation: "scan-recording-recovery",
                error: error
            )
            return .empty
        }

        var recoveredMeetings: [StoredMeeting] = []
        var preservedCount = 0

        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            do {
                let capture = try await reconstructCapture(in: directory)
                let meeting = try await repository.saveCapture(capture)
                recoveredMeetings.append(meeting)
            } catch {
                preservedCount += 1
                preserveForManualRecovery(directory)
                AppLogger.persistenceFailed(
                    operation: "recover-interrupted-recording",
                    error: error
                )
            }
        }

        return RecordingRecoveryReport(
            recoveredMeetings: recoveredMeetings.sorted { $0.startedAt > $1.startedAt },
            preservedCount: preservedCount
        )
    }

    private func reconstructCapture(in directory: URL) async throws -> RecordingCaptureResult {
        guard let directoryID = UUID(uuidString: directory.lastPathComponent) else {
            throw RecoveryError.invalidSessionDirectory
        }

        let manifestURL = directory.appending(path: "capture.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            let capture = try decoder.decode(
                RecordingCaptureResult.self,
                from: Data(contentsOf: manifestURL)
            )
            guard capture.session.id == directoryID else {
                throw RecoveryError.sessionIdentityMismatch
            }
            return try await rebuild(
                capture: capture,
                in: directory,
                trustExistingRecording: capture.session.audioFileURL != nil
            )
        }

        let sessionURL = directory.appending(path: "session.json")
        let session = try decoder.decode(
            RecordingSession.self,
            from: Data(contentsOf: sessionURL)
        )
        guard session.id == directoryID else {
            throw RecoveryError.sessionIdentityMismatch
        }

        return try await rebuild(
            capture: RecordingCaptureResult(
                session: session,
                tracks: tracks(in: directory, originalTracks: [])
            ),
            in: directory,
            trustExistingRecording: false
        )
    }

    private func rebuild(
        capture: RecordingCaptureResult,
        in directory: URL,
        trustExistingRecording: Bool
    ) async throws -> RecordingCaptureResult {
        let tracks = tracks(in: directory, originalTracks: capture.tracks)
        var session = capture.session
        let recordingURL = directory.appending(path: "recording.m4a")

        if !trustExistingRecording || !fileManager.fileExists(atPath: recordingURL.path) {
            session.audioFileURL = try await mixer.mix(tracks: tracks, outputURL: recordingURL)
        } else {
            session.audioFileURL = recordingURL
        }

        if session.endedAt == nil {
            let duration = try await durationLoader(recordingURL)
            guard duration.isFinite, duration > 0 else {
                throw RecoveryError.invalidRecoveredDuration
            }
            session.endedAt = session.startedAt.addingTimeInterval(duration)
        }

        return RecordingCaptureResult(session: session, tracks: tracks)
    }

    private func tracks(
        in directory: URL,
        originalTracks: [CapturedAudioTrack]
    ) -> [CapturedAudioTrack] {
        AudioSourceKind.allCases.map { source in
            let fileName = source == .microphone ? "microphone.m4a" : "system-audio.m4a"
            return CapturedAudioTrack(
                source: source,
                fileURL: directory.appending(path: fileName),
                firstSampleTime: originalTracks.first(where: { $0.source == source })?.firstSampleTime
            )
        }
    }

    private func preserveForManualRecovery(_ directory: URL) {
        let destination = layout.recovery.appending(
            path: "Interrupted-\(directory.lastPathComponent)-\(UUID().uuidString.prefix(8))",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.moveItem(at: directory, to: destination)
        } catch {
            AppLogger.persistenceFailed(
                operation: "preserve-interrupted-recording",
                error: error
            )
        }
    }

    nonisolated private static func loadDuration(from url: URL) async throws -> TimeInterval {
        let duration = try await AVURLAsset(url: url).load(.duration)
        return duration.seconds
    }
}

private enum RecoveryError: LocalizedError {
    case invalidSessionDirectory
    case sessionIdentityMismatch
    case invalidRecoveredDuration

    var errorDescription: String? {
        switch self {
        case .invalidSessionDirectory:
            "The recording folder has an invalid session ID."
        case .sessionIdentityMismatch:
            "The recording folder doesn’t match the session ID."
        case .invalidRecoveredDuration:
            "Couldn’t read the recovered audio file’s duration."
        }
    }
}
