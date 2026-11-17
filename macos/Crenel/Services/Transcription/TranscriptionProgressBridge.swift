import Foundation

@MainActor
final class TranscriptionProgressBridge {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func uploadProgressHandler() -> TranscriptionUploadProgress {
        { [weak appState] progress in
            Task { @MainActor in
                appState?.updateTranscriptionUploadProgress(progress)
            }
        }
    }
}
