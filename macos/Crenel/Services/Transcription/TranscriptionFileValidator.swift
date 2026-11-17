import Foundation

struct TranscriptionFileValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(
        request: TranscriptionRequest,
        capabilities: TranscriptionServiceCapabilities
    ) throws {
        if request.requestsDiarization, !capabilities.supportsDiarization {
            throw TranscriptionServiceError.unsupportedFeature(.diarization)
        }
        if request.languageCode == nil, !capabilities.supportsAutomaticLanguageDetection {
            throw TranscriptionServiceError.unsupportedFeature(.automaticLanguageDetection)
        }

        let url = request.audioFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            throw TranscriptionServiceError.invalidFile(.missing)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw TranscriptionServiceError.invalidFile(.unreadable)
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw TranscriptionServiceError.invalidFile(.unreadable)
        }
        guard values.isRegularFile == true else {
            throw TranscriptionServiceError.invalidFile(.notRegularFile)
        }

        let fileSize = Int64(values.fileSize ?? 0)
        guard fileSize > 0 else {
            throw TranscriptionServiceError.invalidFile(.empty)
        }
        guard capabilities.maximumFileSizeBytes <= 0
                || fileSize <= capabilities.maximumFileSizeBytes else {
            throw TranscriptionServiceError.invalidFile(.tooLarge)
        }

        let fileExtension = url.pathExtension.lowercased()
        guard capabilities.supportedFileExtensions.contains(fileExtension) else {
            throw TranscriptionServiceError.invalidFile(.unsupportedFormat)
        }
    }
}
