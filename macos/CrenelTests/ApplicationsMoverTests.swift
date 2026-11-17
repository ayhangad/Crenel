import XCTest
@testable import Crenel

final class ApplicationsMoverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone")

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
