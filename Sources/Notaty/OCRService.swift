import AppKit
import Vision

enum OCRError: Error {
    case emptyImage
    case noText
    case vision(Error)
}

enum OCRService {
    static func recognize(image: CGImage, completion: @escaping (Result<String, OCRError>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(.vision(error))) }
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            DispatchQueue.main.async {
                if text.isEmpty {
                    completion(.failure(.noText))
                } else {
                    completion(.success(text))
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Let Vision detect the dominant language from the captured image and
        // pick the appropriate recognition model. Without this flag Vision
        // just uses recognitionLanguages[0] as the primary, so Arabic only
        // worked if it came first — which broke English.
        request.automaticallyDetectsLanguage = true

        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        // Arabic first so that when the image is Arabic, Vision's auto-detect
        // has the best hint. English still works because automaticallyDetectsLanguage
        // overrides ordering.
        let wanted = [
            "ar-SA", "ars-SA",
            "en-US",
            "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR",
            "ru-RU", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR",
            "tr-TR", "nl-NL",
        ]
        let languages = wanted.filter { supported.contains($0) }
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(.failure(.vision(error))) }
            }
        }
    }
}
