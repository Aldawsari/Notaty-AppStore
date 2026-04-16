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

    /// Hybrid transcription: WhisperKit detects language, Apple transcribes.
    /// Falls back to trying both Arabic + English if detection is uncertain.
    static func transcribe(audioURL: URL) async throws -> String {
        // Ensure speech recognition permission
        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            let granted = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { s in
                    cont.resume(returning: s == .authorized)
                }
            }
            if !granted { throw TranscribeError.notAuthorized }
        }

        // 1. Try language detection with WhisperKit
        let detectedLang = await detectLanguage(audioURL: audioURL)

        if let lang = detectedLang, lang != "ar" {
            // Confident it's not Arabic — transcribe with detected language
            return try await transcribeWithApple(audioURL: audioURL, locale: mapToLocale(lang))
        }

        // 2. If detected Arabic OR detection failed/uncertain — try both
        //    Run Arabic and English in parallel, pick the better result
        async let arResult = tryTranscribe(audioURL: audioURL, locale: Locale(identifier: "ar-SA"))
        async let enResult = tryTranscribe(audioURL: audioURL, locale: Locale(identifier: "en-US"))

        let ar = await arResult
        let en = await enResult

        switch (ar, en) {
        case (.success(let arText), .success(let enText)):
            // If WhisperKit said Arabic, trust it
            if detectedLang == "ar" { return arText }
            // Otherwise pick the longer result (usually more meaningful)
            return arText.count >= enText.count ? arText : enText
        case (.success(let text), .failure):
            return text
        case (.failure, .success(let text)):
            return text
        case (.failure(let err), .failure):
            throw err
        }
    }

    /// Detect language using bundled WhisperKit model. Returns nil if detection fails.
    private static func detectLanguage(audioURL: URL) async -> String? {
        do {
            if whisperKit == nil {
                if let modelPath = bundledModelPath() {
                    let config = WhisperKitConfig(modelFolder: modelPath)
                    whisperKit = try await WhisperKit(config)
                } else {
                    whisperKit = try await WhisperKit(WhisperKitConfig(model: "tiny"))
                }
            }
            guard let pipe = whisperKit else { return nil }
            let result = try await pipe.detectLanguage(audioPath: audioURL.path)
            return result.language
        } catch {
            return nil
        }
    }

    /// Look for the bundled model inside the app's Resources directory.
    private static func bundledModelPath() -> String? {
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("Models/openai_whisper-tiny")
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Try transcription, returning Result instead of throwing.
    private static func tryTranscribe(audioURL: URL, locale: Locale) async -> Result<String, Error> {
        do {
            let text = try await transcribeWithApple(audioURL: audioURL, locale: locale)
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// Map Whisper language code to an SFSpeechRecognizer locale.
    private static func mapToLocale(_ lang: String) -> Locale {
        let mapping: [String: String] = [
            "ar": "ar-SA", "en": "en-US", "fr": "fr-FR", "de": "de-DE",
            "es": "es-ES", "it": "it-IT", "pt": "pt-BR", "tr": "tr-TR",
            "ru": "ru-RU", "ja": "ja-JP", "ko": "ko-KR", "zh": "zh-CN",
            "hi": "hi-IN", "ur": "ur-PK", "nl": "nl-NL", "pl": "pl-PL",
        ]
        return Locale(identifier: mapping[lang] ?? "en-US")
    }

    /// Transcribe using Apple's SFSpeechRecognizer with a specific locale.
    private static func transcribeWithApple(audioURL: URL, locale: Locale) async throws -> String {
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
