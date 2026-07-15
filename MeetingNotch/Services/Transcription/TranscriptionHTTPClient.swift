import Foundation

struct TranscriptionHTTPResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol TranscriptionHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> TranscriptionHTTPResponse
    func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionHTTPResponse
}

struct URLSessionTranscriptionHTTPClient: TranscriptionHTTPClient, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> TranscriptionHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranscriptionServiceError.invalidResponse
        }
        return TranscriptionHTTPResponse(data: data, response: response)
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionHTTPResponse {
        let delegate = UploadProgressDelegate(progress: progress)
        let (data, response) = try await session.upload(
            for: request,
            fromFile: fileURL,
            delegate: delegate
        )
        guard let response = response as? HTTPURLResponse else {
            throw TranscriptionServiceError.invalidResponse
        }
        return TranscriptionHTTPResponse(data: data, response: response)
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: TranscriptionUploadProgress

    init(progress: @escaping TranscriptionUploadProgress) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0), 1))
    }
}

struct MultipartFormFileBuilder: Sendable {
    static let temporaryFilePrefix = "MeetingNotch-Upload-"

    struct Field: Sendable {
        let name: String
        let value: String
    }

    func build(
        fields: [Field],
        fileFieldName: String,
        sourceFileURL: URL,
        mimeType: String,
        boundary: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory.appending(
            path: "\(Self.temporaryFilePrefix)\(UUID().uuidString).multipart"
        )
        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw TranscriptionServiceError.invalidFile(.unreadable)
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            for field in fields {
                try output.write(contentsOf: Data(
                    "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n\(field.value)\r\n".utf8
                ))
            }

            let safeFileName = sourceFileURL.lastPathComponent
                .replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "\r", with: "_")
                .replacingOccurrences(of: "\n", with: "_")
            try output.write(contentsOf: Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(safeFileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8
            ))

            let input = try FileHandle(forReadingFrom: sourceFileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                if Task.isCancelled { throw CancellationError() }
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try output.synchronize()
            return outputURL
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    static func removeStaleUploadBodies(fileManager: FileManager = .default) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix(temporaryFilePrefix) {
            try? fileManager.removeItem(at: file)
        }
    }
}
