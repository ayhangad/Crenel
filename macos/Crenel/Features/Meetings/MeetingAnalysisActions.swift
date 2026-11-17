import Foundation

struct MeetingAnalysisActions {
    var renameSpeaker: (UUID, String, String) async -> SettingsActionResult = { _, _, _ in .failed(message: "Couldn’t update the recording.") }
    var importAction: (UUID, ActionItem) async -> SettingsActionResult = { _, _ in .failed(message: "Couldn’t add the task.") }
}
