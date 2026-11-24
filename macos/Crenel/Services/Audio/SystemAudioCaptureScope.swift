import Foundation

enum SystemAudioCaptureScope: Equatable, Sendable {
    case meetingProcesses([UInt32])
    case explicitManualGlobal

    var includedProcessObjectIDs: [UInt32]? {
        switch self {
        case .meetingProcesses(let objectIDs):
            Array(Set(objectIDs.filter { $0 != 0 })).sorted()
        case .explicitManualGlobal:
            nil
        }
    }
}

/// Picks what a recording captures besides the microphone. Recording is never blocked.
///
/// A Zoom call whose process can be verified is tapped on its own; everything else
/// (Google Meet in a browser, Slack, Teams, FaceTime, any other audio) records the whole
/// system mix. The one privacy rule is the microphone gate: while the call's microphone is
/// muted, the user's own microphone stays out of the recording.
struct MeetingAudioCaptureScopeResolver: Sendable {
    func resolve(
        detection: MeetingSessionDetectionSnapshot?,
        meeting: Meeting?
    ) -> SystemAudioCaptureScope {
        guard let detection, detection.session.state != .ended,
              detection.session.clientID == .zoom,
              Self.zoomMayBeInCall(detection),
              let process = detection.audioProcess,
              process.processID == detection.session.processID,
              process.audioObjectID != 0 else {
            return .explicitManualGlobal
        }
        return .meetingProcesses([process.audioObjectID])
    }

    /// Zoom open in the background (say, because the calendar has a Zoom link) is not a
    /// call: no call window and no audio in or out.
    private static func zoomMayBeInCall(_ detection: MeetingSessionDetectionSnapshot) -> Bool {
        if let client = detection.client, client.availability == .available,
           client.meetingWindowPresent || client.callControlsPresent {
            return true
        }
        guard let process = detection.audioProcess else { return true }
        return process.hasActiveIO
    }
}
