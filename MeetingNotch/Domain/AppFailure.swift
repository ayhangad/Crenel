import Foundation

struct AppFailure: Error, Identifiable, Equatable, Sendable {
    enum Category: String, Sendable {
        case permission
        case recording
        case fileSystem
        case network
        case provider
        case decoding
        case unknown
    }

    enum RecoveryAction: String, Sendable {
        case requestPermission
        case openSystemSettings
        case retry
        case freeDiskSpace
        case checkConnection
        case updateCredentials
        case dismiss
    }

    let category: Category
    let title: String
    let message: String
    let recoveryAction: RecoveryAction

    var id: String {
        [category.rawValue, title, recoveryAction.rawValue].joined(separator: ":")
    }

    var isRetryable: Bool {
        switch recoveryAction {
        case .retry, .checkConnection:
            true
        default:
            false
        }
    }

    var recoveryButtonTitle: String {
        switch recoveryAction {
        case .requestPermission:
            "İzin Ver"
        case .openSystemSettings:
            "Sistem Ayarlarını Aç"
        case .retry:
            "Tekrar Dene"
        case .freeDiskSpace:
            "Depolamayı Kontrol Et"
        case .checkConnection:
            "Bağlantıyı Kontrol Et"
        case .updateCredentials:
            "API Anahtarını Güncelle"
        case .dismiss:
            "Kapat"
        }
    }

    static func permission(_ message: String, settings: Bool = false) -> AppFailure {
        AppFailure(
            category: .permission,
            title: "İzin gerekli",
            message: message,
            recoveryAction: settings ? .openSystemSettings : .requestPermission
        )
    }

    static func recording(_ message: String, retryable: Bool = true) -> AppFailure {
        AppFailure(
            category: .recording,
            title: "Kayıt başlatılamadı",
            message: message,
            recoveryAction: retryable ? .retry : .dismiss
        )
    }

    static func fileSystem(_ message: String, diskFull: Bool = false) -> AppFailure {
        AppFailure(
            category: .fileSystem,
            title: "Dosya kaydedilemedi",
            message: message,
            recoveryAction: diskFull ? .freeDiskSpace : .retry
        )
    }

    static func network(_ message: String) -> AppFailure {
        AppFailure(
            category: .network,
            title: "Bağlantı kurulamadı",
            message: message,
            recoveryAction: .checkConnection
        )
    }

    static func provider(_ message: String, credentialsInvalid: Bool = false) -> AppFailure {
        AppFailure(
            category: .provider,
            title: "Transkripsiyon tamamlanamadı",
            message: message,
            recoveryAction: credentialsInvalid ? .updateCredentials : .retry
        )
    }

    static func decoding(_ message: String) -> AppFailure {
        AppFailure(
            category: .decoding,
            title: "Yanıt okunamadı",
            message: message,
            recoveryAction: .retry
        )
    }
}
