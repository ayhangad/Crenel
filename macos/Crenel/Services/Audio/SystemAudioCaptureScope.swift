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

struct MeetingAudioCaptureScopeResolver: Sendable {
    var browserAudioAvailable: @Sendable () -> Bool = { false }

    func resolve(
        detection: MeetingSessionDetectionSnapshot?,
        meeting: Meeting?
    ) throws -> SystemAudioCaptureScope {
        if let detection {
            switch detection.session.clientID {
            case .zoom:
                guard let process = detection.audioProcess,
                      process.processID == detection.session.processID,
                      process.audioObjectID != 0 else {
                    throw RecordingCaptureError.meetingProcessUnavailable
                }
                return .meetingProcesses([process.audioObjectID])
            case .googleMeetChrome:
                guard browserAudioAvailable() else {
                    throw RecordingCaptureError.browserMeetingAudioIsolationUnavailable
                }
                return .browserTab
            case .unsupported, nil:
                break
            }
        }

        switch inferredClient(from: meeting?.meetingURL) {
        case .zoom:
            throw RecordingCaptureError.meetingProcessUnavailable
        case .googleMeetChrome:
            guard browserAudioAvailable() else {
                throw RecordingCaptureError.browserMeetingAudioIsolationUnavailable
            }
            return .browserTab
        case .unsupported, nil:
            return .explicitManualGlobal
        }
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
