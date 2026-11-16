@preconcurrency import AVFoundation
import XCTest
@testable import MeetingNotch

@MainActor
final class DictationControllerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 10_000)
    private var capture: FakeDictationCapture!
    private var transcriber: FakeDictationTranscriber!
    private var inserter: FakeDictationInserter!
    private var trigger: FakeTriggerMonitor!
    private var createdTasks: [String] = []

    override func setUp() async throws {
        clock = Date(timeIntervalSince1970: 10_000)
        capture = FakeDictationCapture()
        transcriber = FakeDictationTranscriber()
        inserter = FakeDictationInserter()
        trigger = FakeTriggerMonitor()
        createdTasks = []
    }

    private func makeController(
        refiner: any DictationTextRefining = PassthroughDictationRefiner(),
        assets: (any DictationSpeechAssetManaging)? = nil
    ) -> DictationController {
        var configuration = DictationController.Configuration()
        configuration.resultDisplayDuration = nil
        configuration.maximumSessionDuration = 3_600
        let controller = DictationController(
            capture: capture,
            transcriber: transcriber,
            assets: assets,
            inserter: inserter,
            refiner: refiner,
            triggerMonitor: trigger,
            configuration: configuration,
            now: { [unowned self] in self.clock },
            sleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            preferredLanguages: { ["tr-TR"] }
        )
        controller.onCreateTask = { [unowned self] text in self.createdTasks.append(text) }
        return controller
    }

    private func runSession(_ controller: DictationController, holdFor seconds: TimeInterval = 1) async {
        trigger.emit(.began)
        await controller.waitForCurrentSession()
        capture.send(buffers: 3)
        clock.addTimeInterval(seconds)
        trigger.emit(.ended)
        await controller.waitForCurrentSession()
    }

    func testNormalFlowInsertsTranscriptAndRecordsHistory() async {
        transcriber.finalText = "  merhaba dünya  "
        inserter.result = .insertedViaAccessibility
        inserter.context = DictationTargetSnapshot(bundleIdentifier: "com.apple.TextEdit", appName: "TextEdit")
        let controller = makeController()

        trigger.emit(.began)
        guard case .listening = controller.state else {
            return XCTFail("Expected listening, got \(controller.state)")
        }
        await controller.waitForCurrentSession()
        XCTAssertEqual(transcriber.startedLocale, "tr-TR")
        capture.send(buffers: 3)
        clock.addTimeInterval(1)
        trigger.emit(.ended)
        await controller.waitForCurrentSession()

        XCTAssertEqual(transcriber.fedBufferCount, 3)
        XCTAssertEqual(inserter.insertedTexts, ["merhaba dünya"])
        XCTAssertEqual(
            controller.state,
            .inserted(DictationResultSummary(text: "merhaba dünya", delivery: .insertedViaAccessibility, appName: "TextEdit"))
        )
        XCTAssertEqual(controller.history.first?.finalText, "merhaba dünya")
        XCTAssertEqual(controller.history.first?.appName, "TextEdit")
        XCTAssertTrue(capture.stopCount >= 1)
    }

    func testHoldShorterThanMinimumCancelsSilently() async {
        transcriber.finalText = "kısa"
        let controller = makeController()

        trigger.emit(.began)
        await controller.waitForCurrentSession()
        clock.addTimeInterval(0.1)
        trigger.emit(.ended)
        await controller.waitForCurrentSession()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(inserter.insertedTexts.isEmpty)
        XCTAssertTrue(controller.history.isEmpty)
        XCTAssertFalse(transcriber.finishCalled)
    }

    func testEscapeCancelDiscardsSessionWithoutInsertion() async {
        transcriber.finalText = "iptal edilecek"
        let controller = makeController()

        trigger.emit(.began)
        await controller.waitForCurrentSession()
        capture.send(buffers: 2)
        clock.addTimeInterval(2)
        trigger.emit(.cancelled)
        await Task.yield()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.partialTranscript, "")
        XCTAssertTrue(inserter.insertedTexts.isEmpty)
        XCTAssertFalse(transcriber.finishCalled)

        // A stale `.ended` after cancel is ignored.
        trigger.emit(.ended)
        XCTAssertEqual(controller.state, .idle)
    }

    func testRefinerCreateTaskRoutesToClosureInsteadOfInserting() async {
        transcriber.finalText = "yarın faturayı öde diye görev ekle"
        let refiner = FixedRefiner(outcome: .createTask("Faturayı öde"))
        let controller = makeController(refiner: refiner)

        await runSession(controller)

        XCTAssertEqual(createdTasks, ["Faturayı öde"])
        XCTAssertTrue(inserter.insertedTexts.isEmpty)
        XCTAssertEqual(
            controller.state,
            .inserted(DictationResultSummary(text: "Faturayı öde", delivery: .taskCreated, appName: nil))
        )
        let context = await refiner.lastContext
        XCTAssertEqual(context?.localeIdentifier, "tr-TR")
    }

    func testReplaceSelectionOutcomeReportsReplacement() async {
        transcriber.finalText = "bunu daha resmi yap"
        inserter.context = DictationTargetSnapshot(bundleIdentifier: "x", appName: "Notes", selectedText: "selam")
        inserter.result = .insertedViaPaste
        let refiner = FixedRefiner(outcome: .replaceSelection("Merhabalar"))
        let controller = makeController(refiner: refiner)

        await runSession(controller)

        XCTAssertEqual(inserter.insertedTexts, ["Merhabalar"])
        XCTAssertEqual(
            controller.state,
            .inserted(DictationResultSummary(text: "Merhabalar", delivery: .replacedSelection, appName: "Notes"))
        )
        let context = await refiner.lastContext
        XCTAssertEqual(context?.selectedText, "selam")
    }

    func testNoFocusedFieldFallsBackToClipboardFailure() async {
        transcriber.finalText = "panoya gitmeli"
        inserter.result = .copiedToClipboard(.noFocusedTextField)
        let controller = makeController()

        await runSession(controller)

        XCTAssertEqual(controller.state, .failed(.noFocusedTextField))
        XCTAssertTrue(DictationFailure.noFocusedTextField.leftTextOnClipboard)
        XCTAssertEqual(controller.history.first?.finalText, "panoya gitmeli")
        XCTAssertNil(controller.history.first?.delivery)
    }

    func testSecureFieldRefusalIsNotKeptInHistory() async {
        transcriber.finalText = "gizli"
        inserter.result = .refusedSecureField
        let controller = makeController()

        await runSession(controller)

        XCTAssertEqual(controller.state, .failed(.secureTextField))
        XCTAssertTrue(controller.history.isEmpty)
    }

    func testSilenceOnlyResultDoesNotInsert() async {
        transcriber.finalText = " . "
        let controller = makeController()

        await runSession(controller)

        XCTAssertEqual(controller.state, .failed(.noSpeechDetected))
        XCTAssertTrue(inserter.insertedTexts.isEmpty)
    }

    func testMicrophoneDeniedFailsAndResetsTrigger() async {
        capture.startError = DictationFailure.microphonePermissionDenied
        let controller = makeController()

        trigger.emit(.began)
        await controller.waitForCurrentSession()

        XCTAssertEqual(controller.state, .failed(.microphonePermissionDenied))
        XCTAssertEqual(trigger.externalEndCount, 1)
        XCTAssertEqual(
            DictationFailure.microphonePermissionDenied.message,
            "Mikrofon izni verilmedi. Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon bölümünden izin verin."
        )
    }

    func testMissingSpeechAssetsStartsDownload() async {
        transcriber.startError = DictationFailure.speechAssetsMissing(localeIdentifier: "tr-TR")
        let assets = FakeAssetManager()
        let controller = makeController(assets: assets)

        trigger.emit(.began)
        await controller.waitForCurrentSession()

        XCTAssertEqual(controller.state, .failed(.speechAssetsMissing(localeIdentifier: "tr-TR")))
        XCTAssertEqual(capture.stopCount, 1)
        for _ in 0..<20 where assets.preparedLocales.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(assets.preparedLocales, ["tr-TR"])
    }

    func testPartialTranscriptAndLevelArePublished() async {
        transcriber.finalText = "son"
        let controller = makeController()

        trigger.emit(.began)
        await controller.waitForCurrentSession()
        transcriber.partialContinuation?.yield("canlı önizleme")
        capture.levelContinuation?.yield(0.6)
        for _ in 0..<20 where controller.partialTranscript.isEmpty || controller.level == 0 {
            await Task.yield()
        }

        XCTAssertEqual(controller.partialTranscript, "canlı önizleme")
        XCTAssertEqual(controller.level, 0.6, accuracy: 0.001)
        if case .listening(_, let level) = controller.state {
            XCTAssertEqual(level, 0.6, accuracy: 0.001)
        } else {
            XCTFail("Expected listening")
        }
    }

    func testHistoryIsCappedAtTwentyAndCopyLastUsesNewest() async {
        let controller = makeController()
        for index in 0..<22 {
            transcriber.finalText = "metin \(index)"
            await runSession(controller)
        }

        XCTAssertEqual(controller.history.count, 20)
        XCTAssertEqual(controller.history.first?.finalText, "metin 21")
        XCTAssertTrue(controller.copyLastDictation())
        XCTAssertEqual(inserter.copiedTexts, ["metin 21"])
    }

    func testFailureMessagesAreTurkishAndNonEmpty() {
        let failures: [DictationFailure] = [
            .microphonePermissionDenied, .microphoneUnavailable, .inputMonitoringPermissionMissing,
            .accessibilityPermissionMissing, .speechAssetsMissing(localeIdentifier: "tr-TR"),
            .speechAssetsDownloading(localeIdentifier: "tr-TR"), .unsupportedLocale(localeIdentifier: "xx"),
            .noFocusedTextField, .secureTextField, .tooShort, .noSpeechDetected, .sessionTooLong,
            .transcriptionFailed, .insertionFailed
        ]
        for failure in failures {
            XCTAssertFalse(failure.message.isEmpty, "\(failure)")
        }
        XCTAssertEqual(DictationFailure.noFocusedTextField.message, "Odaklanmış bir metin alanı bulunamadı; metin panoya kopyalandı.")
        XCTAssertEqual(DictationFailure.noSpeechDetected.message, "Konuşma algılanmadı.")
    }

    func testLanguageResolution() {
        XCTAssertEqual(DictationLanguage.automatic.resolvedLocaleIdentifier(preferredLanguages: ["tr-TR", "en"]), "tr-TR")
        XCTAssertEqual(DictationLanguage.automatic.resolvedLocaleIdentifier(preferredLanguages: ["en-GB"]), "en-US")
        XCTAssertEqual(DictationLanguage.automatic.resolvedLocaleIdentifier(preferredLanguages: ["de-DE"]), "en-US")
        XCTAssertEqual(DictationLanguage.turkish.resolvedLocaleIdentifier(preferredLanguages: ["en"]), "tr-TR")
    }

    func testTranscriptAccumulatorJoinsFinalAndVolatileSegments() {
        var accumulator = TranscriptAccumulator()
        accumulator.apply(text: "Merhaba", isFinal: false)
        XCTAssertEqual(accumulator.display, "Merhaba")
        accumulator.apply(text: "Merhaba dünya.", isFinal: true)
        accumulator.apply(text: " Nasıl", isFinal: false)
        XCTAssertEqual(accumulator.display, "Merhaba dünya. Nasıl")
        XCTAssertEqual(accumulator.finalText, "Merhaba dünya.")
    }
}

// MARK: - Fakes

final class FakeDictationCapture: DictationAudioCapturing {
    var startError: Error?
    private(set) var stopCount = 0
    private(set) var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private(set) var levelContinuation: AsyncStream<Float>.Continuation?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    func start(deviceID: String?) async throws -> DictationAudioStream {
        if let startError { throw startError }
        let (buffers, bufferContinuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        let (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self)
        self.bufferContinuation = bufferContinuation
        self.levelContinuation = levelContinuation
        return DictationAudioStream(format: format, buffers: buffers, levels: levels)
    }

    func send(buffers count: Int) {
        for _ in 0..<count {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
            buffer.frameLength = 160
            bufferContinuation?.yield(buffer)
        }
    }

    func stop() {
        stopCount += 1
        bufferContinuation?.finish()
        levelContinuation?.finish()
        bufferContinuation = nil
        levelContinuation = nil
    }
}

final class FakeDictationTranscriber: DictationTranscribing, @unchecked Sendable {
    var finalText = ""
    var startError: Error?
    private(set) var startedLocale: String?
    private(set) var finishCalled = false
    private(set) var partialContinuation: AsyncStream<String>.Continuation?
    private let lock = NSLock()
    private var fed = 0

    var fedBufferCount: Int { lock.withLock { fed } }

    func start(localeIdentifier: String, vocabulary: [String]) async throws -> AsyncStream<String> {
        if let startError { throw startError }
        startedLocale = localeIdentifier
        finishCalled = false
        lock.withLock { fed = 0 }
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        partialContinuation = continuation
        return stream
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { fed += 1 }
    }

    func finish() async throws -> String {
        finishCalled = true
        partialContinuation?.finish()
        return finalText
    }

    func cancel() async {
        partialContinuation?.finish()
    }
}

@MainActor
final class FakeDictationInserter: DictationTextInserting {
    var context = DictationTargetSnapshot()
    var result: TextInsertionResult = .insertedViaAccessibility
    private(set) var insertedTexts: [String] = []
    private(set) var copiedTexts: [String] = []

    func currentContext() -> DictationTargetSnapshot { context }

    func insert(_ text: String) async -> TextInsertionResult {
        insertedTexts.append(text)
        return result
    }

    func copyToClipboard(_ text: String) {
        copiedTexts.append(text)
    }
}

@MainActor
final class FakeTriggerMonitor: DictationTriggerMonitoring {
    var onEvent: ((DictationTriggerEvent) -> Void)?
    var settings = DictationTriggerSettings.default
    private(set) var externalEndCount = 0

    func start() -> Bool { true }
    func stop() {}
    func sessionEndedExternally() { externalEndCount += 1 }
    func emit(_ event: DictationTriggerEvent) { onEvent?(event) }
}

actor FixedRefiner: DictationTextRefining {
    let outcome: DictationRefinementOutcome
    private(set) var lastContext: DictationContext?

    init(outcome: DictationRefinementOutcome) {
        self.outcome = outcome
    }

    func refine(transcript: String, context: DictationContext) async -> DictationRefinementOutcome {
        lastContext = context
        return outcome
    }
}

final class FakeAssetManager: DictationSpeechAssetManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var prepared: [String] = []
    var preparedLocales: [String] { lock.withLock { prepared } }

    func assetStatus(localeIdentifier: String) async -> DictationSpeechAssetStatus { .notInstalled }

    func prepareAssets(localeIdentifier: String, progress: (@Sendable (Double) -> Void)?) async throws {
        lock.withLock { prepared.append(localeIdentifier) }
    }
}
