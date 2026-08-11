import Darwin
import Foundation

final class BrowserAudioIPCServer: @unchecked Sendable {
    private let broker: BrowserAudioStreamBroker
    private let queue = DispatchQueue(label: "gad.MeetingNotch.browser-audio.ipc")
    private let stateLock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var clientDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?

    init(broker: BrowserAudioStreamBroker) {
        self.broker = broker
    }

    func start() throws {
        try BrowserAudioSocketEndpoint.prepareDirectory()
        let socketPath = BrowserAudioSocketEndpoint.socketURL.path
        unlink(socketPath)

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BrowserAudioSocketTransportError.systemCall("socket", errno)
        }
        do {
            var address = try BrowserAudioSocketTransport.makeAddress(path: socketPath)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            guard bindResult == 0 else {
                throw BrowserAudioSocketTransportError.systemCall("bind", errno)
            }
            guard chmod(socketPath, 0o600) == 0 else {
                throw BrowserAudioSocketTransportError.systemCall("chmod", errno)
            }
            guard Darwin.listen(descriptor, 1) == 0 else {
                throw BrowserAudioSocketTransportError.systemCall("listen", errno)
            }

            stateLock.withIPCStateLock { listenerDescriptor = descriptor }
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptConnection() }
            listenerSource = source
            source.resume()
        } catch {
            Darwin.close(descriptor)
            unlink(socketPath)
            throw error
        }
    }

    func stop() {
        let descriptors = stateLock.withIPCStateLock { () -> (Int32, Int32) in
            let result = (listenerDescriptor, clientDescriptor)
            listenerDescriptor = -1
            clientDescriptor = -1
            return result
        }
        listenerSource?.setEventHandler {}
        listenerSource?.cancel()
        listenerSource = nil
        if descriptors.1 >= 0 {
            Darwin.shutdown(descriptors.1, SHUT_RDWR)
            Darwin.close(descriptors.1)
        }
        if descriptors.0 >= 0 { Darwin.close(descriptors.0) }
        unlink(BrowserAudioSocketEndpoint.socketURL.path)
        broker.bridgeDisconnected()
    }

    private func acceptConnection() {
        let listener = stateLock.withIPCStateLock { listenerDescriptor }
        guard listener >= 0 else { return }
        let descriptor = Darwin.accept(listener, nil, nil)
        guard descriptor >= 0 else { return }
        do {
            try BrowserAudioSocketTransport.disableSIGPIPE(on: descriptor)
        } catch {
            Darwin.close(descriptor)
            return
        }

        let accepted = stateLock.withIPCStateLock { () -> Bool in
            guard clientDescriptor < 0 else { return false }
            clientDescriptor = descriptor
            return true
        }
        guard accepted else {
            Darwin.close(descriptor)
            return
        }
        queue.async { [weak self] in self?.serve(descriptor) }
    }

    private func serve(_ descriptor: Int32) {
        defer {
            let wasCurrent = stateLock.withIPCStateLock { () -> Bool in
                guard clientDescriptor == descriptor else { return false }
                clientDescriptor = -1
                return true
            }
            Darwin.close(descriptor)
            if wasCurrent { broker.bridgeDisconnected() }
        }

        do {
            while let body = try BrowserAudioSocketTransport.readFrame(from: descriptor) {
                let message = try JSONDecoder().decode(BrowserAudioBridgeMessage.self, from: body)
                let response = try broker.handle(message)
                try BrowserAudioSocketTransport.writeFrame(response, to: descriptor)
            }
        } catch {
            try? BrowserAudioSocketTransport.writeFrame(
                BrowserAudioBridgeResponse.failure("invalid-application-bridge-message"),
                to: descriptor
            )
        }
    }
}

private extension NSLock {
    func withIPCStateLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
