import Foundation

enum BrowserAudioStreamBrokerError: Error, Equatable {
    case unsupportedVersion
    case invalidSession
    case invalidMessage
    case sessionAlreadyActive
    case sessionNotActive
    case outOfSequence(expected: Int, actual: Int)
    case consumerAlreadyAttached
}

enum BrowserAudioConnectionStatus: Equatable, Sendable {
    case unavailable
    case waitingForMeetTab
    case tabConnected
    case recording
}

final class BrowserAudioStreamBroker: @unchecked Sendable {
    typealias PCMConsumer = @Sendable (BrowserAudioPCMChunk) throws -> Void
    typealias DisconnectHandler = @Sendable () -> Void

    private struct Consumer {
        let sessionID: UUID
        let consume: PCMConsumer
        let disconnected: DisconnectHandler
    }

    private let lock = NSLock()
    private var activeSessionID: UUID?
    private var nextSequence = 0
    private var consumer: Consumer?
    private var statusHandler: (@Sendable (BrowserAudioConnectionStatus) -> Void)?

    var hasActiveSession: Bool {
        lock.withBrowserAudioLock { activeSessionID != nil }
    }

    func setStatusHandler(
        _ handler: (@Sendable (BrowserAudioConnectionStatus) -> Void)?
    ) {
        lock.withBrowserAudioLock { statusHandler = handler }
    }

    func handle(_ message: BrowserAudioBridgeMessage) throws -> BrowserAudioBridgeResponse {
        guard message.version == BrowserAudioProtocol.version else {
            throw BrowserAudioStreamBrokerError.unsupportedVersion
        }
        guard let sessionID = UUID(uuidString: message.sessionId) else {
            throw BrowserAudioStreamBrokerError.invalidSession
        }

        switch message.type {
        case "start":
            return try start(sessionID: sessionID, tabID: message.tabId)
        case "audio":
            return try audio(sessionID: sessionID, message: message)
        case "stop":
            return try stop(sessionID: sessionID)
        default:
            throw BrowserAudioStreamBrokerError.invalidMessage
        }
    }

    func attachConsumer(
        consume: @escaping PCMConsumer,
        disconnected: @escaping DisconnectHandler
    ) throws -> UUID {
        let sessionID = try lock.withBrowserAudioLock {
            guard let activeSessionID else {
                throw BrowserAudioStreamBrokerError.sessionNotActive
            }
            guard consumer == nil else {
                throw BrowserAudioStreamBrokerError.consumerAlreadyAttached
            }
            consumer = Consumer(
                sessionID: activeSessionID,
                consume: consume,
                disconnected: disconnected
            )
            return activeSessionID
        }
        publishStatus(.recording)
        return sessionID
    }

    func detachConsumer(sessionID: UUID) {
        let remainsConnected = lock.withBrowserAudioLock { () -> Bool in
            guard consumer?.sessionID == sessionID else { return false }
            consumer = nil
            return activeSessionID != nil
        }
        if remainsConnected { publishStatus(.tabConnected) }
    }

    func bridgeDisconnected() {
        let disconnect = lock.withBrowserAudioLock { () -> DisconnectHandler? in
            let handler = consumer?.disconnected
            activeSessionID = nil
            nextSequence = 0
            consumer = nil
            return handler
        }
        disconnect?()
        publishStatus(.waitingForMeetTab)
    }

    private func start(sessionID: UUID, tabID: Int?) throws -> BrowserAudioBridgeResponse {
        let response: BrowserAudioBridgeResponse = try lock.withBrowserAudioLock {
            guard activeSessionID == nil, consumer == nil else {
                throw BrowserAudioStreamBrokerError.sessionAlreadyActive
            }
            guard let tabID, tabID > 0 else {
                throw BrowserAudioStreamBrokerError.invalidMessage
            }
            activeSessionID = sessionID
            nextSequence = 0
            return .ready(sessionID: sessionID)
        }
        publishStatus(.tabConnected)
        return response
    }

    private func audio(
        sessionID: UUID,
        message: BrowserAudioBridgeMessage
    ) throws -> BrowserAudioBridgeResponse {
        let delivery = try lock.withBrowserAudioLock { () -> (BrowserAudioPCMChunk, PCMConsumer?) in
            guard activeSessionID == sessionID else {
                throw BrowserAudioStreamBrokerError.sessionNotActive
            }
            guard let sequence = message.sequence,
                  let sampleRate = message.sampleRate,
                  let channels = message.channels,
                  let frameCount = message.frameCount,
                  let pcm = message.pcmS16LE,
                  sequence == nextSequence,
                  (8_000 ... 192_000).contains(sampleRate),
                  (1 ... 2).contains(channels),
                  (1 ... BrowserAudioProtocol.maximumFramesPerChunk).contains(frameCount),
                  pcm.count == frameCount * channels * MemoryLayout<Int16>.size else {
                if let sequence = message.sequence, sequence != nextSequence {
                    throw BrowserAudioStreamBrokerError.outOfSequence(
                        expected: nextSequence,
                        actual: sequence
                    )
                }
                throw BrowserAudioStreamBrokerError.invalidMessage
            }
            let chunk = BrowserAudioPCMChunk(
                sessionID: sessionID,
                sequence: sequence,
                sampleRate: sampleRate,
                channels: channels,
                frameCount: frameCount,
                pcmS16LE: pcm
            )
            nextSequence += 1
            return (chunk, consumer?.consume)
        }

        do {
            try delivery.1?(delivery.0)
        } catch {
            bridgeDisconnected()
            throw error
        }
        return .acknowledgement(sessionID: sessionID, sequence: delivery.0.sequence)
    }

    private func stop(sessionID: UUID) throws -> BrowserAudioBridgeResponse {
        let disconnect = try lock.withBrowserAudioLock { () -> DisconnectHandler? in
            guard activeSessionID == sessionID else {
                throw BrowserAudioStreamBrokerError.sessionNotActive
            }
            let handler = consumer?.disconnected
            activeSessionID = nil
            nextSequence = 0
            consumer = nil
            return handler
        }
        disconnect?()
        publishStatus(.waitingForMeetTab)
        return .stopped(sessionID: sessionID)
    }

    private func publishStatus(_ status: BrowserAudioConnectionStatus) {
        let handler = lock.withBrowserAudioLock { statusHandler }
        handler?(status)
    }
}

private extension NSLock {
    func withBrowserAudioLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
