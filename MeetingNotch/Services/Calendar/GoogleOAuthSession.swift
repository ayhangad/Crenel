import AppKit
import CryptoKit
import Network
import Security

struct GoogleOAuthGrant: Sendable {
    let code: String
    let redirectURI: String
    let verifier: String
}

enum GoogleCalendarError: Error, LocalizedError {
    case notConfigured, authorization, cancelled, unavailable, invalidResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Bu sürümün Google bağlantısı yayıncı tarafından henüz yapılandırılmadı. Bu Mac’in takvimlerini kullanabilirsiniz."
        case .authorization: "Google takvim bağlantısını yeniden yetkilendirin."
        case .cancelled: "Google bağlantısı iptal edildi veya zaman aşımına uğradı."
        case .unavailable: "Google takvimlerine ulaşılamadı. Bağlantınızı kontrol edin."
        case .invalidResponse: "Google takvim yanıtı okunamadı. Tekrar deneyin."
        }
    }
}

@MainActor
final class GoogleOAuthSession {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<GoogleOAuthGrant, Error>?
    private var timeout: Task<Void, Never>?
    private var redirectURI = ""
    private var verifier = ""
    private var state = ""
    private var connections: [NWConnection] = []

    static func authorize(clientID: String) async throws -> GoogleOAuthGrant {
        let session = GoogleOAuthSession()
        return try await session.run(clientID: clientID)
    }

    nonisolated static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func callbackCode(requestLine: String, expectedState: String) throws -> String {
        let components = requestLine.split(separator: " ")
        guard components.count == 3, components[0] == "GET",
              let url = URLComponents(string: "http://127.0.0.1" + components[1]),
              url.path == "/oauth/callback" else { throw GoogleCalendarError.authorization }
        let items = url.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, !items.contains(where: { $0.name == "error" }) else {
            throw GoogleCalendarError.authorization
        }
        return code
    }

    private func run(clientID: String) async throws -> GoogleOAuthGrant {
        verifier = try randomString()
        state = try randomString()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                listener?.stateUpdateHandler = { [weak self] status in
                    Task { @MainActor in
                        guard let self else { return }
                        switch status {
                        case .ready:
                            guard self.redirectURI.isEmpty, let port = self.listener?.port else { return }
                            self.redirectURI = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
                            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                            url.queryItems = [
                                .init(name: "client_id", value: clientID),
                                .init(name: "redirect_uri", value: self.redirectURI),
                                .init(name: "response_type", value: "code"),
                                .init(name: "scope", value: "https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly"),
                                .init(name: "state", value: self.state),
                                .init(name: "code_challenge", value: Self.challenge(for: self.verifier)),
                                .init(name: "code_challenge_method", value: "S256"),
                                .init(name: "access_type", value: "offline"),
                                .init(name: "prompt", value: "consent")
                            ]
                            guard let url = url.url, NSWorkspace.shared.open(url) else {
                                self.finish(.failure(GoogleCalendarError.unavailable)); return
                            }
                        case .failed: self.finish(.failure(GoogleCalendarError.unavailable))
                        default: break
                        }
                    }
                }
                listener?.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.accept(connection) }
                }
                listener?.start(queue: .main)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(180)) }
                    catch { return }
                    self?.finish(.failure(GoogleCalendarError.cancelled))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(GoogleCalendarError.cancelled)) }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8, continuation != nil else { connection.cancel(); return }
        connections.append(connection)
        connection.start(queue: .main)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard bytes.count <= 16_384, error == nil else { self.close(connection); return }
                if let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") {
                    let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                    let code = try? Self.callbackCode(requestLine: firstLine, expectedState: self.state)
                    let target = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let callback = URLComponents(string: "http://127.0.0.1" + target)
                    let denied = callback?.path == "/oauth/callback"
                        && callback?.queryItems?.first(where: { $0.name == "state" })?.value == self.state
                        && callback?.queryItems?.contains(where: { $0.name == "error" }) == true
                    let body = code == nil ? "Baglanti dogrulanamadi. Bu pencereyi kapatabilirsiniz." : "MeetingNotch'a donebilirsiniz. Bu pencereyi kapatabilirsiniz."
                    let response = "HTTP/1.1 \(code == nil ? "400 Bad Request" : "200 OK")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        Task { @MainActor in
                            self.close(connection)
                            if let code {
                                self.finish(.success(GoogleOAuthGrant(code: code, redirectURI: self.redirectURI, verifier: self.verifier)))
                            } else if denied { self.finish(.failure(GoogleCalendarError.cancelled)) }
                        }
                    })
                } else if !complete { self.receive(connection, accumulated: bytes) }
                else { self.close(connection) }
            }
        }
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    private func finish(_ result: Result<GoogleOAuthGrant, Error>) {
        let pending = continuation
        continuation = nil
        listener?.cancel(); listener = nil
        timeout?.cancel(); timeout = nil
        connections.forEach { $0.cancel() }; connections = []
        verifier = ""; state = ""
        pending?.resume(with: result)
    }

    private func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GoogleCalendarError.unavailable
        }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
