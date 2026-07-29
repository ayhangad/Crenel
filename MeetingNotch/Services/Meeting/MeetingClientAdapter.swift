import ApplicationServices
import Foundation

enum MeetingClientAdapterAvailability: Equatable, Sendable {
    case available
    case accessibilityPermissionRequired
    case clientUnavailable
}

struct MeetingClientSnapshot: Equatable, Sendable {
    let clientID: MeetingClientID
    let processID: Int32
    let availability: MeetingClientAdapterAvailability
    let meetingWindowPresent: Bool
    let callControlsPresent: Bool
    let microphoneState: MeetingMicrophoneState

    var evidence: MeetingEvidence {
        .clientUI(
            clientID: clientID,
            meetingWindowPresent: meetingWindowPresent,
            callControlsPresent: callControlsPresent
        )
    }
}

protocol MeetingClientAdapting: Sendable {
    func inspect(
        processID: Int32,
        bundleIdentifier: String?,
        promptForAccessibility: Bool
    ) -> MeetingClientSnapshot?
}

protocol AccessibilityAuthorizing: Sendable {
    func isTrusted(prompt: Bool) -> Bool
}

struct SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    func isTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct AccessibilityElementSnapshot: Equatable, Sendable {
    private static let interactiveRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXMenuButtonRole as String
    ]

    let role: String?
    let subrole: String?
    let identifier: String?
    let title: String?
    let description: String?
    let help: String?
    let value: String?
    let url: String?

    var isWindow: Bool {
        role == kAXWindowRole as String
    }

    var isInteractiveControl: Bool {
        role.map(Self.interactiveRoles.contains) ?? false
    }

    fileprivate var normalizedSearchText: String {
        [
            identifier,
            title,
            description,
            help,
            value,
            url
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(
            of: #"[^a-z0-9:/._-]+"#,
            with: " ",
            options: .regularExpression
        )
    }
}

protocol AccessibilityTreeReading: Sendable {
    func readElements(processID: Int32) throws -> [AccessibilityElementSnapshot]
}

enum AccessibilityTreeReaderError: Error, Equatable {
    case applicationUnavailable
    case treeUnavailable
}

struct SystemAccessibilityTreeReader: AccessibilityTreeReading {
    private let maximumNodeCount: Int
    private let maximumDepth: Int

    init(maximumNodeCount: Int = 1_200, maximumDepth: Int = 16) {
        self.maximumNodeCount = maximumNodeCount
        self.maximumDepth = maximumDepth
    }

    func readElements(processID: Int32) throws -> [AccessibilityElementSnapshot] {
        guard processID > 0 else {
            throw AccessibilityTreeReaderError.applicationUnavailable
        }

        let application = AXUIElementCreateApplication(pid_t(processID))
        let roots = elements(for: application, attribute: kAXWindowsAttribute as String)
        guard !roots.isEmpty else {
            throw AccessibilityTreeReaderError.treeUnavailable
        }

        var result: [AccessibilityElementSnapshot] = []
        var stack = roots.reversed().map { ($0, 0) }
        var visited: Set<CFHashCode> = []

        while let (element, depth) = stack.popLast(),
              result.count < maximumNodeCount {
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { continue }

            result.append(snapshot(for: element))
            guard depth < maximumDepth else { continue }

            let children = elements(
                for: element,
                attribute: kAXChildrenAttribute as String
            )
            stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }

        return result
    }

    private func snapshot(for element: AXUIElement) -> AccessibilityElementSnapshot {
        AccessibilityElementSnapshot(
            role: stringValue(for: element, attribute: kAXRoleAttribute as String),
            subrole: stringValue(for: element, attribute: kAXSubroleAttribute as String),
            identifier: stringValue(for: element, attribute: kAXIdentifierAttribute as String),
            title: stringValue(for: element, attribute: kAXTitleAttribute as String),
            description: stringValue(
                for: element,
                attribute: kAXDescriptionAttribute as String
            ),
            help: stringValue(for: element, attribute: kAXHelpAttribute as String),
            value: stringValue(for: element, attribute: kAXValueAttribute as String),
            url: stringValue(for: element, attribute: kAXURLAttribute as String)
        )
    }

    private func stringValue(
        for element: AXUIElement,
        attribute: String
    ) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue
        ) == .success, let rawValue else {
            return nil
        }

        if CFGetTypeID(rawValue) == CFStringGetTypeID() {
            return rawValue as? String
        }
        if CFGetTypeID(rawValue) == CFURLGetTypeID(),
           let url = rawValue as? URL {
            return url.absoluteString
        }
        return nil
    }

    private func elements(
        for element: AXUIElement,
        attribute: String
    ) -> [AXUIElement] {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue
        ) == .success, let rawValue else {
            return []
        }
        return rawValue as? [AXUIElement] ?? []
    }
}

struct MeetingClientProcessMatcher: Sendable {
    private static let zoomBundleIdentifiers: Set<String> = [
        "us.zoom.xos"
    ]
    private static let chromeBundleIdentifiers: Set<String> = [
        "com.google.chrome",
        "com.google.chrome.beta",
        "com.google.chrome.canary"
    ]

    func clientID(bundleIdentifier: String?) -> MeetingClientID? {
        guard let identifier = bundleIdentifier?.lowercased() else { return nil }
        if Self.zoomBundleIdentifiers.contains(identifier) {
            return .zoom
        }
        if Self.chromeBundleIdentifiers.contains(identifier) {
            return .googleMeetChrome
        }
        return nil
    }
}

struct AccessibilityMeetingClientAdapter: MeetingClientAdapting {
    private let authorizer: any AccessibilityAuthorizing
    private let treeReader: any AccessibilityTreeReading
    private let processMatcher: MeetingClientProcessMatcher

    init(
        authorizer: any AccessibilityAuthorizing = SystemAccessibilityAuthorizer(),
        treeReader: any AccessibilityTreeReading = SystemAccessibilityTreeReader(),
        processMatcher: MeetingClientProcessMatcher = MeetingClientProcessMatcher()
    ) {
        self.authorizer = authorizer
        self.treeReader = treeReader
        self.processMatcher = processMatcher
    }

    func inspect(
        processID: Int32,
        bundleIdentifier: String?,
        promptForAccessibility: Bool = false
    ) -> MeetingClientSnapshot? {
        guard let clientID = processMatcher.clientID(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        guard authorizer.isTrusted(prompt: promptForAccessibility) else {
            return unavailableSnapshot(
                clientID: clientID,
                processID: processID,
                availability: .accessibilityPermissionRequired
            )
        }
        guard let elements = try? treeReader.readElements(processID: processID) else {
            return unavailableSnapshot(
                clientID: clientID,
                processID: processID,
                availability: .clientUnavailable
            )
        }

        let detection = MeetingClientUIDetector.detect(
            clientID: clientID,
            elements: elements
        )
        return MeetingClientSnapshot(
            clientID: clientID,
            processID: processID,
            availability: .available,
            meetingWindowPresent: detection.meetingWindowPresent,
            callControlsPresent: detection.callControlsPresent,
            microphoneState: detection.microphoneState
        )
    }

    private func unavailableSnapshot(
        clientID: MeetingClientID,
        processID: Int32,
        availability: MeetingClientAdapterAvailability
    ) -> MeetingClientSnapshot {
        MeetingClientSnapshot(
            clientID: clientID,
            processID: processID,
            availability: availability,
            meetingWindowPresent: false,
            callControlsPresent: false,
            microphoneState: .unknown
        )
    }
}

private struct MeetingClientUIDetection {
    let meetingWindowPresent: Bool
    let callControlsPresent: Bool
    let microphoneState: MeetingMicrophoneState
}

private enum MeetingClientUIDetector {
    private static let zoomWindowPhrases = [
        "zoom meeting",
        "zoom webinar",
        "meeting controls",
        "toplanti kontrolleri"
    ]
    private static let zoomEndPhrases = [
        "leave meeting",
        "end meeting",
        "leave webinar",
        "toplantidan ayril",
        "toplantiyi sonlandir"
    ]
    private static let zoomMicrophoneClosedPhrases = [
        "unmute my audio",
        "unmute audio",
        "unmute",
        "sesimi ac",
        "sesi ac"
    ]
    private static let zoomMicrophoneOpenPhrases = [
        "mute my audio",
        "mute audio",
        "mute",
        "sesimi kapat",
        "sesi kapat"
    ]
    private static let meetContextPhrases = [
        "meet.google.com",
        "google meet"
    ]
    private static let meetEndPhrases = [
        "leave call",
        "end call",
        "hang up",
        "aramadan ayril",
        "gorusmeden ayril",
        "cagridan ayril"
    ]
    private static let meetMicrophoneClosedPhrases = [
        "turn on microphone",
        "unmute microphone",
        "mikrofonu ac",
        "mikrofonunuzu acin"
    ]
    private static let meetMicrophoneOpenPhrases = [
        "turn off microphone",
        "mute microphone",
        "mikrofonu kapat",
        "mikrofonunuzu kapatin"
    ]

    static func detect(
        clientID: MeetingClientID,
        elements: [AccessibilityElementSnapshot]
    ) -> MeetingClientUIDetection {
        switch clientID {
        case .zoom:
            detectZoom(elements)
        case .googleMeetChrome:
            detectGoogleMeet(elements)
        case .unsupported:
            MeetingClientUIDetection(
                meetingWindowPresent: false,
                callControlsPresent: false,
                microphoneState: .unknown
            )
        }
    }

    private static func detectZoom(
        _ elements: [AccessibilityElementSnapshot]
    ) -> MeetingClientUIDetection {
        let controls = elements.filter(\.isInteractiveControl)
        let endControl = controls.first { containsAny($0, phrases: zoomEndPhrases) }
        let microphoneState = microphoneState(
            controls: controls,
            closedPhrases: zoomMicrophoneClosedPhrases,
            openPhrases: zoomMicrophoneOpenPhrases
        )
        let controlsPresent = endControl != nil && microphoneState != .unknown
        let windowPresent = elements.contains(where: \.isWindow)
            && (elements.contains { containsAny($0, phrases: zoomWindowPhrases) }
                || controlsPresent)

        return MeetingClientUIDetection(
            meetingWindowPresent: windowPresent,
            callControlsPresent: controlsPresent,
            microphoneState: microphoneState
        )
    }

    private static func detectGoogleMeet(
        _ elements: [AccessibilityElementSnapshot]
    ) -> MeetingClientUIDetection {
        let hasMeetContext = elements.contains {
            containsAny($0, phrases: meetContextPhrases)
        }
        guard hasMeetContext else {
            return MeetingClientUIDetection(
                meetingWindowPresent: false,
                callControlsPresent: false,
                microphoneState: .unknown
            )
        }

        let controls = elements.filter(\.isInteractiveControl)
        let endControl = controls.first { containsAny($0, phrases: meetEndPhrases) }
        let microphoneState = microphoneState(
            controls: controls,
            closedPhrases: meetMicrophoneClosedPhrases,
            openPhrases: meetMicrophoneOpenPhrases
        )
        let controlsPresent = endControl != nil && microphoneState != .unknown

        return MeetingClientUIDetection(
            meetingWindowPresent: elements.contains(where: \.isWindow),
            callControlsPresent: controlsPresent,
            microphoneState: microphoneState
        )
    }

    private static func microphoneState(
        controls: [AccessibilityElementSnapshot],
        closedPhrases: [String],
        openPhrases: [String]
    ) -> MeetingMicrophoneState {
        if controls.contains(where: { containsAny($0, phrases: closedPhrases) }) {
            return .closed
        }
        if controls.contains(where: { containsAny($0, phrases: openPhrases) }) {
            return .open
        }
        return .unknown
    }

    private static func containsAny(
        _ element: AccessibilityElementSnapshot,
        phrases: [String]
    ) -> Bool {
        let text = element.normalizedSearchText
        return phrases.contains { text.contains($0) }
    }
}
