@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Typed on-device transcription failure with user-facing messages.
/// `serviceError` maps to the shared `TranscriptionServiceError` vocabulary so the worker's
/// retry policy treats permanent failures (unsupported language, unreadable audio) as final.
enum LocalMeetingTranscriptionError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedLocale(String)
    case assetInstallationFailed(String)
    case unreadableAudio
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let identifier):
            "On-device transcription doesn’t support \(identifier). Choose another language or ElevenLabs in Settings."
        case .assetInstallationFailed(let identifier):
            "Couldn’t download the on-device speech model for \(identifier). Check your internet connection and disk space, then try again."
        case .unreadableAudio:
            "Couldn’t read the recording for on-device transcription."
        case .analysisFailed:
            "On-device transcription didn’t finish. Try again."
        }
    }

    var serviceError: TranscriptionServiceError {
        switch self {
        case .unsupportedLocale: .unsupportedFeature(.automaticLanguageDetection)
        case .assetInstallationFailed: .networkUnavailable
        case .unreadableAudio: .invalidFile(.unreadable)
        case .analysisFailed: .invalidResponse
        }
    }
}

/// Fully on-device meeting transcription with the macOS 26 `SpeechAnalyzer` stack.
///
/// - No network access of its own; only the system asset installer may download speech models.
/// - Nothing is written to disk by this service.
/// - Poor-man's diarization: when the raw `microphone.m4a` / `system-audio.m4a` tracks that
///   `FileMeetingRepository` keeps next to the mixed recording still exist, each is transcribed
///   separately and labelled "You" / "Participants"; otherwise the mixed file is transcribed as a
///   single "Speaker".
actor LocalMeetingTranscriptionService: TranscriptionServicing {
    static let microphoneTrackFileName = "microphone.m4a"
    static let systemAudioTrackFileName = "system-audio.m4a"

    nonisolated let capabilities = TranscriptionServiceCapabilities(
        supportedFileExtensions: ["m4a", "wav", "caf", "aiff", "aif", "aac", "mp3"],
        maximumFileSizeBytes: Int64.max,
        supportsDiarization: false,
        supportsAutomaticLanguageDetection: true
    )

    private let fileManager: FileManager
    private let systemLocale: @Sendable () -> Locale

    init(
        fileManager: FileManager = .default,
        systemLocale: @escaping @Sendable () -> Locale = { Locale.current }
    ) {
        self.fileManager = fileManager
        self.systemLocale = systemLocale
    }

    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        // Diarization is approximated from separate tracks, so it is not a hard requirement here.
        let validationRequest = TranscriptionRequest(
            audioFileURL: request.audioFileURL,
            languageCode: request.languageCode,
            requestsDiarization: false,
            idempotencyKey: request.idempotencyKey
        )
        try TranscriptionFileValidator(fileManager: fileManager)
            .validate(request: validationRequest, capabilities: capabilities)
        try Task.checkCancellation()

        let engine = try await resolveEngine(languageCode: request.languageCode)
        try await ensureAssets(for: engine)
        try Task.checkCancellation()

        let sources = Self.trackSources(for: request.audioFileURL, fileManager: fileManager)
        uploadProgress(0)
        var perTrack: [[TranscriptSegment]] = []
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            let count = Double(sources.count)
            let phrases = try await transcribeFile(source.url, engine: engine) { fraction in
                uploadProgress(min(1, (Double(index) + min(1, max(0, fraction))) / count))
            }
            perTrack.append(LocalTranscriptAssembler.sentenceSegments(from: phrases, speaker: source.speaker))
        }
        uploadProgress(1)

        let segments = LocalTranscriptAssembler.merge(perTrack)
        let languageCode = engine.locale.language.languageCode?.identifier
        return TranscriptionResult(
            transcript: LocalTranscriptAssembler.transcript(from: segments, languageCode: languageCode)
        )
    }

    // MARK: - Track discovery

    struct TrackSource: Equatable, Sendable {
        let url: URL
        let speaker: LocalTranscriptSpeaker
    }

    /// Uses the raw tracks next to the mixed file when both exist and are non-empty; otherwise
    /// the mixed file with a single speaker.
    static func trackSources(for mixedURL: URL, fileManager: FileManager = .default) -> [TrackSource] {
        let directory = mixedURL.deletingLastPathComponent()
        let microphone = directory.appending(path: microphoneTrackFileName)
        let system = directory.appending(path: systemAudioTrackFileName)
        func usable(_ url: URL) -> Bool {
            guard url.standardizedFileURL != mixedURL.standardizedFileURL,
                  let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else {
                return false
            }
            return size.int64Value > 0
        }
        if usable(microphone), usable(system) {
            return [
                TrackSource(url: microphone, speaker: .microphone),
                TrackSource(url: system, speaker: .systemAudio)
            ]
        }
        return [TrackSource(url: mixedURL, speaker: .single)]
    }

    // MARK: - Locale

    /// Ordered locale candidates for a request language code ("tr", "en", nil → system language).
    static func localeCandidates(for languageCode: String?, systemLocale: Locale) -> [Locale] {
        let raw = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = raw.lowercased()
        switch code {
        case "":
            var identifiers = [systemLocale.identifier]
            if let language = systemLocale.language.languageCode?.identifier {
                identifiers.append(defaultRegionIdentifier(for: language))
            }
            return identifiers.uniqued().map(Locale.init(identifier:))
        case "tr", "tur":
            return [Locale(identifier: "tr_TR")]
        case "en", "eng":
            // Prefer the user's English region (en_GB etc.) when the system language is English.
            let system = systemLocale.language.languageCode?.identifier == "en" ? [systemLocale.identifier] : []
            return (system + ["en_US"]).uniqued().map(Locale.init(identifier:))
        default:
            let normalized = raw.replacingOccurrences(of: "-", with: "_")
            let language = String(code.split(separator: "-").first ?? "")
            let candidates = normalized.contains("_") ? [normalized] : [normalized, defaultRegionIdentifier(for: language)]
            return candidates.uniqued().map(Locale.init(identifier:))
        }
    }

    private static func defaultRegionIdentifier(for language: String) -> String {
        switch language {
        case "tr": "tr_TR"
        case "en": "en_US"
        case "de": "de_DE"
        case "fr": "fr_FR"
        case "es": "es_ES"
        case "it": "it_IT"
        case "pt": "pt_BR"
        case "ja": "ja_JP"
        default: language
        }
    }

    // MARK: - Engine

    private enum ModuleKind { case speech, dictation }

    private struct Engine {
        let locale: Locale
        let kind: ModuleKind

        /// A fresh module per analysis; a module may only be attached to one analyzer.
        func makeModule() -> any SpeechModule {
            switch kind {
            case .speech:
                SpeechTranscriber(
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: [],
                    attributeOptions: [.audioTimeRange]
                )
            case .dictation:
                DictationTranscriber(
                    locale: locale,
                    contentHints: [.farField],
                    transcriptionOptions: [.punctuation],
                    reportingOptions: [],
                    attributeOptions: [.audioTimeRange]
                )
            }
        }
    }

    private func resolveEngine(languageCode: String?) async throws -> Engine {
        let candidates = Self.localeCandidates(for: languageCode, systemLocale: systemLocale())
        for candidate in candidates {
            if SpeechTranscriber.isAvailable,
               let locale = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                return Engine(locale: locale, kind: .speech)
            }
            if let locale = await DictationTranscriber.supportedLocale(equivalentTo: candidate) {
                return Engine(locale: locale, kind: .dictation)
            }
        }
        throw LocalMeetingTranscriptionError.unsupportedLocale(
            candidates.first.map(Self.displayName(for:)) ?? (languageCode ?? "?")
        )
    }

    private func ensureAssets(for engine: Engine) async throws {
        let module = engine.makeModule()
        let name = Self.displayName(for: engine.locale)
        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            return
        case .unsupported:
            throw LocalMeetingTranscriptionError.unsupportedLocale(name)
        default:
            break
        }
        do {
            _ = try? await AssetInventory.reserve(locale: engine.locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalMeetingTranscriptionError.assetInstallationFailed(name)
        }
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw LocalMeetingTranscriptionError.assetInstallationFailed(name)
        }
    }

    private static func displayName(for locale: Locale) -> String {
        AppLanguage.locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    // MARK: - Analysis

    private func transcribeFile(
        _ url: URL,
        engine: Engine,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [LocalRecognizedPhrase] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw LocalMeetingTranscriptionError.unreadableAudio
        }
        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
        guard duration > 0 else { return [] }

        let module = engine.makeModule()
        let results: AsyncThrowingStream<LocalRecognizedPhrase, Error> = switch module {
        case let transcriber as SpeechTranscriber:
            Self.phrases(from: transcriber.results) { ($0.text, $0.range, $0.isFinal) }
        case let transcriber as DictationTranscriber:
            Self.phrases(from: transcriber.results) { ($0.text, $0.range, $0.isFinal) }
        default:
            throw LocalMeetingTranscriptionError.analysisFailed
        }

        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: SpeechAnalyzer.Options(priority: .utility, modelRetention: .whileInUse)
        )
        let collector = Task<[LocalRecognizedPhrase], Error> {
            var phrases: [LocalRecognizedPhrase] = []
            for try await phrase in results {
                phrases.append(phrase)
                progress(phrase.end / duration)
            }
            return phrases
        }

        return try await withTaskCancellationHandler {
            do {
                if let lastSample = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                try Task.checkCancellation()
                return try await collector.value
            } catch {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                throw LocalMeetingTranscriptionError.analysisFailed
            }
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Converts final module results into timed tokens using the per-run `audioTimeRange` attribute.
    private static func phrases<S: AsyncSequence & Sendable>(
        from sequence: S,
        transform: @escaping @Sendable (S.Element) -> (AttributedString, CMTimeRange, Bool)
    ) -> AsyncThrowingStream<LocalRecognizedPhrase, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await element in sequence {
                        let (text, range, isFinal) = transform(element)
                        guard isFinal else { continue }
                        continuation.yield(phrase(from: text, range: range))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func phrase(from text: AttributedString, range: CMTimeRange) -> LocalRecognizedPhrase {
        var tokens: [LocalTimedToken] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let timeRange = run.attributes[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
            tokens.append(LocalTimedToken(
                text: piece,
                start: timeRange.map { seconds($0.start) },
                end: timeRange.map { seconds(CMTimeRangeGetEnd($0)) }
            ))
        }
        return LocalRecognizedPhrase(
            start: seconds(range.start),
            end: seconds(CMTimeRangeGetEnd(range)),
            tokens: tokens
        )
    }

    private static func seconds(_ time: CMTime) -> TimeInterval {
        let value = CMTimeGetSeconds(time)
        return value.isFinite ? max(0, value) : 0
    }
}

// MARK: - Pure assembly (unit-tested without SpeechAnalyzer)

struct LocalTranscriptSpeaker: Equatable, Sendable {
    let id: String
    let name: String

    static let microphone = LocalTranscriptSpeaker(id: "local_microphone", name: "You")
    static let systemAudio = LocalTranscriptSpeaker(id: "local_system", name: "Participants")
    static let single = LocalTranscriptSpeaker(id: "speaker_0", name: "Speaker")
}

/// A recognized text run. `start`/`end` are nil for runs without an audio time range
/// (e.g. whitespace or punctuation).
struct LocalTimedToken: Equatable, Sendable {
    var text: String
    var start: TimeInterval?
    var end: TimeInterval?
}

/// One finalized analyzer result with its overall audio range.
struct LocalRecognizedPhrase: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var tokens: [LocalTimedToken]
}

enum LocalTranscriptAssembler {
    /// A pause longer than this closes a segment even without punctuation (Turkish
    /// SpeechTranscriber output is typically unpunctuated).
    static let pauseThreshold: TimeInterval = 0.8
    static let maximumSegmentDuration: TimeInterval = 20
    static let maximumSegmentCharacters = 300

    /// Splits phrases into sentence-level segments for one speaker. Sentences may span analyzer
    /// results; long unpunctuated speech is cut at pauses or duration/length caps.
    static func sentenceSegments(
        from phrases: [LocalRecognizedPhrase],
        speaker: LocalTranscriptSpeaker
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var text = ""
        var start: TimeInterval?
        var end: TimeInterval?

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let start {
                segments.append(TranscriptSegment(
                    speakerID: speaker.id,
                    speakerName: speaker.name,
                    startTime: start,
                    endTime: max(start, end ?? start),
                    text: trimmed
                ))
            }
            text = ""
            start = nil
            end = nil
        }

        for phrase in phrases {
            // Results without any timed run still carry the phrase range.
            let timed = phrase.tokens.contains { $0.start != nil }
            let tokens = timed ? phrase.tokens : [LocalTimedToken(
                text: phrase.tokens.map(\.text).joined(), start: phrase.start, end: phrase.end
            )]
            if !text.isEmpty, !text.last!.isWhitespace { text += " " }

            for token in tokens {
                if let tokenStart = token.start, let currentEnd = end,
                   tokenStart - currentEnd > pauseThreshold {
                    flush()
                }
                if let tokenStart = token.start, let currentStart = start,
                   tokenStart - currentStart > maximumSegmentDuration || text.count > maximumSegmentCharacters {
                    flush()
                }
                if start == nil, token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                text += token.text
                if let tokenStart = token.start { start = start ?? tokenStart }
                if let tokenEnd = token.end { end = max(end ?? tokenEnd, tokenEnd) }
                if start == nil { start = phrase.start }
                if endsSentence(token.text) { flush() }
            }
        }
        flush()
        return segments
    }

    /// Merges per-track segments by start time (ties: earlier end, then track order).
    static func merge(_ tracks: [[TranscriptSegment]]) -> [TranscriptSegment] {
        tracks.enumerated()
            .flatMap { trackIndex, segments in
                segments.enumerated().map { (segment: $1, track: trackIndex, order: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.segment.startTime != rhs.segment.startTime {
                    return lhs.segment.startTime < rhs.segment.startTime
                }
                if lhs.segment.endTime != rhs.segment.endTime {
                    return lhs.segment.endTime < rhs.segment.endTime
                }
                if lhs.track != rhs.track { return lhs.track < rhs.track }
                return lhs.order < rhs.order
            }
            .map(\.segment)
    }

    static func transcript(from segments: [TranscriptSegment], languageCode: String?) -> Transcript {
        Transcript(
            text: segments.map(\.text).joined(separator: " "),
            languageCode: languageCode,
            segments: segments
        )
    }

    private static func endsSentence(_ token: String) -> Bool {
        guard let last = token.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?…。？！".contains(last)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
