import Darwin
import Foundation

private final class ApplicationBridgeClient {
    private var descriptor: Int32 = -1

    deinit { close() }

    func send(_ message: BrowserAudioBridgeMessage) throws -> BrowserAudioBridgeResponse {
        if descriptor < 0 {
            descriptor = try BrowserAudioSocketTransport.connect(
                to: BrowserAudioSocketEndpoint.socketURL
            )
        }
        try BrowserAudioSocketTransport.writeFrame(message, to: descriptor)
        guard let responseData = try BrowserAudioSocketTransport.readFrame(from: descriptor) else {
            throw BrowserAudioSocketTransportError.connectionClosed
        }
        return try JSONDecoder().decode(BrowserAudioBridgeResponse.self, from: responseData)
    }

    func close() {
        guard descriptor >= 0 else { return }
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
        descriptor = -1
    }
}

private let extensionOrigin = CommandLine.arguments.dropFirst().first ?? ""
private let bridge = ApplicationBridgeClient()
private var session = BrowserAudioNativeHostSession { message in
    try bridge.send(message)
}

do {
    while let message = try BrowserAudioSocketTransport.readFrame(from: STDIN_FILENO) {
        let response = session.process(message, extensionOrigin: extensionOrigin)
        try BrowserAudioSocketTransport.writeFrame(response, to: STDOUT_FILENO)
        if response.type == "error" || response.type == "stopped" { break }
    }
} catch {
    try? BrowserAudioSocketTransport.writeFrame(
        BrowserAudioNativeResponse.failure("native-host-io-failure"),
        to: STDOUT_FILENO
    )
}
bridge.close()
