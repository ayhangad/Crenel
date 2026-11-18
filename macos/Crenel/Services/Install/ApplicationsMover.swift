import AppKit
import Foundation
import Security

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

    /// Validate the completed copy on the destination volume before swapping it into place.
    static func move(_ source: URL, into folder: URL = URL(fileURLWithPath: "/Applications"),
                     fileManager: FileManager = .default,
                     validate: (URL, URL) throws -> Void = validateCopy) throws -> URL {
        let destination = folder.appending(path: source.lastPathComponent)
        let temporary = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                            appropriateFor: destination, create: true)
        defer { try? fileManager.removeItem(at: temporary) }
        let staged = temporary.appending(path: source.lastPathComponent)
        try fileManager.copyItem(at: source, to: staged)
        try validate(source, staged)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
        return destination
    }

    private static func validateCopy(source: URL, staged: URL) throws {
        guard let bundle = Bundle(url: staged),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let flags = SecCSFlags()
        var original: SecStaticCode?, copy: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(source as CFURL, flags, &original) == errSecSuccess, let original,
              SecCodeCopyDesignatedRequirement(original, flags, &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(staged as CFURL, flags, &copy) == errSecSuccess, let copy,
              SecStaticCodeCheckValidity(copy, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode),
                                         requirement) == errSecSuccess else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    @MainActor
    private static func relaunch(at url: URL) {
        Task {
            await relaunch(at: url, open: { destination in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            }, terminate: { NSApp.terminate(nil) }, showError: { error in
                let alert = NSAlert(error: error)
                alert.messageText = String(localized: "Crenel couldn’t open the installed copy")
                alert.runModal()
            })
        }
    }

    @MainActor
    static func relaunch(at url: URL, open: (URL) async throws -> Void, terminate: () -> Void,
                         showError: (Error) -> Void) async {
        do {
            try await open(url)
            terminate()
        } catch {
            showError(error)
        }
    }
}
