import Foundation

struct ApplicationRelauncher {
    typealias HelperLauncher = (_ executableURL: URL, _ arguments: [String]) throws -> Void

    private static let helperScript = """
    process_id="$1"
    application_path="$2"
    attempt=0
    while /bin/kill -0 "$process_id" 2>/dev/null && [ "$attempt" -lt 100 ]; do
        /bin/sleep 0.1
        attempt=$((attempt + 1))
    done
    exec /usr/bin/open -n "$application_path"
    """

    private let launchHelper: HelperLauncher

    init(launchHelper: @escaping HelperLauncher = Self.launchProcess) {
        self.launchHelper = launchHelper
    }

    func prepareRelaunch(
        applicationURL: URL,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        try launchHelper(
            URL(filePath: "/bin/sh"),
            [
                "-c",
                Self.helperScript,
                "MeetingNotch-relauncher",
                String(processIdentifier),
                applicationURL.standardizedFileURL.path
            ]
        )
    }

    private static func launchProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
