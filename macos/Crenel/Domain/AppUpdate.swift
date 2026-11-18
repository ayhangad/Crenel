import Foundation

/// A version Crenel can update to, or has just updated to.
struct AppUpdateVersion: Equatable, Sendable {
    /// "1.2".
    let shortVersion: String
    /// The release notes page, when the feed names one.
    var releaseNotesURL: URL?
    /// How many changes the notes list, when known ("3 changes").
    var changeCount: Int?
}

/// Where an update is. The update itself is installed by the updater while Crenel is
/// closed (1–2 s), so there is no "installing" phase to show: Restarting is the last
/// moment Crenel is running, and the next launch reports the new version.
enum AppUpdatePhase: Equatable, Sendable {
    case idle
    /// Downloading in the background, 0…1.
    case downloading(AppUpdateVersion, progress: Double)
    /// Verifying and unpacking the download.
    case preparing(AppUpdateVersion)
    /// Ready to install on restart.
    case ready(AppUpdateVersion)
    /// Restart was chosen; Crenel is about to quit and be replaced.
    case restarting(AppUpdateVersion)

    var version: AppUpdateVersion? {
        switch self {
        case .idle: nil
        case .downloading(let version, _), .preparing(let version), .ready(let version), .restarting(let version): version
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Which update notices the user has already answered, per version: "Later" on the
/// ready strip, "OK" on the strip shown during a recording.
struct AppUpdateNotices: Equatable, Sendable {
    var laterVersion: String?
    var duringRecordingVersion: String?

    func readyDismissed(_ version: AppUpdateVersion) -> Bool { laterVersion == version.shortVersion }
    func recordingDismissed(_ version: AppUpdateVersion) -> Bool { duringRecordingVersion == version.shortVersion }
}

/// Compares this launch's version with the last one, to say "Updated" once.
enum AppLaunchVersion {
    static let lastLaunchedKey = "lastLaunchedVersion"
    static let lastLaunchedBuildKey = "lastLaunchedBuild"

    /// The version this launch updated to, if the app was updated since the last launch:
    /// a newer version, or a newer build of the same version. Records both either way.
    static func updatedVersion(current: String, build: String? = nil, defaults: UserDefaults = .standard) -> String? {
        let last = defaults.string(forKey: lastLaunchedKey)
        let lastBuild = defaults.string(forKey: lastLaunchedBuildKey)
        defaults.set(current, forKey: lastLaunchedKey)
        defaults.set(build, forKey: lastLaunchedBuildKey)
        guard let last else { return nil }
        switch current.compare(last, options: .numeric) {
        case .orderedDescending:
            return current
        case .orderedSame:
            guard let build, let lastBuild,
                  build.compare(lastBuild, options: .numeric) == .orderedDescending else { return nil }
            return current
        case .orderedAscending:
            return nil
        }
    }
}
