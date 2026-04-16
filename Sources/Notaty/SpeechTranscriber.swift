import Foundation
import Speech
import WhisperKit

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case failed(String)
        case notAvailable
        case notAuthorized
    }

    private static var whisperKit: WhisperKit?

    /// Detect language with WhisperKit, then transcribe with Apple SFSpeechRecognizer.
    static func transcribe(audioURL: URL) async throws -> String {
        // 1. Detect language using WhisperKit (tiny model — fast)
        if whisperKit == nil {
            whisperKit = try await WhisperKit(model: "tiny")
        }

        var locale = Locale(identifier: "en-US")
        if let pipe = whisperKit {
            let langResult = try await pipe.detectLanguage(audioPath: audioURL.path)
            let lang = langResult.language
            // Map WhisperKit language code to a locale
            locale = mapToLocale(lang)
        }

        // 2. Transcribe with SFSpeechRecognizer using detected locale
        return try await transcribeWithApple(audioURL: audioURL, locale: locale)
    }

    /// Map Whisper language code (e.g. "ar", "en") to an SFSpeechRecognizer locale.
    private static func mapToLocale(_ lang: String) -> Locale {
        let mapping: [String: String] = [
            "ar": "ar-SA",
            "en": "en-US",
            "fr": "fr-FR",
            "de": "de-DE",
            "es": "es-ES",
            "it": "it-IT",
            "pt": "pt-BR",
            "tr": "tr-TR",
            "ru": "ru-RU",
            "ja": "ja-JP",
            "ko": "ko-KR",
            "zh": "zh-CN",
            "hi": "hi-IN",
            "ur": "ur-PK",
            "nl": "nl-NL",
            "pl": "pl-PL",
        ]
        let identifier = mapping[lang] ?? "en-US"
        return Locale(identifier: identifier)
    }

    /// Transcribe using Apple's SFSpeechRecognizer with a specific locale.
    private static func transcribeWithApple(audioURL: URL, locale: Locale) async throws -> String {
        // Request permission if needed
        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            let granted = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
            if !granted {
                throw TranscribeError.notAuthorized
            }
        }

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
