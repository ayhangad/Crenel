import Darwin
import Foundation

enum BrowserAudioSocketTransportError: Error {
    case invalidPath
    case systemCall(String, Int32)
    case connectionClosed
    case invalidFrameLength
}

enum BrowserAudioSocketEndpoint {
    static var directoryURL: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "meetingnotch-browser-audio-\(getuid())", directoryHint: .isDirectory)
    }

    static var socketURL: URL {
        directoryURL.appending(path: "bridge.sock")
    }

    static func prepareDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }
}

enum BrowserAudioSocketTransport {
    static func makeAddress(path: String) throws -> sockaddr_un {
        let pathBytes = Array(path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw BrowserAudioSocketTransportError.invalidPath
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            path.withCString { source in
                _ = strlcpy(destination, source, pathBytes.count)
            }
        }
        return address
    }

    static func connect(to url: URL) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw systemError("socket")
        }
        do {
            try disableSIGPIPE(on: descriptor)
            var address = try makeAddress(path: url.path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            guard result == 0 else { throw systemError("connect") }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func disableSIGPIPE(on descriptor: Int32) throws {
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw systemError("setsockopt")
        }
    }

    static func readFrame(from descriptor: Int32) throws -> Data? {
        guard let header = try readExactly(
            byteCount: NativeMessagingFraming.headerByteCount,
            from: descriptor,
            allowsCleanEOF: true
        ) else { return nil }
        let length = try NativeMessagingFraming.messageLength(from: header)
        guard length > 0, length <= BrowserAudioProtocol.maximumNativeMessageBytes else {
            throw BrowserAudioSocketTransportError.invalidFrameLength
        }
        return try readExactly(byteCount: length, from: descriptor, allowsCleanEOF: false)
    }

    static func writeFrame<T: Encodable>(_ value: T, to descriptor: Int32) throws {
        try writeAll(NativeMessagingFraming.frame(value), to: descriptor)
    }

    static func readExactly(
        byteCount: Int,
        from descriptor: Int32,
        allowsCleanEOF: Bool
    ) throws -> Data? {
        var result = Data(count: byteCount)
        var offset = 0
        while offset < byteCount {
            let count = result.withUnsafeMutableBytes { bytes in
                Darwin.read(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    byteCount - offset
                )
            }
            if count == 0 {
                if allowsCleanEOF, offset == 0 { return nil }
                throw BrowserAudioSocketTransportError.connectionClosed
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemError("read")
            }
            offset += count
        }
        return result
    }

    static func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes in
                Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    data.count - offset
                )
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemError("write")
            }
            guard count > 0 else {
                throw BrowserAudioSocketTransportError.connectionClosed
            }
            offset += count
        }
    }

    private static func systemError(_ operation: String) -> BrowserAudioSocketTransportError {
        .systemCall(operation, errno)
    }
}
