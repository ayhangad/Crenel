import Foundation

/// Turns a raw dictation transcript into the text to insert, a selection replacement, or a task.
/// Never throws: every LLM failure falls back to the deterministic result.
struct DictationRefiner: DictationTextRefining {
    static let onDeviceTimeBudget: TimeInterval = 2.5
    static let cloudTimeBudget: TimeInterval = 4

    let preferences: AgentPreferences
    private let provider: (any LanguageModelProvider)?
    private let timeBudgetOverride: TimeInterval?

    /// - Parameters:
    ///   - provider: model to use; `nil` (or `preferences.provider == .off`) keeps only the deterministic pass.
    ///   - timeBudget: overrides the per-provider budget (tests).
    init(preferences: AgentPreferences, provider: (any LanguageModelProvider)?, timeBudget: TimeInterval? = nil) {
        self.preferences = preferences
        self.provider = preferences.provider == .off ? nil : provider
        self.timeBudgetOverride = timeBudget
    }

    /// Builds the provider for `preferences` with production Keychain/HTTP dependencies.
    init(preferences: AgentPreferences) {
        self.init(preferences: preferences, provider: AgentProviderFactory.makeProvider(for: preferences))
    }

    var timeBudget: TimeInterval {
        timeBudgetOverride ?? (preferences.provider.isCloud ? Self.cloudTimeBudget : Self.onDeviceTimeBudget)
    }

    func refine(transcript: String, context: DictationContext) async -> DictationRefinementOutcome {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        if let task = DictationTextProcessor.taskText(in: raw, localeIdentifier: context.localeIdentifier) {
            return .createTask(DictationTextProcessor.applyVocabulary(context.vocabulary, to: task))
        }

        let selected = context.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if preferences.commandModeEnabled, !selected.isEmpty, let provider,
           DictationTextProcessor.looksLikeCommand(raw) {
            return await transform(selection: context.selectedText ?? selected, instruction: raw, provider: provider)
        }

        let deterministic = DictationTextProcessor.clean(raw, context: context)
        guard preferences.cleanupEnabled, let provider,
              deterministic.split(whereSeparator: \.isWhitespace).count > 2 else {
            return .insert(deterministic)
        }
        let request = AgentRequest(
            systemInstructions: DictationPrompts.cleanupInstructions,
            userContent: DictationPrompts.cleanupRequestContent(transcript: deterministic, context: context),
            maxOutputTokens: Self.outputTokenBudget(for: deterministic, cloud: preferences.provider.isCloud),
            temperature: 0,
            timeout: timeBudget
        )
        guard let output = try? await AgentDeadline.run(seconds: timeBudget, operation: {
            try await provider.generate(request)
        }), let accepted = DictationOutputGuard.acceptCleanup(output, input: deterministic) else {
            return .insert(deterministic)
        }
        return .insert(DictationTextProcessor.applyVocabulary(context.vocabulary, to: accepted))
    }

    /// On failure the original selection is returned unchanged, so a spoken command is never typed
    /// over the user's text.
    private func transform(
        selection: String,
        instruction: String,
        provider: any LanguageModelProvider
    ) async -> DictationRefinementOutcome {
        let request = AgentRequest(
            systemInstructions: DictationPrompts.transformInstructions,
            userContent: DictationPrompts.transformRequestContent(instruction: instruction, selectedText: selection),
            maxOutputTokens: Self.outputTokenBudget(for: selection, cloud: preferences.provider.isCloud, factor: 3),
            temperature: 0.2,
            timeout: timeBudget
        )
        guard let output = try? await AgentDeadline.run(seconds: timeBudget, operation: {
            try await provider.generate(request)
        }), let accepted = DictationOutputGuard.acceptTransform(output, selectedText: selection) else {
            return .replaceSelection(selection)
        }
        return .replaceSelection(accepted)
    }

    /// Roughly 1 token per 3 characters, with headroom for reasoning on cloud models.
    static func outputTokenBudget(for text: String, cloud: Bool, factor: Int = 2) -> Int {
        let estimate = max(64, text.count / 3 * factor + 64)
        return cloud ? min(8_000, estimate + 1_024) : min(4_000, estimate)
    }
}

enum AgentProviderFactory {
    static func makeProvider(
        for preferences: AgentPreferences,
        openAIKeys: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.openAIService),
        anthropicKeys: any APIKeyRepository = KeychainAPIKeyRepository(
            service: KeychainAPIKeyRepository.anthropicService
        ),
        http: any AgentHTTPClient = URLSessionAgentHTTPClient()
    ) -> (any LanguageModelProvider)? {
        switch preferences.provider {
        case .off:
            return nil
        case .onDevice, .automatic:
            // `.automatic` is resolved earlier (AgentProviderResolver); on-device is the safe default.
            return FoundationModelsProvider()
        case .openAI:
            return OpenAIProvider(
                model: preferences.modelID(for: .openAI) ?? OpenAIProvider.defaultModel,
                keys: openAIKeys, http: http
            )
        case .anthropic:
            return AnthropicProvider(
                model: preferences.modelID(for: .anthropic) ?? AnthropicProvider.defaultModel,
                keys: anthropicKeys, http: http
            )
        }
    }
}

/// Runs an operation with a hard deadline. Returns as soon as the deadline passes even if the
/// operation ignores cancellation; the operation is cancelled in the background.
enum AgentDeadline {
    static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let work = Task {
                    do { gate.finish(.success(try await operation())) } catch { gate.finish(.failure(error)) }
                }
                let timer = Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    gate.finish(.failure(AgentError.timeout))
                }
                gate.track([work, timer])
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }

    private final class ResumeGate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var pending: Result<T, Error>?
        private var done = false
        private var tasks: [Task<Void, Never>] = []

        func install(_ continuation: CheckedContinuation<T, Error>) {
            lock.lock()
            if let pending {
                done = true
                lock.unlock()
                continuation.resume(with: pending)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func track(_ newTasks: [Task<Void, Never>]) {
            lock.lock()
            if done {
                lock.unlock()
                newTasks.forEach { $0.cancel() }
                return
            }
            tasks.append(contentsOf: newTasks)
            lock.unlock()
        }

        func finish(_ result: Result<T, Error>) {
            lock.lock()
            guard !done else { lock.unlock(); return }
            guard let continuation else {
                if pending == nil { pending = result }
                lock.unlock()
                return
            }
            done = true
            self.continuation = nil
            let toCancel = tasks
            tasks = []
            lock.unlock()
            continuation.resume(with: result)
            toCancel.forEach { $0.cancel() }
        }
    }
}

/// Turns `.automatic` into the provider the user's keys allow: one API key is enough.
enum AgentProviderResolver {
    static func resolve(
        _ preferences: AgentPreferences,
        anthropicKeys: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.anthropicService),
        openAIKeys: any APIKeyRepository = KeychainAPIKeyRepository(service: KeychainAPIKeyRepository.openAIService)
    ) async -> AgentPreferences {
        guard preferences.provider == .automatic else { return preferences }
        var resolved = preferences
        if await hasKey(anthropicKeys) {
            resolved.provider = .anthropic
        } else if await hasKey(openAIKeys) {
            resolved.provider = .openAI
        } else {
            resolved.provider = .onDevice
        }
        return resolved
    }

    private static func hasKey(_ keys: any APIKeyRepository) async -> Bool {
        guard let key = (try? await keys.apiKey()) ?? nil else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
