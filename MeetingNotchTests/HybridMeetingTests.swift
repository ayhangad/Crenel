import XCTest
@testable import MeetingNotch

final class HybridMeetingTests: XCTestCase {
    func testOpenAINormalizationRequiresRealEvidenceAndKeepsSpeakerIdentity() throws {
        let source = TranscriptSegment(speakerID: "speaker_0", speakerName: "Ayşe", startTime: 123, endTime: 130,
            text: "Teklif dosyasını ben yarın göndereceğim.")
        let output = OpenAIMeetingSummaryService.Output(title: "Teklif", overview: "Teklif hazırlanacak.", decisions: [], actions: [
            .init(title: "Teklifi gönder", speakerID: "speaker_0", assignee: "Uydurma kişi", dueDate: "2026-09-15", sourceSegmentID: source.id.uuidString)
        ])
        let result = try OpenAIMeetingSummaryService.normalize(output, segments: [source])
        XCTAssertEqual(result.actionItems.first?.assignee, "Ayşe")
        XCTAssertEqual(result.actionItems.first?.sourceTime, 123)
        XCTAssertNotNil(result.actionItems.first?.dueDate)
        XCTAssertEqual(result.actionItems.first?.id, try OpenAIMeetingSummaryService.normalize(output, segments: [source]).actionItems.first?.id)
        let invalid = OpenAIMeetingSummaryService.Output(title: "", overview: "", decisions: [], actions: [
            .init(title: "Görev", speakerID: "speaker_0", assignee: nil, dueDate: nil, sourceSegmentID: UUID().uuidString)
        ])
        XCTAssertThrowsError(try OpenAIMeetingSummaryService.normalize(invalid, segments: [source]))
    }

    func testHallucinatedNameAndMalformedDateStayUnknown() throws {
        let source = TranscriptSegment(speakerID: "speaker_0", startTime: 0, endTime: 3, text: "Raporu göndereceğim.")
        let output = OpenAIMeetingSummaryService.Output(title: "Rapor", overview: "", decisions: [], actions: [
            .init(title: "Raporu gönder", speakerID: nil, assignee: "Deniz", dueDate: "2026-02-31", sourceSegmentID: source.id.uuidString)
        ])
        let action = try XCTUnwrap(OpenAIMeetingSummaryService.normalize(output, segments: [source]).actionItems.first)
        XCTAssertNil(action.assignee)
        XCTAssertNil(action.dueDate)
    }

    func testChunkingCoversEveryCharacterAndPreservesEvidenceIDs() {
        let segments = [
            TranscriptSegment(speakerID: "speaker_0", startTime: 0, endTime: 10, text: String(repeating: "a", count: 95)),
            TranscriptSegment(speakerID: "speaker_1", startTime: 10, endTime: 20, text: String(repeating: "b", count: 45))
        ]
        let chunks = OpenAIMeetingSummaryService.chunks(segments, limit: 40)
        XCTAssertTrue(chunks.allSatisfy { $0.reduce(0) { $0 + $1.text.count } <= 40 })
        XCTAssertEqual(chunks.flatMap { $0 }.map(\.text).joined(), segments.map(\.text).joined())
        XCTAssertEqual(Set(chunks.flatMap { $0 }.map(\.id)), Set(segments.map(\.id)))
    }

    func testLegacyTranscriptAndTaskDecodeWithNoAnalysisFields() throws {
        let data = Data("""
        {"overview":"Özet","decisions":[],"actionItems":[{"id":"00000000-0000-0000-0000-000000000001","title":"Görev"}]}
        """.utf8)
        let summary = try JSONDecoder().decode(MeetingSummary.self, from: data)
        XCTAssertNil(summary.model)
        XCTAssertNil(summary.actionItems.first?.sourceSegmentID)
        let taskData = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","title":"Eski görev","createdAt":100}
        """.utf8)
        let task = try JSONDecoder().decode(TaskItem.self, from: taskData)
        XCTAssertEqual(task.title, "Eski görev")
        XCTAssertNil(task.sourceMeetingID)
    }

    func testTaskImportIsIdempotentAndDoesNotOverwriteUserEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileTaskRepository(rootURL: root)
        let action = ActionItem(title: "Rapor", assignee: "Ayşe", dueDate: Date(), speakerID: "speaker_0", sourceTime: 44)
        let meetingID = UUID()
        var task = try await repository.importAction(action, meetingID: meetingID)
        task.title = "Kullanıcı düzeltmesi"
        task.setStatus(.completed)
        try await repository.save(task)
        let again = try await repository.importAction(action, meetingID: meetingID)
        XCTAssertEqual(again.title, "Kullanıcı düzeltmesi")
        XCTAssertEqual(again.status, .completed)
        let all = try await repository.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sourceTime, 44)
    }

    func testNotificationPlanIgnoresPastEventsAndChangesIDsOnReschedule() {
        let now = Date(timeIntervalSince1970: 10_000)
        var meeting = Meeting(title: "Review", startDate: now.addingTimeInterval(1200), endDate: now.addingTimeInterval(4800), meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        let initial = MeetingNotificationPlan.make(meetings: [meeting], leadTime: 600, now: now)
        XCTAssertEqual(initial.count, 2)
        XCTAssertEqual(initial.first?.date, now.addingTimeInterval(600))
        meeting.startDate = now.addingTimeInterval(1800)
        let changed = MeetingNotificationPlan.make(meetings: [meeting], leadTime: 600, now: now)
        XCTAssertTrue(Set(initial.map(\.id)).isDisjoint(with: changed.map(\.id)))
        XCTAssertTrue(MeetingNotificationPlan.make(meetings: [meeting], leadTime: 600, now: now.addingTimeInterval(5000)).isEmpty)
    }

    func testEmptyCalendarStateDoesNotClaimNoMeetingsWithoutAccess() {
        XCTAssertEqual(CalendarEmptyPresentation.message(enabled: true, access: .denied, snapshot: nil), "Takvim erişimine izin verin")
        XCTAssertEqual(CalendarEmptyPresentation.message(enabled: false, access: .authorized, snapshot: nil), "Takvim bağlantısı kapalı")
        XCTAssertEqual(CalendarEmptyPresentation.message(enabled: true, access: .failed("network"), snapshot: nil), "Takvim yenilenemedi")
    }

    func testOpenAIResponseRequestUsesSchemaAndDoesNotStoreRemoteState() async throws {
        let http = AnalysisHTTPFixture(status: 200, data: Data("""
        {"status":"completed","output":[{"content":[{"type":"output_text","text":"{\\"title\\":\\"Check\\",\\"overview\\":\\"\\",\\"decisions\\":[],\\"actions\\":[]}"}]}]}
        """.utf8))
        let service = OpenAIMeetingSummaryService(keys: AnalysisKeyFixture(), http: http)
        try await service.validate(apiKey: "synthetic-test-key")
        let captured = await http.captured()
        let request = try XCTUnwrap(captured)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(json["model"] as? String, OpenAIMeetingSummaryService.model)
        XCTAssertNotNil(json["text"])
        XCTAssertNil(json["tools"])
    }

    func testQuotaFailureNeverExposesProviderBody() async {
        let http = AnalysisHTTPFixture(status: 429, data: Data("""
        {"error":{"code":"insufficient_quota","message":"secret transcript key"}}
        """.utf8))
        do {
            try await OpenAIMeetingSummaryService(keys: AnalysisKeyFixture(), http: http).validate(apiKey: "test")
            XCTFail("Expected quota error")
        } catch {
            XCTAssertEqual(error as? MeetingAnalysisError, .quota)
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }
}

private actor AnalysisHTTPFixture: TranscriptionHTTPClient {
    let status: Int
    let body: Data
    var last: URLRequest?
    init(status: Int, data: Data) { self.status = status; body = data }
    func data(for request: URLRequest) async throws -> TranscriptionHTTPResponse {
        last = request
        return .init(data: body, response: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func upload(for request: URLRequest, fromFile fileURL: URL, progress: @escaping TranscriptionUploadProgress) async throws -> TranscriptionHTTPResponse {
        throw MeetingAnalysisError.unavailable
    }
    func captured() -> URLRequest? { last }
}

private actor AnalysisKeyFixture: APIKeyRepository {
    func apiKey() -> String? { "fixture" }
    func saveAPIKey(_ apiKey: String) {}
    func deleteAPIKey() {}
}

private struct HeartbeatReader: AudioProcessSnapshotReading {
    func readSnapshots() throws -> [AudioProcessSnapshot] {
        [.init(audioObjectID: 10, processID: 42, bundleIdentifier: "us.zoom.xos", isRunningInput: true, isRunningOutput: true)]
    }
}
private final class HeartbeatAdapter: MeetingClientAdapting, @unchecked Sendable {
    private let lock = NSLock()
    private var state = MeetingMicrophoneState.open
    func close() { lock.withLock { state = .closed } }
    func inspect(processID: Int32, bundleIdentifier: String?, promptForAccessibility: Bool) -> MeetingClientSnapshot? {
        .init(clientID: .zoom, processID: processID, availability: .available,
              meetingWindowPresent: true, callControlsPresent: true, microphoneState: lock.withLock { state })
    }
}
private actor HeartbeatRecorder {
    var last: MeetingSessionDetectionSnapshot?
    func append(_ value: MeetingSessionDetectionSnapshot) { last = value }
}

extension HybridMeetingTests {
    func testMuteChangesReachCoordinatorWithUnchangedHALSnapshot() async {
        let monitor = CoreAudioProcessMonitor(reader: HeartbeatReader(), pollingInterval: nil)
        let adapter = HeartbeatAdapter()
        let coordinator = MeetingSessionCoordinator(audioProcessMonitor: monitor, clientAdapter: adapter)
        let recorder = HeartbeatRecorder()
        await coordinator.start { await recorder.append($0) }
        let before = await recorder.last
        XCTAssertEqual(before?.microphoneState, .open)
        adapter.close()
        await coordinator.refresh()
        let after = await recorder.last
        XCTAssertEqual(after?.microphoneState, .closed)
        await coordinator.stop()
    }
}
