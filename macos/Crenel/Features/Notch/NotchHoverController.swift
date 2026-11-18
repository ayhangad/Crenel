import Foundation

@MainActor
final class NotchHoverController {
    typealias Transition = @MainActor () async -> Void

    enum PresentationState: Equatable {
        case compact
        case expanded
    }

    private let expansionDelay: Duration
    private let compactionDelay: Duration
    private let onExpand: Transition
    private let onCompact: Transition
    /// Asked just before the panel closes: the pointer may be on it without having moved
    /// since the last hover report.
    private let isStillHovering: @MainActor () -> Bool
    private var transitionTask: Task<Void, Never>?
    private var isPinned = false
    private var isHovering = false
    private(set) var presentationState: PresentationState = .compact

    init(
        // The pointer leans the notch in, and it opens 180 ms later; it closes 380 ms
        // after the pointer leaves.
        expansionDelay: Duration = .milliseconds(Int(Hud.Motion.leanDelay * 1_000)),
        compactionDelay: Duration = .milliseconds(380),
        onExpand: @escaping Transition,
        onCompact: @escaping Transition,
        isStillHovering: @escaping @MainActor () -> Bool = { false }
    ) {
        self.isStillHovering = isStillHovering
        self.expansionDelay = expansionDelay
        self.compactionDelay = compactionDelay
        self.onExpand = onExpand
        self.onCompact = onCompact
    }

    func update(isHovering: Bool) {
        self.isHovering = isHovering
        transitionTask?.cancel()

        switch (isHovering, presentationState) {
        case (true, .compact):
            transitionTask = schedule(after: expansionDelay) { [weak self] in
                guard let self else { return }
                self.presentationState = .expanded
                await self.onExpand()
            }
        case (false, .expanded):
            guard !isPinned else {
                transitionTask = nil
                return
            }
            transitionTask = schedule(after: compactionDelay) { [weak self] in
                guard let self, !self.isStillHovering() else { return }
                self.presentationState = .compact
                await self.onCompact()
            }
        case (true, .expanded), (false, .compact):
            transitionTask = nil
        }
    }

    func setPinned(_ isPinned: Bool, isHovering: Bool? = nil) {
        self.isPinned = isPinned
        if let isHovering {
            self.isHovering = isHovering
        }
        transitionTask?.cancel()
        transitionTask = nil

        guard !isPinned, !self.isHovering, presentationState == .expanded else { return }
        transitionTask = schedule(after: compactionDelay) { [weak self] in
            guard let self else { return }
            self.presentationState = .compact
            await self.onCompact()
        }
    }

    func markExpanded() {
        transitionTask?.cancel()
        transitionTask = nil
        presentationState = .expanded
    }

    func markCompact() {
        transitionTask?.cancel()
        transitionTask = nil
        presentationState = .compact
    }

    func cancel() {
        transitionTask?.cancel()
        transitionTask = nil
    }

    private func schedule(
        after delay: Duration,
        action: @escaping Transition
    ) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                await action()
            } catch {
                // A new hover intent replaces the pending transition.
            }
        }
    }
}
