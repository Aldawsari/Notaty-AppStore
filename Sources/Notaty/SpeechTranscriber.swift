import Foundation
import Speech

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case failed(String)
        case notAvailable
        case notAuthorized
        case missingUsageDescription

        var localizedDescription: String {
            switch self {
            case .failed(let message):
                return message
            case .notAvailable:
                return "Speech recognition is not available for the selected language."
            case .notAuthorized:
                return "Speech recognition permission was not granted."
            case .missingUsageDescription:
                return "Speech recognition requires Notaty to run as an app bundle with NSSpeechRecognitionUsageDescription in Info.plist."
            }
        }
    }

    /// Transcribe using the language selected in Settings.
    static func transcribe(audioURL: URL) async throws -> String {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") is String
        else {
            throw TranscribeError.missingUsageDescription
        }

        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            let granted = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { s in
                    cont.resume(returning: s == .authorized)
                }
            }
            if !granted { throw TranscribeError.notAuthorized }
        }

        let lang = await MainActor.run { Settings.shared.transcribeLanguage }
        let locale = Locale(identifier: lang)

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscribeError.notAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error {
                    hasResumed = true
                    continuation.resume(throwing: TranscribeError.failed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
