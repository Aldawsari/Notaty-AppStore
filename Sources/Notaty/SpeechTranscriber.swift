import Foundation
import WhisperKit

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case failed(String)
    }

    private static var whisperKit: WhisperKit?

    /// Transcribe audio file using WhisperKit (on-device, auto language detection).
    static func transcribe(audioURL: URL) async throws -> String {
        // Reuse the pipeline if already loaded, otherwise initialize
        if whisperKit == nil {
            whisperKit = try await WhisperKit()
        }

        guard let pipe = whisperKit else {
            throw TranscribeError.failed("Failed to initialize WhisperKit")
        }

        let results = try await pipe.transcribe(audioPath: audioURL.path)

        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw TranscribeError.failed("No speech detected")
        }

        return text
    }
}
