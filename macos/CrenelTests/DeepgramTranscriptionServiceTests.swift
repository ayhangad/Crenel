import Foundation
import XCTest
@testable import Crenel

final class DeepgramTranscriptionServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "Crenel-DeepgramTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUploadSendsRawAudioWithTokenNova3DiarizationAndTurkish() async throws {
        let audioURL = try audioFile()
        let client = DeepgramMockHTTPClient(uploadResponse: try response(statusCode: 200, data: utterancesFixture()))
        let service = DeepgramTranscriptionService(
            apiKeyRepository: DeepgramStubKeys(apiKey: " dg-key "),
            httpClient: client,
            endpoint: URL(string: "https://example.test/v1/listen")!
        )

        let result = try await service.transcribe(
            TranscriptionRequest(audioFileURL: audioURL, languageCode: "TR"),
            uploadProgress: { _ in }
        )

        let captured = await client.lastUploadRequest()
        let request = try XCTUnwrap(captured)
        let uploadedFile = await client.lastUploadFileURL()
        XCTAssertEqual(uploadedFile, audioURL, "Audio goes up as is, without a multipart copy")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token dg-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        let query = try queryItems(request)
        XCTAssertEqual(query["model"], "nova-3")
        XCTAssertEqual(query["diarize"], "true")
        XCTAssertEqual(query["utterances"], "true")
        XCTAssertEqual(query["smart_format"], "true")
        XCTAssertEqual(query["language"], "tr")
        XCTAssertNil(query["detect_language"])

        XCTAssertEqual(result.transcript.languageCode, "tr")
        XCTAssertEqual(result.transcript.segments.map(\.speakerID), ["speaker_0", "speaker_1"])
        XCTAssertEqual(result.transcript.segments.map(\.text), ["Merhaba dünya. Nasılsın?", "İyiyim."])
        XCTAssertEqual(result.transcript.segments[0].startTime, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.transcript.segments[0].endTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.transcript.segments[1].startTime, 2.2, accuracy: 0.001)
    }

    func testAutomaticLanguageAsksDeepgramToDetect() async throws {
        let client = DeepgramMockHTTPClient(uploadResponse: try response(statusCode: 200, data: utterancesFixture()))
        let service = DeepgramTranscriptionService(apiKeyRepository: DeepgramStubKeys(apiKey: "k"), httpClient: client)

        _ = try await service.transcribe(
            TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
            uploadProgress: { _ in }
        )

        let captured = await client.lastUploadRequest()
        let query = try queryItems(try XCTUnwrap(captured))
        XCTAssertEqual(query["detect_language"], "true")
        XCTAssertNil(query["language"])
    }

    func testWordsAreTheFallbackWhenUtterancesAreMissing() throws {
        let data = Data(#"""
        {"results":{"channels":[{"alternatives":[{"transcript":"selam evet tamam","words":[
          {"word":"selam","punctuated_word":"Selam.","start":0.0,"end":0.4,"speaker":0},
          {"word":"evet","punctuated_word":"Evet,","start":0.6,"end":0.9,"speaker":1},
          {"word":"tamam","punctuated_word":"tamam.","start":0.9,"end":1.3,"speaker":1}
        ]}]}]}}
        """#.utf8)

        let transcript = try DeepgramTranscriptParser().parse(data)

        XCTAssertEqual(transcript.segments.map(\.speakerID), ["speaker_0", "speaker_1"])
        XCTAssertEqual(transcript.segments.map(\.text), ["Selam.", "Evet, tamam."])
        XCTAssertNil(transcript.languageCode)
    }

    func testEmptyOrMalformedResponseIsInvalid() {
        for json in [#"{"results":{"channels":[]}}"#,
                     #"{"results":{"channels":[{"alternatives":[{"transcript":"","words":[]}]}]}}"#,
                     "not json"] {
            XCTAssertThrowsError(try DeepgramTranscriptParser().parse(Data(json.utf8))) { error in
                XCTAssertEqual(error as? TranscriptionServiceError, .invalidResponse)
            }
        }
    }

    func testMissingKeyFailsBeforeUploading() async throws {
        let client = DeepgramMockHTTPClient()
        let service = DeepgramTranscriptionService(apiKeyRepository: DeepgramStubKeys(apiKey: nil), httpClient: client)

        do {
            _ = try await service.transcribe(
                TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
                uploadProgress: { _ in }
            )
            XCTFail("A missing key must not upload audio.")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .authentication)
        }
        let captured = await client.lastUploadRequest()
        XCTAssertNil(captured)
    }

    func testHTTPFailuresAreNormalized() async throws {
        let cases: [(Int, [String: String], TranscriptionServiceError)] = [
            (401, [:], .authentication),
            (403, [:], .authentication),
            (429, ["Retry-After": "12"], .rateLimited(retryAfter: 12)),
            (503, [:], .providerUnavailable),
            (400, [:], .invalidResponse)
        ]
        for (status, headers, expected) in cases {
            let client = DeepgramMockHTTPClient(uploadResponse: try response(statusCode: status, data: Data(), headers: headers))
            let service = DeepgramTranscriptionService(apiKeyRepository: DeepgramStubKeys(apiKey: "k"), httpClient: client)
            do {
                _ = try await service.transcribe(
                    TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
                    uploadProgress: { _ in }
                )
                XCTFail("HTTP \(status) must fail.")
            } catch {
                XCTAssertEqual(error as? TranscriptionServiceError, expected, "HTTP \(status)")
            }
        }
    }

    func testKeyValidatorReadsTokenDetailsWithoutUploadingAudio() async throws {
        let client = DeepgramMockHTTPClient(dataResponse: try response(
            statusCode: 200,
            data: Data(#"{"api_key_id":"abc","scopes":["usage:write"]}"#.utf8)
        ))
        try await DeepgramAPIKeyValidator(httpClient: client).validate(" key ")

        let captured = await client.lastDataRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.path, "/v1/auth/token")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token key")
        XCTAssertNil(request.httpBody)
        let uploaded = await client.lastUploadRequest()
        XCTAssertNil(uploaded)
    }

    func testKeyValidatorRejectsUnauthorizedKey() async throws {
        let client = DeepgramMockHTTPClient(dataResponse: try response(statusCode: 401, data: Data()))
        do {
            try await DeepgramAPIKeyValidator(httpClient: client).validate("bad")
            XCTFail("401 must not be accepted.")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .authentication)
        }
    }

    func testRouterSendsDeepgramChoiceToDeepgram() async throws {
        let deepgram = DeepgramRecordingService()
        let other = DeepgramRecordingService()
        let router = MeetingTranscriptionRouter(
            preferences: { MeetingProcessingPreferences(transcription: .deepgram) },
            elevenLabs: other,
            deepgram: deepgram,
            onDevice: other
        )

        _ = try await router.transcribe(
            TranscriptionRequest(audioFileURL: try audioFile(), languageCode: nil),
            uploadProgress: { _ in }
        )

        let deepgramCalls = await deepgram.calls()
        let otherCalls = await other.calls()
        XCTAssertEqual(deepgramCalls, 1)
        XCTAssertEqual(otherCalls, 0)
    }

    func testDeepgramPreferenceRoundTripsAndUnknownFallsBack() throws {
        let encoded = try JSONEncoder().encode(MeetingProcessingPreferences(transcription: .deepgram))
        XCTAssertEqual(try JSONDecoder().decode(MeetingProcessingPreferences.self, from: encoded).transcription, .deepgram)
        let unknown = Data(#"{"transcription":"someFutureProvider"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(MeetingProcessingPreferences.self, from: unknown).transcription, .onDevice)
    }

    // MARK: Helpers

    private func audioFile() throws -> URL {
        let url = root.appending(path: "meeting.m4a")
        try Data("fake-m4a-audio".utf8).write(to: url)
        return url
    }

    private func utterancesFixture() -> Data {
        Data(#"""
        {
          "metadata": {"request_id": "r"},
          "results": {
            "channels": [{
              "detected_language": "tr",
              "alternatives": [{"transcript": "Merhaba dünya. Nasılsın? İyiyim.", "words": []}]
            }],
            "utterances": [
              {"start": 0.1, "end": 1.0, "transcript": "Merhaba dünya.", "speaker": 0},
              {"start": 1.1, "end": 2.0, "transcript": "Nasılsın?", "speaker": 0},
              {"start": 2.2, "end": 2.9, "transcript": "İyiyim.", "speaker": 1}
            ]
          }
        }
        """#.utf8)
    }

    private func queryItems(_ request: URLRequest) throws -> [String: String] {
        let url = try XCTUnwrap(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private func response(
        statusCode: Int,
        data: Data,
        headers: [String: String] = [:]
    ) throws -> TranscriptionHTTPResponse {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        ))
        return TranscriptionHTTPResponse(data: data, response: response)
    }
}

private actor DeepgramStubKeys: APIKeyRepository {
    private var key: String?
    init(apiKey: String?) { key = apiKey }
    func apiKey() -> String? { key }
    func saveAPIKey(_ apiKey: String) { key = apiKey }
    func deleteAPIKey() { key = nil }
}

private actor DeepgramRecordingService: TranscriptionServicing {
    private var count = 0
    nonisolated var capabilities: TranscriptionServiceCapabilities {
        TranscriptionServiceCapabilities(
            supportedFileExtensions: ["m4a"],
            maximumFileSizeBytes: 0,
            supportsDiarization: true,
            supportsAutomaticLanguageDetection: true
        )
    }
    func transcribe(
        _ request: TranscriptionRequest,
        uploadProgress: @escaping TranscriptionUploadProgress
    ) async throws -> TranscriptionResult {
        count += 1
        return TranscriptionResult(transcript: Transcript(
            text: "x",
            languageCode: nil,
            segments: [TranscriptSegment(speakerID: "speaker_0", startTime: 0, endTime: 1, text: "x")]
        ))
    }
    func calls() -> Int { count }
}

private actor DeepgramMockHTTPClient: TranscriptionHTTPClient {
    private let configuredDataResponse: TranscriptionHTTPResponse?
    private let configuredUploadResponse: TranscriptionHTTPResponse?
    private var dataRequest: URLRequest?
    private var uploadRequest: URLRequest?
    private var uploadFileURL: URL?

    init(dataResponse: TranscriptionHTTPResponse? = nil, uploadResponse: TranscriptionHTTPResponse? = nil) {
        configuredDataResponse = dataResponse
        configuredUploadResponse = uploadResponse
    }

    func data(for request: URLRequest) throws -> TranscriptionHTTPResponse {
        dataRequest = request
        guard let configuredDataResponse else { throw URLError(.badServerResponse) }
        return configuredDataResponse
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping TranscriptionUploadProgress
    ) throws -> TranscriptionHTTPResponse {
        uploadRequest = request
        uploadFileURL = fileURL
        progress(0.5)
        guard let configuredUploadResponse else { throw URLError(.badServerResponse) }
        return configuredUploadResponse
    }

    func lastDataRequest() -> URLRequest? { dataRequest }
    func lastUploadRequest() -> URLRequest? { uploadRequest }
    func lastUploadFileURL() -> URL? { uploadFileURL }
}
