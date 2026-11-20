import Foundation
import XCTest
@testable import Crenel

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CrenelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testStartsOnlyAfterBothSourcesAreReadyAndPreservesMeetingID() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        var statuses: [RecordingCaptureStatus] = []
        coordinator.onStatusChange = { statuses.append($0) }
        let meeting = Meeting(
            title: "Weekly",
            startDate: .now,
            endDate: .now.addingTimeInterval(1_800)
        )

        let session = try await coordinator.start(
            meeting: meeting,
            systemAudioScope: .meetingProcesses([42])
        )

        XCTAssertEqual(session.meetingID, meeting.id)
        XCTAssertEqual(session.sourceMeeting, meeting)
        XCTAssertTrue(microphone.didPrepare)
        XCTAssertTrue(systemAudio.didPrepare)
        XCTAssertTrue(microphone.didStart)
        XCTAssertTrue(systemAudio.didStart)
        XCTAssertEqual(statuses.last?.microphone.isReady, true)
        XCTAssertEqual(statuses.last?.systemAudio.isReady, true)
    }

    func testStopFinalizesBothTracksAndWritesCaptureManifest() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )

        let result = try await coordinator.stop()

        XCTAssertEqual(Set(result.tracks.map(\.source)), Set(AudioSourceKind.allCases))
        XCTAssertNotNil(result.session.endedAt)
        XCTAssertEqual(result.session.audioFileURL?.lastPathComponent, "recording.m4a")
        let manifest = temporaryRoot
            .appending(path: "Crenel/Temporary/\(session.id.uuidString)/capture.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
    }

    func testStartFailureCancelsBothSourcesAndRemovesTemporaryDirectory() async {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        systemAudio.startError = RecordingCaptureError.sourceFailed(.systemAudio, "test")
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)

        do {
            _ = try await coordinator.start(
                meeting: nil,
                systemAudioScope: .explicitManualGlobal
            )
            XCTFail("Start should fail")
        } catch {
            XCTAssertTrue(microphone.didCancel)
            XCTAssertTrue(systemAudio.didCancel)
        }

        let temporaryDirectory = temporaryRoot.appending(path: "Crenel/Temporary")
        let remaining = (try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRejectsRecordingWhenRequiredDiskSpaceIsUnavailable() async {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = RecordingCoordinator(
            microphoneFactory: { _ in microphone },
            systemAudioFactory: { _ in systemAudio },
            minimumFreeDiskSpace: .max,
            storageRoot: temporaryRoot
        )

        do {
            _ = try await coordinator.start(
                meeting: nil,
                systemAudioScope: .explicitManualGlobal
            )
            XCTFail("Start should fail")
        } catch let error as RecordingCaptureError {
            XCTAssertEqual(error, .insufficientDiskSpace)
            XCTAssertFalse(microphone.didPrepare)
            XCTAssertFalse(systemAudio.didPrepare)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let temporaryDirectory = temporaryRoot.appending(path: "Crenel/Temporary")
        let remaining = (try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStorageMonitorReportsLowDiskWhileRecording() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        var availableCapacity: Int64 = 1_000
        let interruption = expectation(description: "storage safety interruption")
        let coordinator = RecordingCoordinator(
            microphoneFactory: { _ in microphone },
            systemAudioFactory: { _ in systemAudio },
            minimumFreeDiskSpace: 500,
            storageRoot: temporaryRoot,
            mixer: MockAudioTrackMixer(),
            availableCapacityProvider: { _ in availableCapacity },
            storageSafetyCheckInterval: .milliseconds(10)
        )
        coordinator.onSafetyInterruption = { issue in
            XCTAssertEqual(issue, .diskSpaceBecameLow)
            interruption.fulfill()
        }

        _ = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )
        availableCapacity = 0

        await fulfillment(of: [interruption], timeout: 1)
        XCTAssertEqual(coordinator.currentStorageSafetyIssue(), .diskSpaceBecameLow)
        await coordinator.cancel()
    }

    func testMixFailurePreservesRawTracksAndRecoveryManifest() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = RecordingCoordinator(
            microphoneFactory: { _ in microphone },
            systemAudioFactory: { _ in systemAudio },
            minimumFreeDiskSpace: 0,
            storageRoot: temporaryRoot,
            mixer: FailingAudioTrackMixer()
        )
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )
        let directory = temporaryRoot
            .appending(path: "Crenel/Temporary/\(session.id.uuidString)")

        do {
            _ = try await coordinator.stop()
            XCTFail("Stop should fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: directory.appending(path: "microphone.m4a").path
            ))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: directory.appending(path: "system-audio.m4a").path
            ))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: directory.appending(path: "capture.json").path
            ))
        }
    }

    func testSelectedMicrophoneIdentifierIsPassedToSourceFactory() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        var requestedDeviceID: String?
        let coordinator = RecordingCoordinator(
            microphoneFactory: { deviceID in
                requestedDeviceID = deviceID
                return microphone
            },
            systemAudioFactory: { _ in systemAudio },
            minimumFreeDiskSpace: 0,
            storageRoot: temporaryRoot,
            mixer: MockAudioTrackMixer()
        )

        _ = try await coordinator.start(
            meeting: nil,
            microphoneDeviceID: "usb-microphone",
            systemAudioScope: .explicitManualGlobal
        )

        XCTAssertEqual(requestedDeviceID, "usb-microphone")
        await coordinator.cancel()
    }

    func testMicrophoneConnectionChangesUpdateStatusAndRequestAttention() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        var connectionChanges: [AudioSourceConnectionState] = []
        var latestStatus = RecordingCaptureStatus.idle
        coordinator.onStatusChange = { latestStatus = $0 }
        coordinator.onSourceConnectionChange = { source, state in
            XCTAssertEqual(source, .microphone)
            connectionChanges.append(state)
        }

        _ = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )
        microphone.emitConnectionState(.disconnected(deviceName: "USB Mikrofon"))
        await Task.yield()

        XCTAssertEqual(connectionChanges.last, .disconnected(deviceName: "USB Mikrofon"))
        XCTAssertEqual(
            latestStatus.microphone.connectionState,
            .disconnected(deviceName: "USB Mikrofon")
        )
        await coordinator.cancel()
    }

    func testRecordingStartedDuringDictationInheritsHold() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: MockAudioCaptureSource(kind: .systemAudio))
        coordinator.setDictationHeld(true)
        _ = try await coordinator.start(meeting: nil, systemAudioScope: .explicitManualGlobal)
        coordinator.setManualMicrophoneState(.open)
        XCTAssertEqual(microphone.receivedGates.last?.state, .closed)
        coordinator.setDictationHeld(false)
        XCTAssertEqual(microphone.receivedGates.last?.state, .open)
        await coordinator.cancel()
    }

    func testClientAdapterMicrophoneStateUpdatesLiveGateAndCaptureMetadata() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        var gateChanges: [MeetingMicrophoneGate] = []
        coordinator.onMicrophoneGateChange = { gateChanges.append($0) }
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .meetingProcesses([71])
        )

        coordinator.updateMicrophoneGate(
            from: detectionSnapshot(
                audioObjectID: 71,
                processID: 7_100,
                availability: .available,
                microphoneState: .closed
            ),
            at: session.startedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(gateChanges.map(\.state), [.open, .closed])
        XCTAssertEqual(microphone.receivedGates.last?.state, .closed)
        XCTAssertEqual(microphone.receivedGates.last?.events.last?.source, .clientAdapter)

        let result = try await coordinator.stop()
        XCTAssertEqual(result.session.microphoneGateEvents.map(\.state), [.open, .closed])
    }

    func testUnscopedRecordingIgnoresOtherCallAppsMuteState() async throws {
        // Recording a Slack huddle while a muted Zoom window is open somewhere.
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: MockAudioCaptureSource(kind: .systemAudio))
        let session = try await coordinator.start(meeting: nil, systemAudioScope: .explicitManualGlobal)

        coordinator.updateMicrophoneGate(
            from: detectionSnapshot(
                audioObjectID: 71,
                processID: 7_100,
                availability: .available,
                microphoneState: .closed
            ),
            at: session.startedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(microphone.receivedGates.last?.state, .open)
        await coordinator.cancel()
    }

    func testAccessibilityLossKeepsTheMicrophoneOpen() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .meetingProcesses([72])
        )
        coordinator.updateMicrophoneGate(
            from: detectionSnapshot(
                audioObjectID: 72,
                processID: 7_200,
                availability: .available,
                microphoneState: .open
            ),
            at: session.startedAt.addingTimeInterval(1)
        )

        coordinator.updateMicrophoneGate(
            from: detectionSnapshot(
                audioObjectID: 72,
                processID: 7_200,
                availability: .accessibilityPermissionRequired,
                microphoneState: .unknown
            ),
            at: session.startedAt.addingTimeInterval(2)
        )

        XCTAssertEqual(microphone.receivedGates.last?.state, .open)
        XCTAssertEqual(microphone.receivedGates.last?.events.last?.source, .recordingStarted)
        await coordinator.cancel()
    }

    func testMeetingProcessChangeKeepsTheMicrophoneOpen() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .meetingProcesses([73])
        )
        coordinator.updateMicrophoneGate(
            from: detectionSnapshot(
                audioObjectID: 73,
                processID: 7_300,
                availability: .available,
                microphoneState: .open
            ),
            at: session.startedAt.addingTimeInterval(1)
        )

        coordinator.updateMicrophoneGate(
            from: detectionSnapshot(
                audioObjectID: 74,
                processID: 7_301,
                availability: .available,
                microphoneState: .open
            ),
            at: session.startedAt.addingTimeInterval(2)
        )

        XCTAssertEqual(microphone.receivedGates.last?.state, .open)
        XCTAssertEqual(microphone.receivedGates.last?.events.last?.source, .recordingStarted)
        await coordinator.cancel()
    }

    func testManualMicrophoneControlClosesAndPersistsEvent() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )

        coordinator.setManualMicrophoneState(
            .closed,
            at: session.startedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(microphone.receivedGates.last?.state, .closed)
        XCTAssertEqual(microphone.receivedGates.last?.events.last?.source, .manualControl)
        let result = try await coordinator.stop()
        XCTAssertEqual(result.session.microphoneGateEvents.last?.state, .closed)
        XCTAssertEqual(result.session.microphoneGateEvents.last?.source, .manualControl)
    }

    func testMicrophoneDeviceRecoveryDoesNotOpenClosedPrivacyGate() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        _ = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )
        coordinator.setManualMicrophoneState(.closed)

        microphone.emitConnectionState(.recovered(deviceName: "Kulaklık Mikrofonu"))
        await Task.yield()

        XCTAssertEqual(microphone.receivedGates.last?.state, .closed)
        XCTAssertFalse(try XCTUnwrap(microphone.receivedGates.last).permitsAudio)
        await coordinator.cancel()
    }

    func testSystemInterruptionFailsOpenGateClosedAndPersistsReason() async throws {
        let microphone = MockAudioCaptureSource(kind: .microphone)
        let systemAudio = MockAudioCaptureSource(kind: .systemAudio)
        let coordinator = makeCoordinator(microphone: microphone, systemAudio: systemAudio)
        let session = try await coordinator.start(
            meeting: nil,
            systemAudioScope: .explicitManualGlobal
        )
        coordinator.setManualMicrophoneState(
            .open,
            at: session.startedAt.addingTimeInterval(1)
        )

        coordinator.failClosedForSystemInterruption(
            at: session.startedAt.addingTimeInterval(2)
        )

        XCTAssertEqual(microphone.receivedGates.last?.state, .unknown)
        XCTAssertEqual(
            microphone.receivedGates.last?.events.last?.source,
            .systemInterruption
        )
        let result = try await coordinator.stop()
        XCTAssertEqual(
            result.session.microphoneGateEvents.last?.source,
            .systemInterruption
        )
    }

    private func detectionSnapshot(
        audioObjectID: UInt32,
        processID: Int32,
        availability: MeetingClientAdapterAvailability,
        microphoneState: MeetingMicrophoneState
    ) -> MeetingSessionDetectionSnapshot {
        MeetingSessionDetectionSnapshot(
            session: MeetingSession(
                state: .recording,
                confidence: .confirmed,
                clientID: .zoom,
                processID: processID
            ),
            audioProcess: AudioProcessSnapshot(
                audioObjectID: audioObjectID,
                processID: processID,
                bundleIdentifier: "us.zoom.xos",
                isRunningInput: true,
                isRunningOutput: true
            ),
            client: MeetingClientSnapshot(
                clientID: .zoom,
                processID: processID,
                availability: availability,
                meetingWindowPresent: true,
                callControlsPresent: availability == .available,
                microphoneState: microphoneState
            )
        )
    }

    private func makeCoordinator(
        microphone: MockAudioCaptureSource,
        systemAudio: MockAudioCaptureSource
    ) -> RecordingCoordinator {
        RecordingCoordinator(
            microphoneFactory: { _ in microphone },
            systemAudioFactory: { _ in systemAudio },
            minimumFreeDiskSpace: 0,
            storageRoot: temporaryRoot,
            mixer: MockAudioTrackMixer()
        )
    }
}

private final class MockAudioTrackMixer: AudioTrackMixing, @unchecked Sendable {
    func mix(tracks: [CapturedAudioTrack], outputURL: URL) async throws -> URL {
        try Data("mixed-audio".utf8).write(to: outputURL)
        return outputURL
    }
}

private final class FailingAudioTrackMixer: AudioTrackMixing, @unchecked Sendable {
    func mix(tracks: [CapturedAudioTrack], outputURL: URL) async throws -> URL {
        throw AudioMixError.renderFailed
    }
}

private final class MockAudioCaptureSource: AudioCaptureSource, MeetingMicrophoneGateUpdating {
    let kind: AudioSourceKind
    var onLevelChange: (@Sendable (Float) -> Void)?
    var onConnectionStateChange: (@Sendable (AudioSourceConnectionState) -> Void)?
    var startError: Error?
    private var outputURL: URL?

    private(set) var didPrepare = false
    private(set) var didStart = false
    private(set) var didCancel = false
    private(set) var receivedGates: [MeetingMicrophoneGate] = []

    init(kind: AudioSourceKind) {
        self.kind = kind
    }

    func prepare(outputURL: URL) async throws {
        self.outputURL = outputURL
        didPrepare = true
    }

    func start() async throws {
        if let startError { throw startError }
        didStart = true
        onLevelChange?(0.5)
    }

    func stop() async throws -> CapturedAudioTrack {
        guard let outputURL else {
            throw RecordingCaptureError.sourceFailed(kind, "not prepared")
        }
        try Data("audio".utf8).write(to: outputURL)
        return CapturedAudioTrack(source: kind, fileURL: outputURL, firstSampleTime: 1)
    }

    func cancel() async {
        didCancel = true
    }

    func emitConnectionState(_ state: AudioSourceConnectionState) {
        onConnectionStateChange?(state)
    }

    func updateMicrophoneGate(_ gate: MeetingMicrophoneGate) {
        receivedGates.append(gate)
    }
}
