import Foundation

/// Observable lifecycle of a single dictation session.
enum DictationState: Equatable, Sendable {
    case idle
    case listening(startedAt: Date, level: Float)
    case transcribing
    case refining
    case inserting
    case inserted(DictationResultSummary)
    case failed(DictationFailure)

    var isBusy: Bool {
        switch self {
        case .listening, .transcribing, .refining, .inserting:
            return true
        case .idle, .inserted, .failed:
            return false
        }
    }

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// How the final text reached its destination.
enum DictationDelivery: String, Equatable, Sendable, Codable {
    case insertedViaAccessibility
    case insertedViaPaste
    case replacedSelection
    case taskCreated
}

struct DictationResultSummary: Equatable, Sendable {
    let text: String
    let delivery: DictationDelivery
    let appName: String?

    var message: String {
        switch delivery {
        case .insertedViaAccessibility, .insertedViaPaste:
            if let appName, !appName.isEmpty {
                return "Added to \(appName)."
            }
            return "Text added."
        case .replacedSelection:
            return "Selected text replaced."
        case .taskCreated:
            return "Task created."
        }
    }
}

/// User-facing dictation failures. Messages are safe to show directly.
enum DictationFailure: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case inputMonitoringPermissionMissing
    case accessibilityPermissionMissing
    case speechAssetsMissing(localeIdentifier: String)
    case speechAssetsDownloading(localeIdentifier: String)
    case unsupportedLocale(localeIdentifier: String)
    case noFocusedTextField
    case secureTextField
    case tooShort
    case noSpeechDetected
    case sessionTooLong
    case transcriptionFailed
    case insertionFailed

    var message: String {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is off. Turn it on in System Settings > Privacy & Security > Microphone."
        case .microphoneUnavailable:
            return "No microphone available."
        case .inputMonitoringPermissionMissing:
            return "The dictation shortcut needs Input Monitoring access."
        case .accessibilityPermissionMissing:
            return "Couldn’t insert text without Accessibility access. Copied to clipboard."
        case .speechAssetsMissing:
            return "The on-device speech model for this language isn’t installed. Download started."
        case .speechAssetsDownloading:
            return "Downloading the speech model. Try again when it finishes."
        case .unsupportedLocale:
            return "The selected language isn’t supported for on-device dictation."
        case .noFocusedTextField:
            return "No focused text field. Copied to clipboard."
        case .secureTextField:
            return "Dictation into password fields is blocked for security."
        case .tooShort:
            return "Recording was too short."
        case .noSpeechDetected:
            return "No speech detected."
        case .sessionTooLong:
            return "Dictation time limit reached."
        case .transcriptionFailed:
            return "Couldn’t transcribe speech."
        case .insertionFailed:
            return "Couldn’t insert text. Copied to clipboard."
        }
    }

    /// Whether the dictated text is still available on the clipboard after this failure.
    var leftTextOnClipboard: Bool {
        switch self {
        case .noFocusedTextField, .accessibilityPermissionMissing, .insertionFailed:
            return true
        default:
            return false
        }
    }
}

/// Result of attempting to put text into the frontmost application.
enum TextInsertionResult: Equatable, Sendable {
    case insertedViaAccessibility
    case insertedViaPaste
    case copiedToClipboard(TextInsertionClipboardReason)
    case refusedSecureField
}

enum TextInsertionClipboardReason: Equatable, Sendable {
    case noFocusedTextField
    case accessibilityPermissionMissing
    case pasteFailed
}

/// One completed dictation kept in memory only (never persisted).
struct DictationHistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let transcript: String
    let finalText: String
    let delivery: DictationDelivery?
    let appName: String?
}

/// Recognition language preference; `.automatic` follows the system language list.
enum DictationLanguage: String, CaseIterable, Codable, Equatable, Sendable {
    case automatic
    case turkish
    case english

    static let supportedIdentifiers = ["tr-TR", "en-US"]

    func resolvedLocaleIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .turkish:
            return "tr-TR"
        case .english:
            return "en-US"
        case .automatic:
            for language in preferredLanguages {
                let lowered = language.lowercased()
                if lowered.hasPrefix("tr") { return "tr-TR" }
                if lowered.hasPrefix("en") { return "en-US" }
            }
            return "en-US"
        }
    }
}
