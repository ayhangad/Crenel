import Foundation

protocol MeetingRetentionRepository: Sendable {
    func loadAll() async throws -> [StoredMeeting]
    func delete(id: UUID) async throws
}

protocol MeetingRepository: MeetingRetentionRepository {
    func load(id: UUID) async throws -> StoredMeeting?
    func prepare() async throws
    func saveCapture(_ capture: RecordingCaptureResult) async throws -> StoredMeeting
    func saveTranscription(
        _ result: TranscriptionResult,
        summary: MeetingSummary?,
        for meeting: StoredMeeting
    ) async throws -> StoredMeeting
    func saveAnalysis(_ transcription: StoredTranscription, for meeting: StoredMeeting) async throws -> StoredMeeting
    func renameSpeaker(meetingID: UUID, speakerID: String, name: String) async throws -> StoredMeeting
    func loadTranscription(for meetingID: UUID) async throws -> StoredTranscription?
    func loadMarkdown(for meetingID: UUID) async throws -> String?
    func audioFileURL(for meeting: StoredMeeting) async -> URL
    func recoveryDirectoryURL() async -> URL
    /// Flags notes written by the old offline extractor so they can be written again
    /// with AI. Returns how many meetings it flagged; running it twice flags nothing.
    func flagLegacySummaries() async throws -> Int
}

extension MeetingRepository {
    func load(id: UUID) async throws -> StoredMeeting? {
        try await loadAll().first { $0.id == id }
    }

    func saveAnalysis(_ transcription: StoredTranscription, for meeting: StoredMeeting) async throws -> StoredMeeting {
        try await saveTranscription(TranscriptionResult(transcript: transcription.transcript), summary: transcription.summary, for: meeting)
    }
    func renameSpeaker(meetingID: UUID, speakerID: String, name: String) async throws -> StoredMeeting {
        throw MeetingRepositoryError.meetingNotFound
    }
    func flagLegacySummaries() async throws -> Int { 0 }
}

enum MeetingRepositoryError: LocalizedError, Equatable {
    case missingFinalAudio
    case incompleteSession
    case duplicateMeeting
    case unsupportedSchema(Int)
    case meetingNotFound

    var errorDescription: String? {
        switch self {
        case .missingFinalAudio:
            "Couldn’t find the finished meeting audio."
        case .incompleteSession:
            "The recording session didn’t finish."
        case .duplicateMeeting:
            "This meeting is already saved."
        case .unsupportedSchema(let version):
            "Unsupported meeting metadata version: \(version)."
        case .meetingNotFound:
            "Meeting not found."
        }
    }
}

actor FileMeetingRepository: MeetingRepository {
    private let fileManager: FileManager
    private let layout: AppStorageLayout
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        layout = AppStorageLayout(
            root: rootURL ?? defaultRoot.appending(path: "Crenel", directoryHint: .isDirectory)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func prepare() throws {
        try layout.createDirectories(fileManager: fileManager)
    }

    func saveCapture(_ capture: RecordingCaptureResult) throws -> StoredMeeting {
        try prepare()
        guard let endedAt = capture.session.endedAt else {
            throw MeetingRepositoryError.incompleteSession
        }
        guard let temporaryAudioURL = capture.session.audioFileURL,
              fileManager.fileExists(atPath: temporaryAudioURL.path) else {
            throw MeetingRepositoryError.missingFinalAudio
        }

        let finalDirectory = layout.meetings.appending(
            path: capture.session.id.uuidString,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw MeetingRepositoryError.duplicateMeeting
        }

        let stagingDirectory = layout.meetings.appending(
            path: ".staging-\(capture.session.id.uuidString)",
            directoryHint: .isDirectory
        )
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            let title = normalizedTitle(capture.session.sourceMeeting?.title)
            let audioFileName = MeetingFileName.audioFileName(
                title: title,
                startedAt: capture.session.startedAt,
                id: capture.session.id
            )
            try fileManager.copyItem(
                at: temporaryAudioURL,
                to: stagingDirectory.appending(path: audioFileName)
            )

            let microphoneFileName = try copyRawTrack(
                .microphone,
                from: capture.tracks,
                to: stagingDirectory
            )
            let systemAudioFileName = try copyRawTrack(
                .systemAudio,
                from: capture.tracks,
                to: stagingDirectory
            )
            let meeting = StoredMeeting(
                id: capture.session.id,
                title: title,
                startedAt: capture.session.startedAt,
                endedAt: endedAt,
                sourceMeeting: capture.session.sourceMeeting,
                audioFileName: audioFileName,
                microphoneFileName: microphoneFileName,
                systemAudioFileName: systemAudioFileName
            )
            let metadataURL = stagingDirectory.appending(path: "metadata.json")
            try encoder.encode(meeting).write(to: metadataURL, options: .atomic)
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
            removeTemporaryCaptureDirectory(capture)
            return meeting
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    func loadAll() throws -> [StoredMeeting] {
        try prepare()
        try recoverStagingDirectories()

        let directories = try fileManager.contentsOfDirectory(
            at: layout.meetings,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var meetings: [StoredMeeting] = []

        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            do {
                let meeting = try readMetadata(in: directory)
                meetings.append(meeting)
            } catch {
                moveToRecovery(directory, prefix: "Corrupt")
            }
        }

        return meetings.sorted { $0.startedAt > $1.startedAt }
    }

    func load(id: UUID) throws -> StoredMeeting? {
        let directory = layout.meetings.appending(path: id.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        return try readMetadata(in: directory)
    }

    private func readMetadata(in directory: URL) throws -> StoredMeeting {
        let data = try Data(contentsOf: directory.appending(path: "metadata.json"))
        let meeting = try decoder.decode(StoredMeeting.self, from: data)
        guard meeting.schemaVersion == StoredMeeting.currentSchemaVersion else {
            throw MeetingRepositoryError.unsupportedSchema(meeting.schemaVersion)
        }
        guard directory.lastPathComponent == meeting.id.uuidString,
              isSafeFileName(meeting.audioFileName),
              meeting.microphoneFileName.map(isSafeFileName) ?? true,
              meeting.systemAudioFileName.map(isSafeFileName) ?? true else {
            throw MeetingRepositoryError.missingFinalAudio
        }
        guard fileManager.fileExists(
            atPath: directory.appending(path: meeting.audioFileName).path
        ) else {
            throw MeetingRepositoryError.missingFinalAudio
        }
        return meeting
    }

    func saveTranscription(
        _ result: TranscriptionResult,
        summary: MeetingSummary?,
        for meeting: StoredMeeting
    ) throws -> StoredMeeting {
        try writeAnalysis(StoredTranscription(transcript: result.transcript, summary: summary), for: meeting)
    }

    func saveAnalysis(_ transcription: StoredTranscription, for meeting: StoredMeeting) async throws -> StoredMeeting {
        try writeAnalysis(transcription, for: meeting)
    }

    private func writeAnalysis(_ transcription: StoredTranscription, for meeting: StoredMeeting) throws -> StoredMeeting {
        try prepare()
        let directory = layout.meetings.appending(path: meeting.id.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else { throw MeetingRepositoryError.meetingNotFound }
        var updated = try decoder.decode(StoredMeeting.self, from: Data(contentsOf: directory.appending(path: "metadata.json")))
        if Self.isDefaultTitle(updated.title), let title = transcription.summary?.suggestedTitle,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.title = title
        }
        updated.processingStatus = .completed
        updated.summaryNeedsAttention = transcription.summaryFailure != nil || transcription.summary == nil
        try encoder.encode(transcription).write(to: directory.appending(path: "transcript.json"), options: .atomic)
        let markdown = MeetingMarkdownFormatter.markdown(meeting: updated, transcription: transcription)
        try Data(markdown.utf8).write(to: directory.appending(path: "meeting.md"), options: .atomic)
        try encoder.encode(updated).write(to: directory.appending(path: "metadata.json"), options: .atomic)
        removeRawTrack(named: meeting.microphoneFileName, from: directory)
        removeRawTrack(named: meeting.systemAudioFileName, from: directory)
        return updated
    }

    func renameSpeaker(meetingID: UUID, speakerID: String, name: String) async throws -> StoredMeeting {
        guard let meeting = try await load(id: meetingID),
              let stored = try loadTranscription(for: meetingID) else { throw MeetingRepositoryError.meetingNotFound }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        var transcript = stored.transcript
        for index in transcript.segments.indices where transcript.segments[index].speakerID == speakerID {
            transcript.segments[index].speakerName = trimmed.isEmpty ? nil : trimmed
        }
        var summary = stored.summary
        if summary != nil {
            for index in summary!.actionItems.indices where summary!.actionItems[index].speakerID == speakerID {
                summary!.actionItems[index].assignee = trimmed.isEmpty ? nil : trimmed
            }
        }
        var updated = StoredTranscription(completedAt: stored.completedAt, transcript: transcript, summary: summary)
        updated.transcriptionJobID = stored.transcriptionJobID
        updated.summaryFailure = stored.summaryFailure
        return try writeAnalysis(updated, for: meeting)
    }

    static let legacySummaryFailure = "These notes came from the old offline extractor. Write them again with AI for a real summary and title."

    func flagLegacySummaries() async throws -> Int {
        let marker = layout.root.appending(path: ".legacy-summary-scan-v1")
        guard !fileManager.fileExists(atPath: marker.path) else { return 0 }
        var flagged = 0
        var lastFailure: Error?
        for meeting in try loadAll() where meeting.processingStatus == .completed {
            do {
                guard let stored = try loadTranscription(for: meeting.id),
                      let summary = stored.summary, summary.model == nil,
                      stored.summaryFailure == nil else { continue }
                var marked = stored
                marked.summaryFailure = Self.legacySummaryFailure
                _ = try writeAnalysis(marked, for: meeting)
                flagged += 1
            } catch {
                AppLogger.persistenceFailed(operation: "flag-legacy-summary", error: error)
                lastFailure = error
            }
        }
        if let lastFailure { throw lastFailure }
        try Data().write(to: marker, options: .atomic)
        return flagged
    }

    func loadTranscription(for meetingID: UUID) throws -> StoredTranscription? {
        try prepare()
        let url = layout.meetings
            .appending(path: meetingID.uuidString, directoryHint: .isDirectory)
            .appending(path: "transcript.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let stored = try decoder.decode(StoredTranscription.self, from: Data(contentsOf: url))
        guard stored.schemaVersion == StoredTranscription.currentSchemaVersion else {
            throw MeetingRepositoryError.unsupportedSchema(stored.schemaVersion)
        }
        return stored
    }

    func loadMarkdown(for meetingID: UUID) throws -> String? {
        try prepare()
        let url = layout.meetings
            .appending(path: meetingID.uuidString, directoryHint: .isDirectory)
            .appending(path: "meeting.md")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func delete(id: UUID) throws {
        try prepare()
        let directory = layout.meetings.appending(path: id.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func audioFileURL(for meeting: StoredMeeting) -> URL {
        layout.meetings
            .appending(path: meeting.id.uuidString, directoryHint: .isDirectory)
            .appending(path: meeting.audioFileName)
    }

    func recoveryDirectoryURL() -> URL {
        layout.recovery
    }

    private func copyRawTrack(
        _ source: AudioSourceKind,
        from tracks: [CapturedAudioTrack],
        to directory: URL
    ) throws -> String? {
        guard let track = tracks.first(where: { $0.source == source }),
              fileManager.fileExists(atPath: track.fileURL.path) else {
            return nil
        }
        let fileName = source == .microphone ? "microphone.m4a" : "system-audio.m4a"
        try fileManager.copyItem(at: track.fileURL, to: directory.appending(path: fileName))
        return fileName
    }

    private func removeRawTrack(named fileName: String?, from directory: URL) {
        guard let fileName, isSafeFileName(fileName) else { return }
        try? fileManager.removeItem(at: directory.appending(path: fileName))
    }

    private func removeTemporaryCaptureDirectory(_ capture: RecordingCaptureResult) {
        let candidates = ([capture.session.audioFileURL].compactMap { $0 } + capture.tracks.map { $0.fileURL })
            .map { $0.deletingLastPathComponent().standardizedFileURL }
        guard let directory = candidates.first,
              candidates.allSatisfy({ $0 == directory }),
              directory.deletingLastPathComponent().standardizedFileURL == layout.temporary.standardizedFileURL
        else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    private func recoverStagingDirectories() throws {
        let entries = try fileManager.contentsOfDirectory(
            at: layout.meetings,
            includingPropertiesForKeys: nil
        )
        for entry in entries where entry.lastPathComponent.hasPrefix(".staging-") {
            moveToRecovery(entry, prefix: "Incomplete")
        }
    }

    private func moveToRecovery(_ directory: URL, prefix: String) {
        let destination = layout.recovery.appending(
            path: "\(prefix)-\(directory.lastPathComponent)-\(UUID().uuidString.prefix(8))",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.moveItem(at: directory, to: destination)
        } catch {
            AppLogger.persistenceFailed(operation: "move-to-recovery", error: error)
        }
    }

    private func normalizedTitle(_ title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.defaultTitle : String(trimmed.prefix(160))
    }

    static let defaultTitle = "Untitled meeting"
    /// Meetings saved before the English default may still carry the old Turkish title.
    private static let legacyDefaultTitles: Set<String> = ["İsimsiz Toplantı"]

    private static func isDefaultTitle(_ title: String) -> Bool {
        title == defaultTitle || legacyDefaultTitles.contains(title)
    }

    private func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName != "."
            && fileName != ".."
            && URL(fileURLWithPath: fileName).lastPathComponent == fileName
    }
}
