import AVFoundation
import Darwin
import Foundation
import XCTest
@testable import Crenel

final class BrowserAudioBridgeTests: XCTestCase {
    private let sessionID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    func testNativeHostSessionForwardsOnlyValidatedEventsAndReturnsExactAcknowledgements() throws {
        var forwarded: [BrowserAudioBridgeMessage] = []
        var host = BrowserAudioNativeHostSession { message in
            forwarded.append(message)
            switch message.type {
            case "start": return .ready(sessionID: self.sessionID)
            case "audio": return .acknowledgement(
                sessionID: self.sessionID,
                sequence: message.sequence!
            )
            case "stop": return .stopped(sessionID: self.sessionID)
            default: return .failure("unexpected")
            }
        }

        XCTAssertEqual(
            host.process(startWireMessage(), extensionOrigin: BrowserAudioProtocol.expectedExtensionOrigin),
            .ready(sessionID: sessionID)
        )
        XCTAssertEqual(
            host.process(audioWireMessage(sequence: 0), extensionOrigin: BrowserAudioProtocol.expectedExtensionOrigin),
            .acknowledgement(sessionID: sessionID, sequence: 0)
        )
        XCTAssertEqual(
            host.process(stopWireMessage(), extensionOrigin: BrowserAudioProtocol.expectedExtensionOrigin).type,
            "stopped"
        )
        XCTAssertEqual(forwarded.map(\.type), ["start", "audio", "stop"])
    }

    func testNativeHostRejectsWrongOriginWithoutContactingApplicationBridge() {
        var bridgeWasCalled = false
        var host = BrowserAudioNativeHostSession { _ in
            bridgeWasCalled = true
            return .failure("unexpected")
        }

        XCTAssertEqual(
            host.process(startWireMessage(), extensionOrigin: "chrome-extension://other/"),
            .failure("untrusted-origin")
        )
        XCTAssertFalse(bridgeWasCalled)
    }

    func testBrokerDeliversSequentialPCMAndFailsClosedOnDisconnect() throws {
        let broker = BrowserAudioStreamBroker()
        XCTAssertEqual(
            try broker.handle(.make(from: .start(sessionID: sessionID, tabID: 42))),
            .ready(sessionID: sessionID)
        )

        let delivered = LockedTestBox<[BrowserAudioPCMChunk]>([])
        let disconnected = LockedTestBox(false)
        _ = try broker.attachConsumer(
            consume: { chunk in delivered.mutate { $0.append(chunk) } },
            disconnected: { disconnected.set(true) }
        )
        let chunk = pcmChunk(sequence: 0)
        XCTAssertEqual(
            try broker.handle(.make(from: .audio(chunk))),
            .acknowledgement(sessionID: sessionID, sequence: 0)
        )
        XCTAssertEqual(delivered.value, [chunk])

        broker.bridgeDisconnected()
        XCTAssertTrue(disconnected.value)
        XCTAssertFalse(broker.hasActiveSession)
    }

    func testBrokerRejectsOutOfOrderPCMWithoutDelivery() throws {
        let broker = BrowserAudioStreamBroker()
        _ = try broker.handle(.make(from: .start(sessionID: sessionID, tabID: 42)))
        let deliveryCount = LockedTestBox(0)
        _ = try broker.attachConsumer(
            consume: { _ in deliveryCount.mutate { $0 += 1 } },
            disconnected: {}
        )

        XCTAssertThrowsError(try broker.handle(.make(from: .audio(pcmChunk(sequence: 1))))) {
            XCTAssertEqual(
                $0 as? BrowserAudioStreamBrokerError,
                .outOfSequence(expected: 0, actual: 1)
            )
        }
        XCTAssertEqual(deliveryCount.value, 0)
    }

    func testIPCServerRoundTripsFramesAndReportsClientDisconnect() throws {
        let broker = BrowserAudioStreamBroker()
        let server = BrowserAudioIPCServer(broker: broker)
        try server.start()
        defer { server.stop() }
        var descriptor = try BrowserAudioSocketTransport.connect(
            to: BrowserAudioSocketEndpoint.socketURL
        )
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
        }

        try BrowserAudioSocketTransport.writeFrame(
            BrowserAudioBridgeMessage.make(from: .start(sessionID: sessionID, tabID: 42)),
            to: descriptor
        )
        let readyData = try XCTUnwrap(BrowserAudioSocketTransport.readFrame(from: descriptor))
        XCTAssertEqual(
            try JSONDecoder().decode(BrowserAudioBridgeResponse.self, from: readyData),
            .ready(sessionID: sessionID)
        )

        let disconnected = expectation(description: "IPC disconnect fails closed")
        _ = try broker.attachConsumer(consume: { _ in }, disconnected: { disconnected.fulfill() })
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
        descriptor = -1
        wait(for: [disconnected], timeout: 1)
        XCTAssertFalse(broker.hasActiveSession)
    }

    func testEmbeddedNativeHostExecutableEndToEnd() throws {
        let broker = BrowserAudioStreamBroker()
        let server = BrowserAudioIPCServer(broker: broker)
        try server.start()
        defer { server.stop() }

        let executableURL = Bundle.main.bundleURL
            .appending(path: "Contents/Library/LaunchServices/CrenelBrowserAudioHost")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableURL.path))
        let input = Pipe()
        let output = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [BrowserAudioProtocol.expectedExtensionOrigin]
        process.standardInput = input
        process.standardOutput = output
        try process.run()

        try sendNativeBody(startWireMessage(), to: input.fileHandleForWriting.fileDescriptor)
        XCTAssertEqual(
            try readNativeResponse(from: output.fileHandleForReading.fileDescriptor),
            .ready(sessionID: sessionID)
        )

        let delivered = LockedTestBox<[BrowserAudioPCMChunk]>([])
        _ = try broker.attachConsumer(
            consume: { chunk in delivered.mutate { $0.append(chunk) } },
            disconnected: {}
        )
        try sendNativeBody(
            audioWireMessage(sequence: 0),
            to: input.fileHandleForWriting.fileDescriptor
        )
        XCTAssertEqual(
            try readNativeResponse(from: output.fileHandleForReading.fileDescriptor),
            .acknowledgement(sessionID: sessionID, sequence: 0)
        )
        XCTAssertEqual(delivered.value, [pcmChunk(sequence: 0)])

        try sendNativeBody(stopWireMessage(), to: input.fileHandleForWriting.fileDescriptor)
        XCTAssertEqual(
            try readNativeResponse(from: output.fileHandleForReading.fileDescriptor).type,
            "stopped"
        )
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testBrokerPublishesLiveConnectionStates() throws {
        let broker = BrowserAudioStreamBroker()
        let states = LockedTestBox<[BrowserAudioConnectionStatus]>([])
        broker.setStatusHandler { state in states.mutate { $0.append(state) } }

        _ = try broker.handle(.make(from: .start(sessionID: sessionID, tabID: 42)))
        _ = try broker.attachConsumer(consume: { _ in }, disconnected: {})
        broker.detachConsumer(sessionID: sessionID)
        _ = try broker.handle(.make(from: .stop(sessionID: sessionID, reason: "user")))

        XCTAssertEqual(
            states.value,
            [.tabConnected, .recording, .tabConnected, .waitingForMeetTab]
        )
    }

    func testBrowserCaptureSourceWritesValidatedPCMToM4A() async throws {
        let broker = BrowserAudioStreamBroker()
        _ = try broker.handle(.make(from: .start(sessionID: sessionID, tabID: 42)))
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "Crenel-BrowserAudio-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let source = BrowserAudioCaptureSource(broker: broker)

        try await source.prepare(outputURL: outputURL)
        try await source.start()
        for sequence in 0 ..< 4 {
            _ = try broker.handle(.make(from: .audio(pcmChunk(sequence: sequence, frameCount: 960))))
        }
        let track = try await source.stop()

        XCTAssertEqual(track.source, .systemAudio)
        XCTAssertNotNil(track.firstSampleTime)
        XCTAssertNotNil(track.lastSampleTime)
        let file = try AVAudioFile(forReading: outputURL)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testInstallerCreatesNarrowChromeManifestWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Crenel-HostInstaller-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "Crenel.app", directoryHint: .isDirectory)
        let executable = bundle.appending(
            path: "Contents/Library/LaunchServices/CrenelBrowserAudioHost"
        )
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let manifestURL = try BrowserAudioNativeHostInstaller(
            homeDirectory: root.appending(path: "home", directoryHint: .isDirectory)
        ).install(bundleURL: bundle)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )

        XCTAssertEqual(object["name"] as? String, BrowserAudioNativeHostInstaller.hostName)
        XCTAssertEqual(object["path"] as? String, executable.path)
        XCTAssertEqual(
            object["allowed_origins"] as? [String],
            [BrowserAudioProtocol.expectedExtensionOrigin]
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func pcmChunk(sequence: Int, frameCount: Int = 2) -> BrowserAudioPCMChunk {
        let samples = (0 ..< frameCount).flatMap { index -> [UInt8] in
            let sample = Int16(index.isMultiple(of: 2) ? 8_000 : -8_000)
            let littleEndian = sample.littleEndian
            return [UInt8(truncatingIfNeeded: littleEndian), UInt8(truncatingIfNeeded: littleEndian >> 8)]
        }
        return BrowserAudioPCMChunk(
            sessionID: sessionID,
            sequence: sequence,
            sampleRate: 48_000,
            channels: 1,
            frameCount: frameCount,
            pcmS16LE: Data(samples)
        )
    }

    private func startWireMessage() -> Data {
        json([
            "version": 1,
            "type": "start",
            "sessionId": sessionID.uuidString,
            "client": "googleMeetChrome",
            "tabId": 42
        ])
    }

    private func audioWireMessage(sequence: Int) -> Data {
        let chunk = pcmChunk(sequence: sequence)
        return json([
            "version": 1,
            "type": "audio",
            "sessionId": sessionID.uuidString,
            "sequence": sequence,
            "sampleRate": chunk.sampleRate,
            "channels": chunk.channels,
            "frameCount": chunk.frameCount,
            "pcmS16LE": chunk.pcmS16LE.base64EncodedString()
        ])
    }

    private func stopWireMessage() -> Data {
        json([
            "version": 1,
            "type": "stop",
            "sessionId": sessionID.uuidString,
            "reason": "user"
        ])
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sendNativeBody(_ body: Data, to descriptor: Int32) throws {
        var length = UInt32(body.count).littleEndian
        var framed = Data(bytes: &length, count: NativeMessagingFraming.headerByteCount)
        framed.append(body)
        try BrowserAudioSocketTransport.writeAll(framed, to: descriptor)
    }

    private func readNativeResponse(from descriptor: Int32) throws -> BrowserAudioNativeResponse {
        let body = try XCTUnwrap(BrowserAudioSocketTransport.readFrame(from: descriptor))
        return try JSONDecoder().decode(BrowserAudioNativeResponse.self, from: body)
    }
}

private final class LockedTestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func mutate(_ operation: (inout Value) -> Void) {
        lock.lock()
        operation(&storage)
        lock.unlock()
    }
}
