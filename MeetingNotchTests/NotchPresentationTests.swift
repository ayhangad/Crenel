import AppKit
import SwiftUI
import XCTest
@testable import MeetingNotch

final class NotchPresentationTests: XCTestCase {
    func testRecordingOutranksMeetingAndTasks() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))

        let status = NotchStatusResolver.compactStatus(
            flow: .recording(startedAt: startedAt),
            nextMeeting: meeting,
            activeTaskCount: 4
        )

        XCTAssertEqual(
            status,
            .recording(
                .init(
                    startedAt: startedAt,
                    clientID: nil,
                    microphoneState: .unknown
                )
            )
        )
    }

    func testRecordingCompactStatusCarriesSessionClientAndMicrophoneGate() {
        let startedAt = Date(timeIntervalSince1970: 100)
        var gate = MeetingMicrophoneGate(recordingStartedAt: startedAt)
        gate.setManualState(.open, at: startedAt.addingTimeInterval(1))
        let detection = MeetingSessionDetectionSnapshot(
            session: MeetingSession(clientID: .zoom, processID: 123),
            audioProcess: nil,
            client: nil
        )

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .recording(startedAt: startedAt),
                nextMeeting: nil,
                activeTaskCount: 0,
                meetingDetection: detection,
                microphoneGate: gate
            ),
            .recording(
                .init(
                    startedAt: startedAt,
                    clientID: .zoom,
                    microphoneState: .open
                )
            )
        )
    }

    func testEveryProcessingPhaseOutranksMeetingAndTasks() {
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))
        let cases: [(MeetingFlowState, NotchCompactStatus)] = [
            (.preparingRecording, .processing(.preparing)),
            (.finalizingAudio, .processing(.finalizing)),
            (.uploading(progress: 0.42), .processing(.uploading(progress: 0.42))),
            (.transcribing, .processing(.transcribing)),
            (.summarizing, .processing(.summarizing))
        ]

        for (flow, expected) in cases {
            XCTAssertEqual(
                NotchStatusResolver.compactStatus(
                    flow: flow,
                    nextMeeting: meeting,
                    activeTaskCount: 4
                ),
                expected
            )
        }
    }

    func testFailureAndCompletionOutrankMeetingAndTasks() {
        let meeting = makeMeeting(startDate: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .failed(.network("Bağlantı yok")),
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .failed
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .completed(meetingID: UUID()),
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .completed
        )
    }

    func testMeetingOutranksTasksAndTasksOutrankIdle() {
        let startDate = Date(timeIntervalSince1970: 200)
        let meeting = makeMeeting(startDate: startDate)

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: meeting,
                activeTaskCount: 4
            ),
            .upcoming(startDate: startDate)
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: nil,
                activeTaskCount: 4
            ),
            .tasks(count: 4)
        )
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(
                flow: .idle,
                nextMeeting: nil,
                activeTaskCount: 0
            ),
            .idle
        )
    }

    func testPanelUsesPreferredSizeOnLargeScreenAndStaysWithinSmallScreen() {
        XCTAssertEqual(
            NotchPanelLayout(availableSize: CGSize(width: 1_440, height: 900)),
            NotchPanelLayout(width: 424, maximumContentHeight: 600)
        )
        XCTAssertEqual(
            NotchPanelLayout(
                availableSize: CGSize(width: 1_440, height: 900),
                preferredWidth: 520
            ),
            NotchPanelLayout(width: 520, maximumContentHeight: 600)
        )

        let constrained = NotchPanelLayout(availableSize: CGSize(width: 360, height: 500))
        XCTAssertEqual(constrained.width, 328)
        XCTAssertEqual(constrained.maximumContentHeight, 350)
        XCTAssertLessThanOrEqual(constrained.width + 32, 360)
        XCTAssertLessThanOrEqual(constrained.maximumContentHeight + 150, 500)
    }

    func testOnlyCompletionResetsAfterTransientPresentation() {
        let completed = MeetingFlowState.completed(meetingID: UUID())
        let failed = MeetingFlowState.failed(.network("Bağlantı yok"))

        XCTAssertTrue(NotchTransientStatusPolicy.shouldPresent(completed))
        XCTAssertTrue(NotchTransientStatusPolicy.shouldResetAfterTimeout(completed))
        XCTAssertTrue(NotchTransientStatusPolicy.shouldPresent(failed))
        XCTAssertFalse(NotchTransientStatusPolicy.shouldResetAfterTimeout(failed))
        XCTAssertFalse(NotchTransientStatusPolicy.shouldPresent(.transcribing))
    }

    func testReducedMotionProfileRemovesPerceptibleTransitionDurations() {
        let standard = NotchMotionProfile.resolved(reducesMotion: false)
        let reduced = NotchMotionProfile.resolved(reducesMotion: true)

        XCTAssertEqual(standard.openingDuration, 0.28)
        XCTAssertEqual(standard.closingDuration, 0.2)
        XCTAssertEqual(standard.conversionDuration, 0.3)
        XCTAssertTrue(reduced.reducesMotion)
        XCTAssertLessThanOrEqual(reduced.openingDuration, 0.01)
        XCTAssertLessThanOrEqual(reduced.closingDuration, 0.01)
        XCTAssertLessThanOrEqual(reduced.conversionDuration, 0.01)
    }

    func testPreviewAuditMatrixCoversAppearanceMotionKeyboardAndVoiceOver() {
        let matrix = NotchPreviewProfile.requiredMatrix

        XCTAssertEqual(Set(matrix.map(\.colorScheme)), Set(NotchPreviewColorScheme.allCases))
        XCTAssertTrue(matrix.contains(where: \.increasedContrast))
        XCTAssertTrue(matrix.contains(where: \.reducesMotion))
        XCTAssertEqual(Set(matrix.map(\.auditFocus)), Set(NotchPreviewAuditFocus.allCases))
        XCTAssertEqual(Set(matrix.map(\.name)).count, matrix.count)
    }

    func testPhysicalNotchForcesDarkAppearanceWhileFloatingPanelInheritsSystem() {
        XCTAssertEqual(
            MeetingNotchPanelAppearance.colorScheme(
                inherited: .light,
                hasPhysicalNotch: true
            ),
            .dark
        )
        XCTAssertEqual(
            MeetingNotchPanelAppearance.colorScheme(
                inherited: .dark,
                hasPhysicalNotch: false
            ),
            .dark
        )
        XCTAssertEqual(
            MeetingNotchPanelAppearance.colorScheme(
                inherited: .light,
                hasPhysicalNotch: false
            ),
            .light
        )
    }

    func testInactiveTabsKeepReadableVisualWeight() {
        XCTAssertGreaterThanOrEqual(MeetingNotchTheme.inactiveTabForegroundOpacity, 0.65)
        XCTAssertGreaterThan(
            MeetingNotchTheme.inactiveTabHoverForegroundOpacity,
            MeetingNotchTheme.inactiveTabForegroundOpacity
        )
        XCTAssertGreaterThanOrEqual(MeetingNotchTheme.activeTabFillOpacity, 0.10)
        XCTAssertEqual(
            MeetingNotchTheme.surfaceRadius,
            MeetingNotchTheme.controlRadius + MeetingNotchTheme.tabBarPadding
        )
    }

    @MainActor
    func testPhysicalNotchPanelRendersWhenSystemAppearanceIsLight() throws {
        let state = AppState()
        state.updateNotchPanelPresentation(
            availableSize: CGSize(width: 1_440, height: 900),
            hasPhysicalNotch: true
        )

        let rootView = ZStack(alignment: .top) {
            Color.black
            NotchPanelView()
                .environmentObject(state)
        }
        .frame(width: MeetingNotchTheme.panelWidth, height: 560, alignment: .top)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: MeetingNotchTheme.panelWidth, height: 560)
        )
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return XCTFail("Notch panel bitmap'i üretilemedi")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

        if FileManager.default.fileExists(atPath: "/tmp/MeetingNotchExportUIAudit") {
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                return XCTFail("Notch panel PNG verisi üretilemedi")
            }
            let projectRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let outputURL = projectRoot
                .appendingPathComponent("artifacts/ui-audit/after.png")
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: outputURL, options: .atomic)
        }
    }

    func testKeyboardAndVoiceOverContractsAreCompleteAndUnambiguous() {
        let tabLabels = AppState.PanelTab.allCases.map(NotchAccessibilityContract.tabLabel)
        let shortcuts = AppState.PanelTab.allCases.map(
            NotchAccessibilityContract.tabShortcutDescription
        )

        XCTAssertEqual(Set(tabLabels).count, AppState.PanelTab.allCases.count)
        XCTAssertEqual(Set(shortcuts).count, AppState.PanelTab.allCases.count)
        XCTAssertTrue(shortcuts.allSatisfy { $0.hasPrefix("Command ") })

        XCTAssertEqual(
            NotchAccessibilityContract.recordingSessionLabel(clientID: .zoom),
            "Zoom oturumu kaydediliyor"
        )
        XCTAssertEqual(
            NotchAccessibilityContract.recordingSessionLabel(clientID: .googleMeetChrome),
            "Google Meet oturumu kaydediliyor"
        )
        XCTAssertEqual(
            NotchAccessibilityContract.microphoneGateLabel(.unknown),
            "Toplantı mikrofonu bilinmiyor, güvenli kapalı"
        )
        XCTAssertEqual(
            NotchAccessibilityContract.recordingDurationLabel("01:23"),
            "Kayıt süresi 01:23"
        )
    }

    private func makeMeeting(startDate: Date) -> Meeting {
        Meeting(
            title: "Planlama",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            externalIdentifier: "planlama"
        )
    }
}
