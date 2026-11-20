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
/// A Zoom or Google Meet call that is actually live is captured on its own: Zoom's process,
/// or the Meet tab through the Chrome bridge, and never all system audio instead. Anything
/// else the user explicitly records (a Slack huddle, Teams, FaceTime, a Chrome tab that is
/// not Meet) uses the whole system mix. A stale detection, a Chrome window that shows no
/// Meet call, or a calendar link alone must not block that: those blocked recording a
/// Slack huddle while a Zoom event sat in the calendar or Chrome played other audio.
struct MeetingAudioCaptureScopeResolver: Sendable {
    var browserAudioAvailable: @Sendable () -> Bool = { false }

    func resolve(
        detection: MeetingSessionDetectionSnapshot?,
        meeting: Meeting?
    ) throws -> SystemAudioCaptureScope {
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
                throw RecordingCaptureError.meetingProcessUnavailable
            }
            return .meetingProcesses([process.audioObjectID])
        case .googleMeetChrome:
            guard Self.chromeMayHostMeetCall(detection.client, scheduledClient: scheduledClient) else {
                return .explicitManualGlobal
            }
            guard browserAudioAvailable() else {
                throw RecordingCaptureError.browserMeetingAudioIsolationUnavailable
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
        // Without a process snapshot nothing is known; keep failing closed.
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
