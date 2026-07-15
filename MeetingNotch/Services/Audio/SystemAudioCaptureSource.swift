import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCaptureSource: NSObject, AudioCaptureSource {
    let kind = AudioSourceKind.systemAudio
    var onLevelChange: (@Sendable (Float) -> Void)?

    private let sampleQueue = DispatchQueue(label: "gad.MeetingNotch.audio.system")
    private var stream: SCStream?
    private var writer: SampleBufferAudioWriter?
    private var outputURL: URL?

    func prepare(outputURL: URL) async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw RecordingCaptureError.systemAudioPermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
            ?? content.displays.first
        else {
            throw RecordingCaptureError.noDisplay
        }

        let ownApplications = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        self.outputURL = outputURL
        writer = SampleBufferAudioWriter(outputURL: outputURL, source: kind)
        self.stream = stream
    }

    func start() async throws {
        guard let stream else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Sistem sesi hazırlanmamış.")
        }
        try await stream.startCapture()
    }

    func stop() async throws -> CapturedAudioTrack {
        guard let stream, let writer, let outputURL else {
            throw RecordingCaptureError.sourceFailed(.systemAudio, "Sistem sesi hazırlanmamış.")
        }

        try await stream.stopCapture()
        sampleQueue.sync {}

        guard let firstSampleTime = try await writer.finish() else {
            throw RecordingCaptureError.sourceDidNotProduceAudio(.systemAudio)
        }
        reset()
        return CapturedAudioTrack(
            source: .systemAudio,
            fileURL: outputURL,
            firstSampleTime: firstSampleTime
        )
    }

    func cancel() async {
        try? await stream?.stopCapture()
        sampleQueue.sync {}
        writer?.cancel()
        reset()
    }

    private func reset() {
        stream = nil
        writer = nil
        outputURL = nil
    }
}

extension SystemAudioCaptureSource: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        writer?.append(sampleBuffer)
        onLevelChange?(AudioLevelMeter.normalizedLevel(from: sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.audioCaptureFailed(source: kind.rawValue, error: error)
    }
}
