@preconcurrency import AVFoundation
import Foundation

protocol AudioTrackMixing: Sendable {
    func mix(tracks: [CapturedAudioTrack], outputURL: URL) async throws -> URL
}

enum AudioMixError: LocalizedError, Equatable {
    case missingSource(AudioSourceKind)
    case unreadableSource(AudioSourceKind)
    case renderFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingSource(let source):
            "\(source.displayName) kaydı bulunamadı."
        case .unreadableSource(let source):
            "\(source.displayName) kaydı okunamadı."
        case .renderFailed:
            "Ses kaynakları birleştirilemedi."
        case .invalidOutput:
            "Oluşturulan M4A dosyası geçerli ses içermiyor."
        }
    }
}

actor AudioTrackMixer: AudioTrackMixing {
    private let outputSampleRate = 48_000.0
    private let maximumFrameCount: AVAudioFrameCount = 4_096

    func mix(tracks: [CapturedAudioTrack], outputURL: URL) async throws -> URL {
        let sources = try loadSources(from: tracks)
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try render(sources: sources, outputURL: outputURL)
            try await validateOutput(at: outputURL)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func loadSources(from captures: [CapturedAudioTrack]) throws -> [SourceAudio] {
        var result: [SourceAudio] = []
        let earliestSampleTime = captures.compactMap(\.firstSampleTime).min() ?? 0

        for source in AudioSourceKind.allCases {
            guard let capture = captures.first(where: { $0.source == source }) else {
                throw AudioMixError.missingSource(source)
            }

            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: capture.fileURL)
            } catch {
                throw AudioMixError.unreadableSource(source)
            }
            guard file.length > 0, file.processingFormat.sampleRate > 0 else {
                throw AudioMixError.unreadableSource(source)
            }

            result.append(SourceAudio(
                capture: capture,
                file: file,
                offset: max(0, (capture.firstSampleTime ?? earliestSampleTime) - earliestSampleTime)
            ))
        }
        return result
    }

    private func render(sources: [SourceAudio], outputURL: URL) throws {
        let engine = AVAudioEngine()
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 2,
            interleaved: false
        )!
        var players: [AVAudioPlayerNode] = []
        var totalDuration: TimeInterval = 0

        for source in sources {
            let player = AVAudioPlayerNode()
            player.volume = volume(for: source.capture.source)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: source.file.processingFormat)
            let startTime = AVAudioTime(
                sampleTime: AVAudioFramePosition(source.offset * outputSampleRate),
                atRate: outputSampleRate
            )
            player.scheduleFile(source.file, at: startTime)
            players.append(player)

            let sourceDuration = Double(source.file.length) / source.file.processingFormat.sampleRate
            totalDuration = max(totalDuration, source.offset + sourceDuration)
        }

        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: outputFormat,
                maximumFrameCount: maximumFrameCount
            )
            engine.prepare()
            try engine.start()
            players.forEach { $0.play() }

            let totalFrames = AVAudioFramePosition(ceil(totalDuration * outputSampleRate))
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: outputSampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000
            ]
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
            let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: engine.manualRenderingMaximumFrameCount
            )!
            var stalledRenderCount = 0

            while engine.manualRenderingSampleTime < totalFrames {
                try Task.checkCancellation()
                let remaining = totalFrames - engine.manualRenderingSampleTime
                let frames = min(AVAudioFrameCount(remaining), buffer.frameCapacity)

                switch try engine.renderOffline(frames, to: buffer) {
                case .success:
                    try outputFile.write(from: buffer)
                    stalledRenderCount = 0
                case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                    stalledRenderCount += 1
                    if stalledRenderCount > 100 {
                        throw AudioMixError.renderFailed
                    }
                case .error:
                    throw AudioMixError.renderFailed
                @unknown default:
                    throw AudioMixError.renderFailed
                }
            }

            players.forEach { $0.stop() }
            engine.stop()
            engine.disableManualRenderingMode()
        } catch let error as AudioMixError {
            throw error
        } catch {
            throw AudioMixError.renderFailed
        }
    }

    private func validateOutput(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        guard !tracks.isEmpty, duration.isNumeric, duration.seconds > 0 else {
            throw AudioMixError.invalidOutput
        }
    }

    private func volume(for source: AudioSourceKind) -> Float {
        switch source {
        case .microphone: 0.85
        case .systemAudio: 0.65
        }
    }
}

private struct SourceAudio {
    let capture: CapturedAudioTrack
    let file: AVAudioFile
    let offset: TimeInterval
}
