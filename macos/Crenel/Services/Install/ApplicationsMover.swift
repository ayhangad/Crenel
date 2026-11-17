import AppKit
import Foundation

/// Offers to move Crenel into Applications when it runs from anywhere else — most often
/// straight from the mounted DMG. From there the Chrome bridge would point at a volume
/// that goes away, the updater could not replace a read-only app, and ejecting the DMG
/// would remove Crenel. People who drag it into Applications never see this.
enum ApplicationsMover {
    enum Location: Equatable {
        /// /Applications or ~/Applications.
        case applications
        /// A mounted disk image (`/Volumes/…`) or a translocated copy macOS made of it.
        case diskImage
        /// Downloads, Desktop or anywhere else.
        case elsewhere
    }

    static func location(of bundleURL: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Location {
        let path = bundleURL.standardizedFileURL.path
        let userApplications = home.appending(path: "Applications").standardizedFileURL.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/") { return .applications }
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") { return .diskImage }
        return .elsewhere
    }

    /// Asks once per launch, then moves and relaunches if the answer is yes.
    @MainActor
    static func offerIfNeeded(bundle: Bundle = .main) {
        let source = bundle.bundleURL
        guard location(of: source) != .applications else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Crenel to Applications?")
        alert.informativeText = String(localized: "Crenel needs to live in Applications to update itself and to keep the Chrome connection working after the disk image is ejected.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let destination = try move(source)
            relaunch(at: destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = String(localized: "Crenel couldn’t be moved")
            failure.informativeText = String(localized: "Drag Crenel into the Applications folder yourself, then open it from there.")
            failure.runModal()
        }
    }

    /// Copies the app into /Applications (replacing an older copy, which goes to the
    /// Trash) and returns where it now is.
    static func move(_ source: URL, fileManager: FileManager = .default) throws -> URL {
        let destination = URL(fileURLWithPath: "/Applications").appending(path: source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    @MainActor
    private static func relaunch(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
