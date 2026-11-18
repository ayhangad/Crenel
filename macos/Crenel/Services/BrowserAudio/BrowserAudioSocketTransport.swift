import Darwin
import Foundation
import Security

enum BrowserAudioSocketTransportError: Error {
    case untrustedPeer
    case invalidPath
    case systemCall(String, Int32)
    case connectionClosed
    case invalidFrameLength
}

/// Identify the live peer by its kernel-issued audit token, including the PID version.
enum BrowserAudioSocketPeer {
    case nativeHost, application

    func verify(on descriptor: Int32) throws {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout.size(ofValue: token))
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
              length == MemoryLayout.size(ofValue: token) else {
            throw BrowserAudioSocketTransportError.untrustedPeer
        }
        let auditData = Data(bytes: &token, count: Int(length))
        let attributes = [kSecGuestAttributeAudit as String: auditData] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest, let rule = signingRule() else {
            throw BrowserAudioSocketTransportError.untrustedPeer
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else {
            throw BrowserAudioSocketTransportError.untrustedPeer
        }
    }

    /// Release builds also require a Developer ID certificate, so a development-signed
    /// build from the same team can't stand in for the shipped app or helper.
    static func teamRule(identifier: String, team: String, requireDeveloperID: Bool) -> String {
        var rule = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        if requireDeveloperID {
            rule += " and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        }
        return rule
    }

    private func signingRule() -> String? {
        var ownCode: SecCode?
        var ownStaticCode: SecStaticCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
              SecCodeCopyStaticCode(ownCode, [], &ownStaticCode) == errSecSuccess,
              let ownStaticCode else { return nil }
        if let team = signingInfo(ownStaticCode)?[kSecCodeInfoTeamIdentifier as String] as? String,
           team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil {
            let identifier = self == .nativeHost ? "gad.Crenel.BrowserAudioHost" : "gad.Crenel"
            #if DEBUG
            return Self.teamRule(identifier: identifier, team: team, requireDeveloperID: false)
            #else
            return Self.teamRule(identifier: identifier, team: team, requireDeveloperID: true)
            #endif
        }
        #if DEBUG
        // Ad-hoc development builds have no team. Pin the exact sibling build's CodeDirectory.
        let peerURL: URL
        switch self {
        case .nativeHost:
            peerURL = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchServices/CrenelBrowserAudioHost")
        case .application:
            guard let hostURL = Bundle.main.executableURL else { return nil }
            let contents = hostURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            peerURL = contents.appending(path: "MacOS/Crenel")
        }
        var expected: SecStaticCode?
        guard SecStaticCodeCreateWithPath(peerURL as CFURL, [], &expected) == errSecSuccess,
              let expected, let hash = signingInfo(expected)?[kSecCodeInfoUnique as String] as? Data,
              !hash.isEmpty else { return nil }
        return "cdhash H\"" + hash.map { String(format: "%02x", $0) }.joined() + "\""
        #else
        return nil
        #endif
    }

    private func signingInfo(_ code: SecStaticCode) -> [String: Any]? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else {
            return nil
        }
        return info as? [String: Any]
    }
}

enum BrowserAudioSocketEndpoint {
    static var directoryURL: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "crenel-browser-audio-\(getuid())", directoryHint: .isDirectory)
    }

    static var socketURL: URL {
        directoryURL.appending(path: "bridge.sock")
    }

    static func prepareDirectory(_ directoryURL: URL, fileManager: FileManager = .default) throws {
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
