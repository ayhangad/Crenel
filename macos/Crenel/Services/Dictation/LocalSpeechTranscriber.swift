@preconcurrency import AVFoundation
import Foundation
import Speech

/// One streaming transcription session: `start` → `feed`… → `finish`.
protocol DictationTranscribing: AnyObject {
    /// Starts a session and returns live partial transcripts (finalized text + volatile tail).
    func start(localeIdentifier: String, vocabulary: [String]) async throws -> AsyncStream<String>
    /// Thread-safe; may be called from any thread while a session is active.
    func feed(_ buffer: AVAudioPCMBuffer) throws
    func finish() async throws -> String
    func cancel() async
}

enum DictationSpeechAssetStatus: Equatable, Sendable {
    case unsupported
    case notInstalled
    case downloading
    case installed
}

protocol DictationSpeechAssetManaging: AnyObject {
    func assetStatus(localeIdentifier: String) async -> DictationSpeechAssetStatus
    func prepareAssets(localeIdentifier: String, progress: (@Sendable (Double) -> Void)?) async throws
}

extension DictationSpeechAssetManaging {
    func prepareAssets(localeIdentifier: String) async throws {
        try await prepareAssets(localeIdentifier: localeIdentifier, progress: nil)
    }
}

/// Fully on-device transcription with the macOS 26 `SpeechAnalyzer` stack.
///
/// Uses `SpeechTranscriber` when the hardware supports it, otherwise falls back to
/// `DictationTranscriber` (with punctuation). Audio never leaves the process.
final class LocalSpeechTranscriber: DictationTranscribing, DictationSpeechAssetManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var inputQueue: DictationPCMQueue?
    private var partialContinuation: AsyncStream<String>.Continuation?
    private var resultsTask: Task<String, Error>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    init() {}

    // MARK: - Assets

    func assetStatus(localeIdentifier: String) async -> DictationSpeechAssetStatus {
        guard let module = await makeModule(localeIdentifier: localeIdentifier) else {
            return .unsupported
        }
        switch await AssetInventory.status(forModules: [module.module]) {
        case .unsupported:
            return .unsupported
        case .supported:
            return .notInstalled
        case .downloading:
            return .downloading
        case .installed:
            return .installed
        @unknown default:
            return .unsupported
        }
    }

    func prepareAssets(localeIdentifier: String, progress: (@Sendable (Double) -> Void)?) async throws {
        guard let module = await makeModule(localeIdentifier: localeIdentifier) else {
            throw DictationFailure.unsupportedLocale(localeIdentifier: localeIdentifier)
        }
        _ = try? await AssetInventory.reserve(locale: module.locale)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module.module]) else {
            return // Already installed.
        }
        var observation: NSKeyValueObservation?
        if let progress {
            observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { value, _ in
                progress(value.fractionCompleted)
            }
        }
        defer { observation?.invalidate() }
        try await request.downloadAndInstall()
    }

    // MARK: - Session

    func start(localeIdentifier: String, vocabulary: [String]) async throws -> AsyncStream<String> {
        await cancel()

        guard let module = await makeModule(localeIdentifier: localeIdentifier) else {
            throw DictationFailure.unsupportedLocale(localeIdentifier: localeIdentifier)
        }
        switch await AssetInventory.status(forModules: [module.module]) {
        case .installed:
            break
        case .downloading:
            throw DictationFailure.speechAssetsDownloading(localeIdentifier: localeIdentifier)
        case .supported:
            throw DictationFailure.speechAssetsMissing(localeIdentifier: localeIdentifier)
        case .unsupported:
            throw DictationFailure.unsupportedLocale(localeIdentifier: localeIdentifier)
        @unknown default:
            throw DictationFailure.unsupportedLocale(localeIdentifier: localeIdentifier)
        }

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module.module])
        let analyzer = SpeechAnalyzer(
            modules: [module.module],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
        )
        do {
            try await analyzer.prepareToAnalyze(in: format)
            let cleanedVocabulary = vocabulary
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !cleanedVocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = Array(cleanedVocabulary.prefix(100))
                try await analyzer.setContext(context)
            }
        } catch {
            throw DictationFailure.transcriptionFailed
        }

        let inputQueue = DictationPCMQueue()
        let inputStream = inputQueue.map { AnalyzerInput(buffer: $0) }
        let (partials, partialContinuation) = AsyncStream.makeStream(
            of: String.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        let resultsTask = Task<String, Error> {
            var accumulator = TranscriptAccumulator()
            do {
                for try await update in module.results() {
                    accumulator.apply(text: update.text, isFinal: update.isFinal)
                    partialContinuation.yield(accumulator.display)
                }
            } catch {
                partialContinuation.finish()
                throw error
            }
            partialContinuation.finish()
            return accumulator.finalText
        }

        lock.withLock {
            self.analyzer = analyzer
            self.inputQueue = inputQueue
            self.partialContinuation = partialContinuation
            self.resultsTask = resultsTask
            self.analyzerFormat = format
            self.converter = nil
            self.converterSourceFormat = nil
        }

        do {
            try await analyzer.start(inputSequence: inputStream)
        } catch {
            await cancel()
            throw DictationFailure.transcriptionFailed
        }
        return partials
    }

    func feed(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let inputQueue else { return }
        guard let converted = convertLocked(buffer) else { return }
        try inputQueue.yield(converted)
    }

    func finish() async throws -> String {
        let (analyzer, inputQueue, resultsTask) = lock.withLock {
            let snapshot = (self.analyzer, self.inputQueue, self.resultsTask)
            self.inputQueue = nil
            return snapshot
        }
        guard let analyzer, let resultsTask else { return "" }
        inputQueue?.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await resultsTask.value
            clearSession()
            return text
        } catch {
            clearSession()
            throw DictationFailure.transcriptionFailed
        }
    }

    func cancel() async {
        let (analyzer, inputQueue, partialContinuation, resultsTask) = lock.withLock {
            let snapshot = (self.analyzer, self.inputQueue, self.partialContinuation, self.resultsTask)
            self.inputQueue = nil
            return snapshot
        }
        inputQueue?.finish()
        resultsTask?.cancel()
        partialContinuation?.finish()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        clearSession()
    }

    // MARK: - Private

    private func clearSession() {
        lock.withLock {
            analyzer = nil
            inputQueue = nil
            partialContinuation = nil
            resultsTask = nil
            analyzerFormat = nil
            converter = nil
            converterSourceFormat = nil
        }
    }

    /// Must be called with `lock` held.
    private func convertLocked(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target = analyzerFormat, buffer.format != target else { return buffer }
        if converter == nil || converterSourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
            converterSourceFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private struct ModuleHandle {
        let module: any SpeechModule
        let locale: Locale
        let results: () -> AsyncThrowingStream<(text: String, isFinal: Bool), Error>
    }

    private func makeModule(localeIdentifier: String) async -> ModuleHandle? {
        let requested = Locale(identifier: localeIdentifier)
        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            return ModuleHandle(module: transcriber, locale: locale) {
                Self.mapResults(transcriber.results) { (String($0.text.characters), $0.isFinal) }
            }
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: [.shortForm],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: []
            )
            return ModuleHandle(module: transcriber, locale: locale) {
                Self.mapResults(transcriber.results) { (String($0.text.characters), $0.isFinal) }
            }
        }
        return nil
    }

    private static func mapResults<S: AsyncSequence & Sendable>(
        _ sequence: S,
        transform: @escaping @Sendable (S.Element) -> (text: String, isFinal: Bool)
    ) -> AsyncThrowingStream<(text: String, isFinal: Bool), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await element in sequence {
                        continuation.yield(transform(element))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Joins finalized segments and the current volatile tail into readable text.
struct TranscriptAccumulator: Equatable, Sendable {
    private(set) var finalizedSegments: [String] = []
    private(set) var volatileText = ""

    mutating func apply(text: String, isFinal: Bool) {
        if isFinal {
            finalizedSegments.append(text)
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    var finalText: String {
        Self.join(finalizedSegments)
    }

    var display: String {
        Self.join(finalizedSegments + [volatileText])
    }

    static func join(_ segments: [String]) -> String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
