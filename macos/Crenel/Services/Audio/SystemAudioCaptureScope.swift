import Foundation

enum SystemAudioCaptureScope: Equatable, Sendable {
    case meetingProcesses([UInt32])
    case browserTab
    case explicitManualGlobal

    var includedProcessObjectIDs: [UInt32]? {
        switch self {
        case .meetingProcesses(let objectIDs):
            Array(Set(objectIDs.filter { $0 != 0 })).sorted()
        case .browserTab, .explicitManualGlobal:
            nil
        }
    }
}

/// Picks what a recording captures besides the microphone.
///
/// Recording is never blocked. A Zoom call whose process can be verified is captured on its
/// own, and a Google Meet call whose tab the Chrome extension is streaming is captured
/// through that bridge. Everything else (a Meet call without the extension, a Zoom process
/// that can't be matched, a Slack huddle, Teams, FaceTime, any other audio) records the
/// whole system mix. Decision 2026-11-24: the user may want to record anything at any time.
struct MeetingAudioCaptureScopeResolver: Sendable {
    var browserAudioAvailable: @Sendable () -> Bool = { false }

    func resolve(
        detection: MeetingSessionDetectionSnapshot?,
        meeting: Meeting?
    ) -> SystemAudioCaptureScope {
        let scheduledClient = inferredClient(from: meeting?.meetingURL)
        guard let detection, detection.session.state != .ended else {
            return .explicitManualGlobal
        }

        switch detection.session.clientID {
        case .zoom:
            // Zoom open in the background (say, because the calendar has a Zoom link) is
            // not a call: no call window and no audio in or out.
            guard Self.zoomMayBeInCall(detection) else { return .explicitManualGlobal }
            guard let process = detection.audioProcess,
                  process.processID == detection.session.processID,
                  process.audioObjectID != 0 else {
                return .explicitManualGlobal
            }
            return .meetingProcesses([process.audioObjectID])
        case .googleMeetChrome:
            guard Self.chromeMayHostMeetCall(detection.client, scheduledClient: scheduledClient),
                  browserAudioAvailable() else {
                return .explicitManualGlobal
            }
            return .browserTab
        case .unsupported, nil:
            return .explicitManualGlobal
        }
    }

    private static func zoomMayBeInCall(_ detection: MeetingSessionDetectionSnapshot) -> Bool {
        if let client = detection.client, client.availability == .available,
           client.meetingWindowPresent || client.callControlsPresent {
            return true
        }
        // Without a process snapshot nothing is known; try the process tap first.
        guard let process = detection.audioProcess else { return true }
        return process.hasActiveIO
    }

    /// Chrome is treated as a Meet call when its window shows one, or when the window can't
    /// be read (no Accessibility, or not inspected) and the calendar says Meet.
    private static func chromeMayHostMeetCall(
        _ client: MeetingClientSnapshot?,
        scheduledClient: MeetingClientID?
    ) -> Bool {
        guard let client, client.availability == .available else {
            return client == nil || scheduledClient == .googleMeetChrome
        }
        return client.meetingWindowPresent || client.callControlsPresent
    }

    private func inferredClient(from url: URL?) -> MeetingClientID? {
        guard let host = url?.host?.lowercased() else { return nil }
        if host == "meet.google.com" {
            return .googleMeetChrome
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return .zoom
        }
        return .unsupported
    }
}
