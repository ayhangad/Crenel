import Foundation
import XCTest
@testable import MeetingNotch

final class BrowserAudioProtocolTests: XCTestCase {
    private let origin = BrowserAudioProtocol.expectedExtensionOrigin
    private let sessionID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    func testRejectsUntrustedExtensionOriginBeforeParsingPayload() {
        var validator = BrowserAudioProtocolValidator()

        XCTAssertThrowsError(
            try validator.validate(Data("{}".utf8), extensionOrigin: "chrome-extension://evil/")
        ) {
            XCTAssertEqual($0 as? BrowserAudioProtocolError, .untrustedOrigin)
        }
    }

    func testAcceptsStartAndExactSequentialPCMChunk() throws {
        var validator = BrowserAudioProtocolValidator()
        XCTAssertEqual(
            try validator.validate(startMessage(), extensionOrigin: origin),
            .start(sessionID: sessionID, tabID: 42)
        )

        let pcm = Data([0x00, 0x80, 0xFF, 0x7F])
        XCTAssertEqual(
            try validator.validate(audioMessage(sequence: 0, pcm: pcm), extensionOrigin: origin),
            .audio(BrowserAudioPCMChunk(
                sessionID: sessionID,
                sequence: 0,
                sampleRate: 48_000,
                channels: 1,
                frameCount: 2,
                pcmS16LE: pcm
            ))
        )
    }

    func testRejectsOutOfOrderAndMismatchedPCMWithoutAdvancingSequence() throws {
        var validator = BrowserAudioProtocolValidator()
        _ = try validator.validate(startMessage(), extensionOrigin: origin)

        XCTAssertThrowsError(
            try validator.validate(
                audioMessage(sequence: 1, pcm: Data(repeating: 0, count: 4)),
                extensionOrigin: origin
            )
        ) {
            XCTAssertEqual(
                $0 as? BrowserAudioProtocolError,
                .outOfSequence(expected: 0, actual: 1)
            )
        }
        XCTAssertThrowsError(
            try validator.validate(
                audioMessage(sequence: 0, frameCount: 4, pcm: Data(repeating: 0, count: 4)),
                extensionOrigin: origin
            )
        ) {
            XCTAssertEqual($0 as? BrowserAudioProtocolError, .invalidField("pcmS16LE"))
        }
        XCTAssertNoThrow(try validator.validate(
            audioMessage(sequence: 0, pcm: Data(repeating: 0, count: 4)),
            extensionOrigin: origin
        ))
    }

    func testStopClosesSessionAndRejectsFurtherAudio() throws {
        var validator = BrowserAudioProtocolValidator()
        _ = try validator.validate(startMessage(), extensionOrigin: origin)
        XCTAssertEqual(
            try validator.validate(stopMessage(), extensionOrigin: origin),
            .stop(sessionID: sessionID, reason: "user")
        )

        XCTAssertThrowsError(
            try validator.validate(
                audioMessage(sequence: 0, pcm: Data(repeating: 0, count: 4)),
                extensionOrigin: origin
            )
        ) {
            XCTAssertEqual($0 as? BrowserAudioProtocolError, .sessionNotActive)
        }
    }

    func testNativeFramingUsesLittleEndianLengthAndEnforcesLimit() throws {
        let response = BrowserAudioNativeResponse.acknowledgement(
            sessionID: sessionID,
            sequence: 7
        )
        let framed = try NativeMessagingFraming.frame(response)
        let header = framed.prefix(NativeMessagingFraming.headerByteCount)
        let length = try NativeMessagingFraming.messageLength(from: Data(header))

        XCTAssertEqual(length, framed.count - NativeMessagingFraming.headerByteCount)
        XCTAssertEqual(
            try JSONDecoder().decode(
                BrowserAudioNativeResponse.self,
                from: Data(framed.dropFirst(NativeMessagingFraming.headerByteCount))
            ),
            response
        )
        var validator = BrowserAudioProtocolValidator()
        XCTAssertThrowsError(
            try validator.validate(
                Data(repeating: 0, count: BrowserAudioProtocol.maximumNativeMessageBytes + 1),
                extensionOrigin: origin
            )
        ) {
            XCTAssertEqual($0 as? BrowserAudioProtocolError, .messageTooLarge)
        }
    }

    private func startMessage() -> Data {
        json([
            "version": 1,
            "type": "start",
            "sessionId": sessionID.uuidString,
            "client": "googleMeetChrome",
            "tabId": 42
        ])
    }

    private func audioMessage(
        sequence: Int,
        frameCount: Int = 2,
        pcm: Data
    ) -> Data {
        json([
            "version": 1,
            "type": "audio",
            "sessionId": sessionID.uuidString,
            "sequence": sequence,
            "sampleRate": 48_000,
            "channels": 1,
            "frameCount": frameCount,
            "pcmS16LE": pcm.base64EncodedString()
        ])
    }

    private func stopMessage() -> Data {
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
}
