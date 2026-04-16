import Foundation
import WhisperKit

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case failed(String)
    }

    private static var whisperKit: WhisperKit?

    /// Transcribe audio file using WhisperKit with a multilingual model.
    static func transcribe(audioURL: URL) async throws -> String {
        if whisperKit == nil {
            // Use large-v3 turbo for best multilingual accuracy (Arabic + English)
            whisperKit = try await WhisperKit(model: "large-v3-v20240930_turbo")
        }

        guard let pipe = whisperKit else {
            throw TranscribeError.failed("Failed to initialize WhisperKit")
        }

        // Detect language first
        let langResult = try await pipe.detectLanguage(audioPath: audioURL.path)
        let detectedLang = langResult.language

        // Transcribe with detected language
        let options = DecodingOptions(language: detectedLang)
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)

        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw TranscribeError.failed("No speech detected")
        }

        return text
    }
}
