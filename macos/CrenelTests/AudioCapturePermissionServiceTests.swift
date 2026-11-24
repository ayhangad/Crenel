@preconcurrency import AVFoundation
import XCTest
@testable import Crenel

@MainActor
final class AudioCapturePermissionServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AudioCapturePermissionServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCurrentSnapshotReflectsMicrophoneAndSystemAudioAccess() {
        let service = makeService(
            microphoneStatus: { .authorized },
            hasSystemAudioAccess: { true }
        )

        XCTAssertEqual(
            service.currentSnapshot(),
            AudioCapturePermissionSnapshot(microphone: .authorized, systemAudio: .authorized)
        )
    }

    func testVerifyRequestsUndeterminedPermissionsBeforeRecording() async {
        var microphoneStatus = AVAuthorizationStatus.notDetermined
        var hasSystemAudioAccess = false
        var microphoneRequestCount = 0
        var systemAudioRequestCount = 0
        let service = makeService(
            microphoneStatus: { microphoneStatus },
            requestMicrophoneAccess: {
                microphoneRequestCount += 1
                microphoneStatus = .authorized
                return true
            },
            hasSystemAudioAccess: { hasSystemAudioAccess },
            requestSystemAudioAccess: {
                systemAudioRequestCount += 1
                hasSystemAudioAccess = true
                return true
            }
        )

        let snapshot = await service.verifyAccessForRecording()

        XCTAssertTrue(snapshot.canRecord)
        XCTAssertEqual(microphoneRequestCount, 1)
        XCTAssertEqual(systemAudioRequestCount, 1)
    }

    func testRejectedSystemAudioAccessIsRetriedByExplicitRecordingAttempt() async {
        var requestCount = 0
        let service = makeService(
            microphoneStatus: { .authorized },
            hasSystemAudioAccess: { false },
            requestSystemAudioAccess: {
                requestCount += 1
                return false
            }
        )

        _ = await service.requestSystemAudioAccess()
        let snapshot = await service.verifyAccessForRecording()

        XCTAssertEqual(snapshot.systemAudio, .denied)
        XCTAssertFalse(snapshot.canRecord)
        XCTAssertEqual(requestCount, 2)
    }

    func testRejectedSystemAudioRequestRequiresSystemSettings() async {
        let service = makeService(hasSystemAudioAccess: { false })
        _ = await service.requestSystemAudioAccess()

        XCTAssertEqual(service.currentSnapshot().systemAudio, .denied)
        XCTAssertTrue(service.currentSnapshot().systemAudio.requiresSystemSettings)
    }

    func testExplicitSystemAudioRequestCanBeRetriedAfterDenial() async {
        var requestCount = 0
        let service = makeService(
            microphoneStatus: { .authorized },
            hasSystemAudioAccess: { false },
            requestSystemAudioAccess: {
                requestCount += 1
                return false
            }
        )

        _ = await service.requestSystemAudioAccess()
        _ = await service.requestSystemAudioAccess()

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(service.currentSnapshot().systemAudio, .denied)
    }

    func testPermissionChangesAreReflectedWithoutRecreatingService() {
        var microphoneStatus = AVAuthorizationStatus.authorized
        var hasSystemAudioAccess = true
        let service = makeService(
            microphoneStatus: { microphoneStatus },
            hasSystemAudioAccess: { hasSystemAudioAccess }
        )

        XCTAssertTrue(service.currentSnapshot().canRecord)

        microphoneStatus = .denied
        hasSystemAudioAccess = false

        XCTAssertEqual(service.currentSnapshot().microphone, .denied)
        XCTAssertEqual(service.currentSnapshot().systemAudio, .verificationRequired)
        XCTAssertFalse(service.currentSnapshot().canRecord)
    }

    func testVerifiedSystemAudioSurvivesRelaunchUntilATapFails() async {
        let first = makeService(hasSystemAudioAccess: { false }, requestSystemAudioAccess: { true })
        _ = await first.requestSystemAudioAccess()
        XCTAssertEqual(first.currentSnapshot().systemAudio, .authorized)

        // A new launch: nothing verified in memory, the stored proof still counts.
        let relaunched = makeService(hasSystemAudioAccess: { false })
        XCTAssertEqual(relaunched.currentSnapshot().systemAudio, .authorized)

        relaunched.systemAudioAccessFailed()
        XCTAssertEqual(relaunched.currentSnapshot().systemAudio, .denied)
        XCTAssertNotEqual(makeService(hasSystemAudioAccess: { false }).currentSnapshot().systemAudio, .authorized)
    }

    private func makeService(
        microphoneStatus: @escaping () -> AVAuthorizationStatus = { .notDetermined },
        requestMicrophoneAccess: @escaping () async -> Bool = { false },
        hasSystemAudioAccess: @escaping () -> Bool,
        requestSystemAudioAccess: @escaping () async -> Bool = { false }
    ) -> AudioCapturePermissionService {
        AudioCapturePermissionService(
            dependencies: .init(
                microphoneStatus: microphoneStatus,
                requestMicrophoneAccess: requestMicrophoneAccess,
                hasSystemAudioAccess: hasSystemAudioAccess,
                requestSystemAudioAccess: requestSystemAudioAccess
            ),
            defaults: defaults
        )
    }
}
