import Foundation
import XCTest
@testable import MeetingNotch

final class ApplicationRelauncherTests: XCTestCase {
    func testRelaunchWaitsForCurrentProcessAndOpensExactApplicationPath() throws {
        var launchedExecutable: URL?
        var launchedArguments: [String] = []
        let relauncher = ApplicationRelauncher { executableURL, arguments in
            launchedExecutable = executableURL
            launchedArguments = arguments
        }
        let applicationURL = URL(filePath: "/tmp/Build Folder/MeetingNotch.app")

        try relauncher.prepareRelaunch(
            applicationURL: applicationURL,
            processIdentifier: 12_345
        )

        XCTAssertEqual(launchedExecutable, URL(filePath: "/bin/sh"))
        XCTAssertEqual(launchedArguments.count, 5)
        XCTAssertEqual(launchedArguments[0], "-c")
        XCTAssertEqual(launchedArguments[2], "MeetingNotch-relauncher")
        XCTAssertEqual(launchedArguments[3], "12345")
        XCTAssertEqual(launchedArguments[4], applicationURL.path)
        XCTAssertTrue(launchedArguments[1].contains("/bin/kill -0"))
        XCTAssertTrue(launchedArguments[1].contains("/usr/bin/open -n"))
        XCTAssertFalse(launchedArguments[1].contains(applicationURL.path))
    }

    func testRelaunchPropagatesHelperLaunchFailure() {
        let relauncher = ApplicationRelauncher { _, _ in
            throw RelaunchTestError.helperUnavailable
        }

        XCTAssertThrowsError(
            try relauncher.prepareRelaunch(
                applicationURL: URL(filePath: "/tmp/MeetingNotch.app"),
                processIdentifier: 1
            )
        ) { error in
            XCTAssertEqual(error as? RelaunchTestError, .helperUnavailable)
        }
    }
}

private enum RelaunchTestError: Error {
    case helperUnavailable
}
