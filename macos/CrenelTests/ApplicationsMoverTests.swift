import XCTest
@testable import Crenel

final class ApplicationsMoverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone")

    func testFailedValidationPreservesOldBundleAndValidCopyReplacesIt() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appending(path: "Applications")
        let source = root.appending(path: "Crenel.app")
        let destination = folder.appending(path: "Crenel.app")
        for url in [source, destination] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        try Data("new".utf8).write(to: source.appending(path: "new"))
        try Data("old".utf8).write(to: destination.appending(path: "old"))
        XCTAssertThrowsError(try ApplicationsMover.move(source, into: folder))
        XCTAssertTrue(fm.fileExists(atPath: destination.appending(path: "old").path))
        let installed = try ApplicationsMover.move(source, into: folder) { _, staged in
            XCTAssertEqual(try Data(contentsOf: staged.appending(path: "new")), Data("new".utf8))
            XCTAssertTrue(fm.fileExists(atPath: destination.appending(path: "old").path))
        }
        XCTAssertTrue(fm.fileExists(atPath: installed.appending(path: "new").path))
        XCTAssertFalse(fm.fileExists(atPath: installed.appending(path: "old").path))
    }

    @MainActor
    func testFailedRelaunchShowsErrorAndKeepsSourceRunning() async {
        var terminated = false, presented = false
        await ApplicationsMover.relaunch(at: home, open: { _ in throw CocoaError(.fileNoSuchFile) },
            terminate: { terminated = true }, showError: { _ in presented = true })
        XCTAssertFalse(terminated)
        XCTAssertTrue(presented)
    }

    func testApplicationsFoldersNeedNoMove() {
        XCTAssertEqual(ApplicationsMover.location(of: URL(fileURLWithPath: "/Applications/Crenel.app"), home: home), .applications)
        XCTAssertEqual(ApplicationsMover.location(of: URL(fileURLWithPath: "/Users/someone/Applications/Crenel.app"), home: home), .applications)
    }

    func testDiskImageAndTranslocationAreRecognised() {
        XCTAssertEqual(ApplicationsMover.location(of: URL(fileURLWithPath: "/Volumes/Crenel/Crenel.app"), home: home), .diskImage)
        XCTAssertEqual(ApplicationsMover.location(of: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Crenel.app"), home: home), .diskImage)
    }

    func testDownloadsIsElsewhere() {
        XCTAssertEqual(ApplicationsMover.location(of: URL(fileURLWithPath: "/Users/someone/Downloads/Crenel.app"), home: home), .elsewhere)
        XCTAssertEqual(ApplicationsMover.location(of: URL(fileURLWithPath: "/Applications Old/Crenel.app"), home: home), .elsewhere)
    }
}
