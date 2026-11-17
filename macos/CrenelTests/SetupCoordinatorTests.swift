import XCTest
@testable import Crenel

extension SetupCoordinator {
    /// A coordinator over fake system state, for previews and render tests.
    static func preview(_ grants: [SetupCapability: SetupGrant] = [.calendar: .granted, .microphone: .granted, .reminders: .blocked]) -> SetupCoordinator {
        SetupCoordinator(system: SetupSystem(
            grant: { grants[$0] ?? .notAsked },
            request: { _ in },
            open: { _ in }
        ))
    }
}

@MainActor
private final class FakeSystem {
    var grants: [SetupCapability: SetupGrant] = [:]
    var requested: [SetupCapability] = []
    var opened: [URL] = []
    /// What a prompt answers.
    var answers: [SetupCapability: SetupGrant] = [:]

    var system: SetupSystem {
        SetupSystem(
            grant: { [unowned self] in self.grants[$0] ?? .notAsked },
            request: { [unowned self] capability in
                self.requested.append(capability)
                self.grants[capability] = self.answers[capability] ?? .granted
            },
            open: { [unowned self] in self.opened.append($0) }
        )
    }
}

@MainActor
final class SetupCoordinatorTests: XCTestCase {
    func testRequestAllPromptsEverySystemPromptInOrderThenOpensFirstManualPane() async {
        let fake = FakeSystem()
        fake.grants = [.microphone: .granted]
        let setup = SetupCoordinator(system: fake.system)

        await setup.requestAll()

        XCTAssertEqual(fake.requested, [.calendar, .reminders, .notifications, .systemAudio, .accessibility])
        XCTAssertEqual(setup.grant(for: .calendar), .granted)
        XCTAssertFalse(setup.isRunningAll)
    }

    func testRefusedPermissionOpensItsSettingsPaneInsteadOfPrompting() async {
        let fake = FakeSystem()
        fake.grants = [.calendar: .blocked]
        let setup = SetupCoordinator(system: fake.system)

        await setup.request(.calendar)

        XCTAssertTrue(fake.requested.isEmpty)
        XCTAssertEqual(fake.opened.first?.absoluteString.contains("Privacy_Calendars"), true)
    }

    func testGrantedCapabilityConnectsItsFeatureOnce() async {
        let fake = FakeSystem()
        let setup = SetupCoordinator(system: fake.system)
        var connected: [SetupCapability] = []
        setup.onGranted = { connected.append($0) }

        await setup.request(.reminders)
        setup.refresh()

        XCTAssertEqual(connected, [.reminders])
    }

    func testGrantMadeInSystemSettingsIsPickedUpOnRefresh() {
        let fake = FakeSystem()
        let setup = SetupCoordinator(system: fake.system)
        var connected: [SetupCapability] = []
        setup.onGranted = { connected.append($0) }

        fake.grants[.calendar] = .granted
        setup.refresh()

        XCTAssertEqual(connected, [.calendar])
        XCTAssertFalse(setup.allGranted)
    }

    func testDeclinedPromptStaysVisibleAsBlocked() async {
        let fake = FakeSystem()
        fake.answers[.calendar] = .blocked
        let setup = SetupCoordinator(system: fake.system)

        await setup.request(.calendar)

        XCTAssertEqual(setup.grant(for: .calendar), .blocked)
    }

    func testEveryCapabilityHasASettingsDestination() {
        for capability in SetupCapability.allCases {
            XCTAssertNotNil(capability.settingsURL, capability.rawValue)
        }
    }
}
