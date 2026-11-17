import XCTest
@testable import Crenel

final class MeetingOwnerTests: XCTestCase {
    private let owner = MeetingOwner.current(fullName: "Deniz Kaya")

    private var transcript: Transcript {
        Transcript(text: "", languageCode: "en", segments: [
            TranscriptSegment(speakerID: "local_microphone", speakerName: "You", startTime: 0, endTime: 2, text: "I'll send the deck."),
            TranscriptSegment(speakerID: "speaker_1", speakerName: "Ece", startTime: 2, endTime: 4, text: "I'll book the room."),
            TranscriptSegment(speakerID: "speaker_2", speakerName: "Speaker 2", startTime: 4, endTime: 6, text: "Someone should write notes.")
        ])
    }

    func testCurrentOwnerKnowsTheAccountNameAndSelfReferences() {
        XCTAssertTrue(owner.isOwner(name: "Deniz"))
        XCTAssertTrue(owner.isOwner(name: "deniz kaya"))
        XCTAssertTrue(owner.isOwner(name: "You"))
        XCTAssertFalse(owner.isOwner(name: "Ece"))
        XCTAssertFalse(owner.isOwner(name: "Denizhan"))
        XCTAssertEqual(owner.displayName, "Deniz Kaya")
    }

    func testKeepsOwnAndUnknownActionsAndDropsOtherPeoples() {
        let actions = [
            ActionItem(title: "Send the deck", speakerID: "local_microphone"),
            ActionItem(title: "Review pricing", assignee: "Deniz"),
            ActionItem(title: "Book the room", speakerID: "speaker_1"),
            ActionItem(title: "Order lunch", assignee: "Ece"),
            ActionItem(title: "Write notes", assignee: "Speaker 2", speakerID: "speaker_2"),
            ActionItem(title: "Share the recording")
        ]
        let kept = owner.ownActions(actions, in: transcript).map(\.title)
        XCTAssertEqual(kept, ["Send the deck", "Review pricing", "Write notes", "Share the recording"])
    }

    func testPromptDescribesTheOwnerAndMicrophoneTrack() {
        XCTAssertTrue(owner.promptDescription.contains("\"Deniz Kaya\""))
        XCTAssertTrue(owner.promptDescription.contains("\"local_microphone\""))
        XCTAssertTrue(MeetingOwner.current(fullName: "").promptDescription.contains("unknown name"))
    }

    func testAgentChunkContentCarriesTheOwnerLine() {
        let segment = transcript.segments[0]
        let content = AgentMeetingSummaryService.chunkContent(
            [segment], references: ["s1": segment.id], meetingDate: "2026-11-17", language: "en", owner: owner
        )
        XCTAssertTrue(content.contains("owner: the person who recorded this meeting"))
        XCTAssertTrue(AgentMeetingSummaryService.chunkInstructions.contains("Return ONLY actions owned by the owner"))
    }

    func testRouterKeepsOnlyTheOwnersActions() async throws {
        struct Fixed: MeetingSummaryGenerating {
            func generate(from transcript: Transcript) async throws -> MeetingSummary {
                MeetingSummary(overview: "", decisions: [], actionItems: [
                    ActionItem(title: "Mine", speakerID: "local_microphone"),
                    ActionItem(title: "Theirs", assignee: "Ece")
                ])
            }
        }
        let router = MeetingSummaryRouter(
            preferences: { .default },
            agentPreferences: { AgentPreferences() },
            openAI: Fixed(),
            owner: owner
        )
        let summary = try await router.generate(from: transcript)
        XCTAssertEqual(summary.actionItems.map(\.title), ["Mine"])
    }
}
