import AVFoundation
import Foundation

struct PrivacyCanaryAudioResult: Codable, Equatable, Sendable {
    let path: String
    let durationSeconds: Double
    let sampleRate: Double
    let channelCount: Int
    let maximumToneAmplitude: Double
    let toneThreshold: Double
    let minimumDurationSeconds: Double?
    let passed: Bool
}

struct PrivacyCanaryTranscriptResult: Codable, Equatable, Sendable {
    let path: String
    let forbiddenPhraseCount: Int
    let matchedPhrases: [String]
    let passed: Bool
}

struct PrivacyCanaryAuditResult: Codable, Equatable, Sendable {
    let generatedAt: Date
    let toneFrequency: Double
    let audio: [PrivacyCanaryAudioResult]
    let transcripts: [PrivacyCanaryTranscriptResult]

    var passed: Bool {
        audio.allSatisfy(\.passed) && transcripts.allSatisfy(\.passed)
    }
}

enum PrivacyCanaryFileAuditError: LocalizedError, Equatable {
    case invalidFrequency(Double)
    case invalidThreshold(Double)
    case invalidMinimumDuration(Double)
    case unreadableAudio(String)
    case unsupportedAudioFormat(String)
    case emptyAudio(String)
    case unreadableTranscript(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFrequency(value):
            "Invalid canary frequency: \(value)"
        case let .invalidThreshold(value):
            "Invalid tone amplitude threshold: \(value)"
        case let .invalidMinimumDuration(value):
            "Invalid minimum duration: \(value)"
        case let .unreadableAudio(path):
            "Couldn’t read audio file: \(path)"
        case let .unsupportedAudioFormat(path):
            "Couldn’t open audio file as Float32 PCM: \(path)"
        case let .emptyAudio(path):
            "Audio file has no frames: \(path)"
        case let .unreadableTranscript(path):
            "Couldn’t read transcript file: \(path)"
        }
    }
}

struct PrivacyCanaryFileAuditor {
    private let analysisFrameCapacity: AVAudioFrameCount

    init(analysisFrameCapacity: AVAudioFrameCount = 32_768) {
        self.analysisFrameCapacity = max(2_048, analysisFrameCapacity)
    }

    func audit(
        audioURLs: [URL],
        transcriptURLs: [URL],
        forbiddenPhrases: [String],
        toneFrequency: Double = 997,
        maximumToneAmplitude: Double = 0.02,
        minimumDurationSeconds: Double? = nil
    ) throws -> PrivacyCanaryAuditResult {
        guard toneFrequency.isFinite, toneFrequency > 0 else {
            throw PrivacyCanaryFileAuditError.invalidFrequency(toneFrequency)
        }
        guard maximumToneAmplitude.isFinite,
              maximumToneAmplitude >= 0,
              maximumToneAmplitude <= 1 else {
            throw PrivacyCanaryFileAuditError.invalidThreshold(maximumToneAmplitude)
        }
        if let minimumDurationSeconds,
           (!minimumDurationSeconds.isFinite || minimumDurationSeconds < 0) {
            throw PrivacyCanaryFileAuditError.invalidMinimumDuration(minimumDurationSeconds)
        }

        let audio = try audioURLs.map {
            try auditAudio(
                at: $0,
                toneFrequency: toneFrequency,
                maximumToneAmplitude: maximumToneAmplitude,
                minimumDurationSeconds: minimumDurationSeconds
            )
        }
        let transcripts = try transcriptURLs.map {
            try auditTranscript(at: $0, forbiddenPhrases: forbiddenPhrases)
        }
        return PrivacyCanaryAuditResult(
            generatedAt: Date(),
            toneFrequency: toneFrequency,
            audio: audio,
            transcripts: transcripts
        )
    }

    func auditAudio(
        at url: URL,
        toneFrequency: Double,
        maximumToneAmplitude: Double,
        minimumDurationSeconds: Double? = nil
    ) throws -> PrivacyCanaryAudioResult {
        guard toneFrequency.isFinite, toneFrequency > 0 else {
            throw PrivacyCanaryFileAuditError.invalidFrequency(toneFrequency)
        }
        guard maximumToneAmplitude.isFinite,
              maximumToneAmplitude >= 0,
              maximumToneAmplitude <= 1 else {
            throw PrivacyCanaryFileAuditError.invalidThreshold(maximumToneAmplitude)
        }
        if let minimumDurationSeconds,
           (!minimumDurationSeconds.isFinite || minimumDurationSeconds < 0) {
            throw PrivacyCanaryFileAuditError.invalidMinimumDuration(minimumDurationSeconds)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw PrivacyCanaryFileAuditError.unreadableAudio(url.path)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw PrivacyCanaryFileAuditError.unreadableAudio(url.path)
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        guard sampleRate.isFinite,
              sampleRate > 0,
              channelCount > 0,
              format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else {
            throw PrivacyCanaryFileAuditError.unsupportedAudioFormat(url.path)
        }
        guard toneFrequency < sampleRate / 2 else {
            throw PrivacyCanaryFileAuditError.invalidFrequency(toneFrequency)
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: analysisFrameCapacity
        ) else {
            throw PrivacyCanaryFileAuditError.unsupportedAudioFormat(url.path)
        }

        var maximumAmplitude = 0.0
        var totalFrames: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            let remainingFrames = file.length - file.framePosition
            let requestedFrames = AVAudioFrameCount(
                min(AVAudioFramePosition(analysisFrameCapacity), remainingFrames)
            )
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: requestedFrames)
            } catch {
                throw PrivacyCanaryFileAuditError.unreadableAudio(url.path)
            }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else {
                throw PrivacyCanaryFileAuditError.emptyAudio(url.path)
            }
            totalFrames += AVAudioFramePosition(frameCount)

            guard let channels = buffer.floatChannelData else {
                throw PrivacyCanaryFileAuditError.unsupportedAudioFormat(url.path)
            }
            for channel in 0..<channelCount {
                maximumAmplitude = max(
                    maximumAmplitude,
                    goertzelAmplitude(
                        samples: channels[channel],
                        count: frameCount,
                        frequency: toneFrequency,
                        sampleRate: sampleRate
                    )
                )
            }
        }

        guard totalFrames > 0 else {
            throw PrivacyCanaryFileAuditError.emptyAudio(url.path)
        }
        let duration = Double(totalFrames) / sampleRate
        let durationPassed = minimumDurationSeconds.map { duration >= $0 } ?? true
        let passed = maximumAmplitude <= maximumToneAmplitude && durationPassed
        return PrivacyCanaryAudioResult(
            path: url.standardizedFileURL.path,
            durationSeconds: duration,
            sampleRate: sampleRate,
            channelCount: channelCount,
            maximumToneAmplitude: maximumAmplitude,
            toneThreshold: maximumToneAmplitude,
            minimumDurationSeconds: minimumDurationSeconds,
            passed: passed
        )
    }

    func auditTranscript(
        at url: URL,
        forbiddenPhrases: [String]
    ) throws -> PrivacyCanaryTranscriptResult {
        guard let data = try? Data(contentsOf: url) else {
            throw PrivacyCanaryFileAuditError.unreadableTranscript(url.path)
        }
        let searchableText = searchableTranscriptText(data: data, extension: url.pathExtension)
        let normalizedText = normalize(searchableText)
        let normalizedPhrases = forbiddenPhrases
            .map { ($0, normalize($0)) }
            .filter { !$0.1.isEmpty }
        let matches = normalizedPhrases.compactMap { original, normalized in
            normalizedText.contains(normalized) ? original : nil
        }
        return PrivacyCanaryTranscriptResult(
            path: url.standardizedFileURL.path,
            forbiddenPhraseCount: normalizedPhrases.count,
            matchedPhrases: matches,
            passed: matches.isEmpty
        )
    }

    private func goertzelAmplitude(
        samples: UnsafePointer<Float>,
        count: Int,
        frequency: Double,
        sampleRate: Double
    ) -> Double {
        guard count > 0 else { return 0 }
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var previous = 0.0
        var previousPrevious = 0.0
        for index in 0..<count {
            let current = Double(samples[index]) + coefficient * previous - previousPrevious
            previousPrevious = previous
            previous = current
        }
        let power = max(
            0,
            previousPrevious * previousPrevious
                + previous * previous
                - coefficient * previous * previousPrevious
        )
        return 2 * sqrt(power) / Double(count)
    }

    private func searchableTranscriptText(data: Data, extension fileExtension: String) -> String {
        if fileExtension.lowercased() == "json",
           let object = try? JSONSerialization.jsonObject(with: data) {
            return strings(in: object).joined(separator: "\n")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func strings(in object: Any) -> [String] {
        if let string = object as? String {
            return [string]
        }
        if let array = object as? [Any] {
            return array.flatMap(strings(in:))
        }
        if let dictionary = object as? [String: Any] {
            return dictionary.values.flatMap(strings(in:))
        }
        return []
    }

    private func normalize(_ text: String) -> String {
        text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
