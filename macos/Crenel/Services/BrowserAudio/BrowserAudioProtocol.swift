import Foundation

enum BrowserAudioProtocol {
    static let version = 1
    static let expectedExtensionID = "cdoilhpndmdimjbnagfgldhkjojjjjha"
    static let expectedExtensionOrigin = "chrome-extension://\(expectedExtensionID)/"
    static let maximumNativeMessageBytes = 256 * 1_024
    static let maximumFramesPerChunk = 4_096
}

struct BrowserAudioPCMChunk: Codable, Equatable, Sendable {
    let sessionID: UUID
    let sequence: Int
    let sampleRate: Int
    let channels: Int
    let frameCount: Int
    let pcmS16LE: Data
}

enum BrowserAudioProtocolEvent: Equatable, Sendable {
    case start(sessionID: UUID, tabID: Int)
    case audio(BrowserAudioPCMChunk)
    case stop(sessionID: UUID, reason: String)
}

enum BrowserAudioProtocolError: Error, Equatable, Sendable {
    case untrustedOrigin
    case messageTooLarge
    case invalidJSON
    case unsupportedVersion
    case invalidSession
    case sessionAlreadyActive
    case sessionNotActive
    case unexpectedType
    case invalidField(String)
    case outOfSequence(expected: Int, actual: Int)
}

struct BrowserAudioProtocolValidator: Sendable {
    private var activeSessionID: UUID?
    private var nextSequence = 0

    mutating func validate(
        _ data: Data,
        extensionOrigin: String
    ) throws -> BrowserAudioProtocolEvent {
        guard extensionOrigin == BrowserAudioProtocol.expectedExtensionOrigin else {
            throw BrowserAudioProtocolError.untrustedOrigin
        }
        guard !data.isEmpty, data.count <= BrowserAudioProtocol.maximumNativeMessageBytes else {
            throw BrowserAudioProtocolError.messageTooLarge
        }

        let message: BrowserAudioWireMessage
        do {
            message = try JSONDecoder().decode(BrowserAudioWireMessage.self, from: data)
        } catch {
            throw BrowserAudioProtocolError.invalidJSON
        }
        guard message.version == BrowserAudioProtocol.version else {
            throw BrowserAudioProtocolError.unsupportedVersion
        }
        guard let sessionID = UUID(uuidString: message.sessionId) else {
            throw BrowserAudioProtocolError.invalidSession
        }

        switch message.type {
        case "start":
            guard activeSessionID == nil else {
                throw BrowserAudioProtocolError.sessionAlreadyActive
            }
            guard message.client == "googleMeetChrome" else {
                throw BrowserAudioProtocolError.invalidField("client")
            }
            guard let tabID = message.tabId, tabID > 0 else {
                throw BrowserAudioProtocolError.invalidField("tabId")
            }
            activeSessionID = sessionID
            nextSequence = 0
            return .start(sessionID: sessionID, tabID: tabID)

        case "audio":
            try requireActiveSession(sessionID)
            guard let sequence = message.sequence else {
                throw BrowserAudioProtocolError.invalidField("sequence")
            }
            guard sequence == nextSequence else {
                throw BrowserAudioProtocolError.outOfSequence(
                    expected: nextSequence,
                    actual: sequence
                )
            }
            guard let sampleRate = message.sampleRate,
                  (8_000 ... 192_000).contains(sampleRate) else {
                throw BrowserAudioProtocolError.invalidField("sampleRate")
            }
            guard let channels = message.channels,
                  (1 ... 2).contains(channels) else {
                throw BrowserAudioProtocolError.invalidField("channels")
            }
            guard let frameCount = message.frameCount,
                  (1 ... BrowserAudioProtocol.maximumFramesPerChunk).contains(frameCount) else {
                throw BrowserAudioProtocolError.invalidField("frameCount")
            }
            guard let encodedPCM = message.pcmS16LE,
                  let pcm = Data(base64Encoded: encodedPCM),
                  pcm.count == frameCount * channels * MemoryLayout<Int16>.size else {
                throw BrowserAudioProtocolError.invalidField("pcmS16LE")
            }

            nextSequence += 1
            return .audio(BrowserAudioPCMChunk(
                sessionID: sessionID,
                sequence: sequence,
                sampleRate: sampleRate,
                channels: channels,
                frameCount: frameCount,
                pcmS16LE: pcm
            ))

        case "stop":
            try requireActiveSession(sessionID)
            let allowedReasons = [
                "user",
                "tab-stopped",
                "tab-error",
                "tab-closed",
                "tab-navigated",
                "tab-stream-ended",
                "invalid-native-ack",
                "native-bridge-disconnected",
                "native-backpressure-or-pcm-error"
            ]
            guard let reason = message.reason, allowedReasons.contains(reason) else {
                throw BrowserAudioProtocolError.invalidField("reason")
            }
            activeSessionID = nil
            nextSequence = 0
            return .stop(sessionID: sessionID, reason: reason)

        default:
            throw BrowserAudioProtocolError.unexpectedType
        }
    }

    private func requireActiveSession(_ sessionID: UUID) throws {
        guard let activeSessionID else {
            throw BrowserAudioProtocolError.sessionNotActive
        }
        guard activeSessionID == sessionID else {
            throw BrowserAudioProtocolError.invalidSession
        }
    }
}

enum NativeMessagingFraming {
    static let headerByteCount = MemoryLayout<UInt32>.size

    static func messageLength(from header: Data) throws -> Int {
        guard header.count == headerByteCount else {
            throw BrowserAudioProtocolError.invalidField("nativeHeader")
        }
        return header.withUnsafeBytes { bytes in
            Int(bytes.loadUnaligned(as: UInt32.self).littleEndian)
        }
    }

    static func frame<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= BrowserAudioProtocol.maximumNativeMessageBytes else {
            throw BrowserAudioProtocolError.messageTooLarge
        }
        var length = UInt32(body.count).littleEndian
        var result = Data(bytes: &length, count: headerByteCount)
        result.append(body)
        return result
    }
}

struct BrowserAudioNativeResponse: Codable, Equatable, Sendable {
    let type: String
    let sessionId: String?
    let sequence: Int?
    let error: String?

    static func ready(sessionID: UUID) -> Self {
        Self(type: "ready", sessionId: sessionID.uuidString.lowercased(), sequence: nil, error: nil)
    }

    static func acknowledgement(sessionID: UUID, sequence: Int) -> Self {
        Self(
            type: "ack",
            sessionId: sessionID.uuidString.lowercased(),
            sequence: sequence,
            error: nil
        )
    }

    static func failure(_ code: String) -> Self {
        Self(type: "error", sessionId: nil, sequence: nil, error: code)
    }
}

struct BrowserAudioBridgeMessage: Codable, Equatable, Sendable {
    let version: Int
    let type: String
    let sessionId: String
    let tabId: Int?
    let sequence: Int?
    let sampleRate: Int?
    let channels: Int?
    let frameCount: Int?
    let pcmS16LE: Data?
    let reason: String?

    static func make(from event: BrowserAudioProtocolEvent) -> Self {
        switch event {
        case .start(let sessionID, let tabID):
            Self(
                version: BrowserAudioProtocol.version,
                type: "start",
                sessionId: sessionID.uuidString.lowercased(),
                tabId: tabID,
                sequence: nil,
                sampleRate: nil,
                channels: nil,
                frameCount: nil,
                pcmS16LE: nil,
                reason: nil
            )
        case .audio(let chunk):
            Self(
                version: BrowserAudioProtocol.version,
                type: "audio",
                sessionId: chunk.sessionID.uuidString.lowercased(),
                tabId: nil,
                sequence: chunk.sequence,
                sampleRate: chunk.sampleRate,
                channels: chunk.channels,
                frameCount: chunk.frameCount,
                pcmS16LE: chunk.pcmS16LE,
                reason: nil
            )
        case .stop(let sessionID, let reason):
            Self(
                version: BrowserAudioProtocol.version,
                type: "stop",
                sessionId: sessionID.uuidString.lowercased(),
                tabId: nil,
                sequence: nil,
                sampleRate: nil,
                channels: nil,
                frameCount: nil,
                pcmS16LE: nil,
                reason: reason
            )
        }
    }
}

struct BrowserAudioBridgeResponse: Codable, Equatable, Sendable {
    let type: String
    let sessionId: String?
    let sequence: Int?
    let error: String?

    static func ready(sessionID: UUID) -> Self {
        Self(type: "ready", sessionId: sessionID.uuidString.lowercased(), sequence: nil, error: nil)
    }

    static func acknowledgement(sessionID: UUID, sequence: Int) -> Self {
        Self(
            type: "ack",
            sessionId: sessionID.uuidString.lowercased(),
            sequence: sequence,
            error: nil
        )
    }

    static func stopped(sessionID: UUID) -> Self {
        Self(type: "stopped", sessionId: sessionID.uuidString.lowercased(), sequence: nil, error: nil)
    }

    static func failure(_ code: String) -> Self {
        Self(type: "error", sessionId: nil, sequence: nil, error: code)
    }
}

struct BrowserAudioNativeHostSession {
    typealias BridgeHandler = (BrowserAudioBridgeMessage) throws -> BrowserAudioBridgeResponse

    private var validator = BrowserAudioProtocolValidator()
    private let bridgeHandler: BridgeHandler

    init(bridgeHandler: @escaping BridgeHandler) {
        self.bridgeHandler = bridgeHandler
    }

    mutating func process(_ data: Data, extensionOrigin: String) -> BrowserAudioNativeResponse {
        do {
            let event = try validator.validate(data, extensionOrigin: extensionOrigin)
            let bridgeResponse = try bridgeHandler(.make(from: event))
            return try nativeResponse(for: event, bridgeResponse: bridgeResponse)
        } catch let error as BrowserAudioProtocolError {
            return .failure(Self.errorCode(for: error))
        } catch {
            return .failure("application-bridge-unavailable")
        }
    }

    private func nativeResponse(
        for event: BrowserAudioProtocolEvent,
        bridgeResponse: BrowserAudioBridgeResponse
    ) throws -> BrowserAudioNativeResponse {
        switch event {
        case .start(let sessionID, _):
            guard bridgeResponse == .ready(sessionID: sessionID) else {
                throw BrowserAudioProtocolError.invalidField("bridgeReady")
            }
            return .ready(sessionID: sessionID)
        case .audio(let chunk):
            guard bridgeResponse == .acknowledgement(
                sessionID: chunk.sessionID,
                sequence: chunk.sequence
            ) else {
                throw BrowserAudioProtocolError.invalidField("bridgeAck")
            }
            return .acknowledgement(sessionID: chunk.sessionID, sequence: chunk.sequence)
        case .stop(let sessionID, _):
            guard bridgeResponse == .stopped(sessionID: sessionID) else {
                throw BrowserAudioProtocolError.invalidField("bridgeStop")
            }
            return BrowserAudioNativeResponse(
                type: "stopped",
                sessionId: sessionID.uuidString.lowercased(),
                sequence: nil,
                error: nil
            )
        }
    }

    private static func errorCode(for error: BrowserAudioProtocolError) -> String {
        switch error {
        case .untrustedOrigin: "untrusted-origin"
        case .messageTooLarge: "message-too-large"
        case .invalidJSON: "invalid-json"
        case .unsupportedVersion: "unsupported-version"
        case .invalidSession: "invalid-session"
        case .sessionAlreadyActive: "session-already-active"
        case .sessionNotActive: "session-not-active"
        case .unexpectedType: "unexpected-type"
        case .invalidField: "invalid-field"
        case .outOfSequence: "out-of-sequence"
        }
    }
}

private struct BrowserAudioWireMessage: Decodable {
    let version: Int
    let type: String
    let sessionId: String
    let client: String?
    let tabId: Int?
    let sequence: Int?
    let sampleRate: Int?
    let channels: Int?
    let frameCount: Int?
    let pcmS16LE: String?
    let reason: String?
}
