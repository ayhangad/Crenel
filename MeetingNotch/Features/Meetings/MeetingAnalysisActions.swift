import Foundation

struct MeetingAnalysisActions {
    var renameSpeaker: (UUID, String, String) async -> SettingsActionResult = { _, _, _ in .failed(message: "Kayıt güncellenemedi.") }
    var importAction: (UUID, ActionItem) async -> SettingsActionResult = { _, _ in .failed(message: "Görev eklenemedi.") }
}
