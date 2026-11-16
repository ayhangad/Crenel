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
                return "\(appName) uygulamasına eklendi."
            }
            return "Metin eklendi."
        case .replacedSelection:
            return "Seçili metin değiştirildi."
        case .taskCreated:
            return "Görev oluşturuldu."
        }
    }
}

/// User-facing dictation failures. Messages are Turkish and safe to show directly.
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
            return "Mikrofon izni verilmedi. Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon bölümünden izin verin."
        case .microphoneUnavailable:
            return "Kullanılabilir mikrofon bulunamadı."
        case .inputMonitoringPermissionMissing:
            return "Dikte kısayolu için Girdi İzleme izni gerekli."
        case .accessibilityPermissionMissing:
            return "Erişilebilirlik izni olmadığı için metin eklenemedi; metin panoya kopyalandı."
        case .speechAssetsMissing:
            return "Bu dil için cihaz üzerindeki konuşma modeli yüklü değil. İndirme başlatıldı."
        case .speechAssetsDownloading:
            return "Konuşma modeli indiriliyor. İndirme bitince yeniden deneyin."
        case .unsupportedLocale:
            return "Seçilen dil cihaz üzerinde dikte için desteklenmiyor."
        case .noFocusedTextField:
            return "Odaklanmış bir metin alanı bulunamadı; metin panoya kopyalandı."
        case .secureTextField:
            return "Güvenlik nedeniyle parola alanlarına dikte edilmez."
        case .tooShort:
            return "Kayıt çok kısaydı."
        case .noSpeechDetected:
            return "Konuşma algılanmadı."
        case .sessionTooLong:
            return "Dikte süresi sınırına ulaşıldı."
        case .transcriptionFailed:
            return "Konuşma yazıya çevrilemedi."
        case .insertionFailed:
            return "Metin eklenemedi; metin panoya kopyalandı."
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
