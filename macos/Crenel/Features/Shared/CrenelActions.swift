import SwiftUI

/// User actions for the Crenel features (calendar, tasks, dictation), injected once at the
/// root of the notch and desktop views. Keeps view initialisers from growing a closure per
/// feature; views stay free of AppKit/EventKit calls.
struct CrenelActions {
    var openInCalendar: (Meeting) -> Void = { _ in }
    var openMeetingURL: (URL) -> Void = { _ in }
    var tasks = TaskActions()
    var dictation = DictationActions()

    struct DictationActions {
        var toggleHandsFree: () -> Void = {}
        var cancel: () -> Void = {}
        var copyLast: () -> Void = {}
        var requestInputMonitoring: () -> Void = {}
        var prepareSpeechAssets: () -> Void = {}
    }

    struct TaskActions {
        var add: (TaskInputParseResult) -> Void = { _ in }
        var rename: (TaskItem, String) -> Void = { _, _ in }
        /// Saves an edited task (title, notes, dates) from the detail card.
        var save: (TaskItem) -> Void = { _ in }
        var setStatus: (TaskItem, TaskStatus) -> Void = { _, _ in }
        var reschedule: (TaskItem, Date?, Bool) -> Void = { _, _, _ in }
        var postponeToTomorrow: (TaskItem) -> Void = { _ in }
        var setPriority: (TaskItem, TaskPriority) -> Void = { _, _ in }
        var archive: (TaskItem) -> Void = { _ in }
        var restore: (TaskItem) -> Void = { _ in }
        var delete: (TaskItem) -> Void = { _ in }
        var clearHistory: () -> Void = {}
        var connectReminders: () -> Void = {}
        var openSourceMeeting: (UUID) -> Void = { _ in }
    }
}

private struct CrenelActionsKey: EnvironmentKey {
    static let defaultValue = CrenelActions()
}

extension EnvironmentValues {
    var crenelActions: CrenelActions {
        get { self[CrenelActionsKey.self] }
        set { self[CrenelActionsKey.self] = newValue }
    }
}
