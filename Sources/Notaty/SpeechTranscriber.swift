import Foundation
import Speech
import WhisperKit

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case failed(String)
        case notAvailable
        case notAuthorized
    }

    private static var whisperTiny: WhisperKit?
    private static var whisperLarge: WhisperKit?

    // MARK: - Public API

    /// Transcribe audio file. Uses enhanced (WhisperKit large) or standard (Apple) mode.
    static func transcribe(audioURL: URL) async throws -> String {
        if Settings.shared.enhancedTranscription, Settings.shared.enhancedModelReady {
            return try await transcribeWithWhisperLarge(audioURL: audioURL)
        } else {
            return try await transcribeStandard(audioURL: audioURL)
        }
    }

    /// Download the large Whisper model for enhanced transcription. Reports progress.
    static func downloadEnhancedModel(onProgress: @escaping (String) -> Void) async throws {
        onProgress("Downloading model...")
        let config = WhisperKitConfig(model: "large-v3-v20240930_turbo")
        whisperLarge = try await WhisperKit(config)
        await MainActor.run {
            Settings.shared.enhancedModelReady = true
        }
        onProgress("Ready")
    }

    /// Check if the large model is already cached locally.
    static func checkEnhancedModelCached() -> Bool {
        let cacheDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent()
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo")
        if let path = cacheDir?.path, FileManager.default.fileExists(atPath: path) {
            return true
        }
        // Also check the default HF cache paths
        let homePaths = [
            NSHomeDirectory() + "/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo",
            NSHomeDirectory() + "/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB",
        ]
        for p in homePaths {
            if FileManager.default.fileExists(atPath: p) { return true }
        }
        return false
    }

    // MARK: - Enhanced Mode (WhisperKit large)

    /// Transcribe using WhisperKit large model — handles mixed languages natively.
    private static func transcribeWithWhisperLarge(audioURL: URL) async throws -> String {
        if whisperLarge == nil {
            // Try to load from cache
            let config = WhisperKitConfig(model: "large-v3-v20240930_turbo")
            whisperLarge = try await WhisperKit(config)
        }
        guard let pipe = whisperLarge else {
            throw TranscribeError.failed("Enhanced model not available")
        }

        let results = try await pipe.transcribe(audioPath: audioURL.path)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty { throw TranscribeError.failed("No speech detected") }
        return text
    }

    // MARK: - Standard Mode (WhisperKit tiny detect + Apple transcribe)

    /// Standard: detect language with WhisperKit tiny, transcribe with Apple.
    private static func transcribeStandard(audioURL: URL) async throws -> String {
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

        let detectedLang = await detectLanguage(audioURL: audioURL)

        if let lang = detectedLang, lang != "ar" {
            return try await transcribeWithApple(audioURL: audioURL, locale: mapToLocale(lang))
        }

        // Arabic or uncertain — try both
        async let arResult = tryTranscribe(audioURL: audioURL, locale: Locale(identifier: "ar-SA"))
        async let enResult = tryTranscribe(audioURL: audioURL, locale: Locale(identifier: "en-US"))

        let ar = await arResult
        let en = await enResult

        switch (ar, en) {
        case (.success(let arText), .success(let enText)):
            if detectedLang == "ar" { return arText }
            return arText.count >= enText.count ? arText : enText
        case (.success(let text), .failure):
            return text
        case (.failure, .success(let text)):
            return text
        case (.failure(let err), .failure):
            throw err
        }
    }

    // MARK: - Language Detection

    private static func detectLanguage(audioURL: URL) async -> String? {
        do {
            if whisperTiny == nil {
                if let modelPath = bundledModelPath() {
                    let config = WhisperKitConfig(modelFolder: modelPath)
                    whisperTiny = try await WhisperKit(config)
                } else {
                    whisperTiny = try await WhisperKit(WhisperKitConfig(model: "tiny"))
                }
            }
            guard let pipe = whisperTiny else { return nil }
            let result = try await pipe.detectLanguage(audioPath: audioURL.path)
            return result.language
        } catch {
            return nil
        }
    }

    private static func bundledModelPath() -> String? {
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("Models/openai_whisper-tiny")
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - Apple Transcription

    private static func tryTranscribe(audioURL: URL, locale: Locale) async -> Result<String, Error> {
        do {
            return .success(try await transcribeWithApple(audioURL: audioURL, locale: locale))
        } catch {
            return .failure(error)
        }
    }

    private static func mapToLocale(_ lang: String) -> Locale {
        let mapping: [String: String] = [
            "ar": "ar-SA", "en": "en-US", "fr": "fr-FR", "de": "de-DE",
            "es": "es-ES", "it": "it-IT", "pt": "pt-BR", "tr": "tr-TR",
            "ru": "ru-RU", "ja": "ja-JP", "ko": "ko-KR", "zh": "zh-CN",
            "hi": "hi-IN", "ur": "ur-PK", "nl": "nl-NL", "pl": "pl-PL",
        ]
        return Locale(identifier: mapping[lang] ?? "en-US")
    }

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
