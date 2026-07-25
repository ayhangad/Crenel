import XCTest
@testable import MeetingNotch

final class AudioProcessMonitorTests: XCTestCase {
    func testMonitorPublishesInitialSnapshotAndOnlyIOChanges() async {
        let idle = AudioProcessSnapshot(
            audioObjectID: 10,
            processID: 42,
            bundleIdentifier: "us.zoom.xos",
            isRunningInput: false,
            isRunningOutput: false
        )
        let active = AudioProcessSnapshot(
            audioObjectID: 10,
            processID: 42,
            bundleIdentifier: "us.zoom.xos",
            isRunningInput: true,
            isRunningOutput: true
        )
        let reader = SequenceAudioProcessSnapshotReader([
            [idle],
            [idle],
            [active]
        ])
        let recorder = AudioProcessUpdateRecorder()
        let monitor = CoreAudioProcessMonitor(reader: reader, pollingInterval: nil)

        await monitor.start { snapshots in
            await recorder.append(snapshots)
        }
        await monitor.refresh()
        await monitor.refresh()

        let updates = await recorder.updates()
        XCTAssertEqual(updates, [[idle], [active]])
        await monitor.stop()
    }

    func testSnapshotExposesStableIdentityBundleAndActiveIO() {
        let snapshot = AudioProcessSnapshot(
            audioObjectID: 20,
            processID: 84,
            bundleIdentifier: "us.zoom.xos",
            isRunningInput: false,
            isRunningOutput: true
        )

        XCTAssertEqual(snapshot.id, 20)
        XCTAssertEqual(snapshot.processID, 84)
        XCTAssertEqual(snapshot.bundleIdentifier, "us.zoom.xos")
        XCTAssertTrue(snapshot.hasActiveIO)
    }

    func testReaderCanInspectCurrentCoreAudioProcessList() throws {
        let snapshots = try CoreAudioProcessSnapshotReader().readSnapshots()

        XCTAssertEqual(snapshots, snapshots.sorted {
            if $0.processID == $1.processID {
                return $0.audioObjectID < $1.audioObjectID
            }
            return $0.processID < $1.processID
        })
        XCTAssertTrue(snapshots.allSatisfy { $0.audioObjectID != 0 })
    }
}

private final class SequenceAudioProcessSnapshotReader:
    AudioProcessSnapshotReading,
    @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[AudioProcessSnapshot]]

    init(_ values: [[AudioProcessSnapshot]]) {
        self.values = values
    }

    func readSnapshots() -> [AudioProcessSnapshot] {
        lock.withLock {
            guard values.count > 1 else { return values.first ?? [] }
            return values.removeFirst()
        }
    }
}

private actor AudioProcessUpdateRecorder {
    private var values: [[AudioProcessSnapshot]] = []

    func append(_ snapshots: [AudioProcessSnapshot]) {
        values.append(snapshots)
    }

    func updates() -> [[AudioProcessSnapshot]] {
        values
    }
}
