import AppKit
import Vision

enum OCRError: Error {
    case emptyImage
    case noText
    case vision(Error)
}

/// One recognized text line with its position in normalized image space
/// (Vision's coordinates: origin lower-left, both axes 0…1).
struct OCRLine {
    let text: String
    let boundingBox: CGRect
}

enum OCRService {
    static func recognize(image: CGImage, completion: @escaping (Result<[OCRLine], OCRError>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(.vision(error))) }
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines: [OCRLine] = observations.compactMap { obs in
                guard let candidate = obs.topCandidates(1).first?.string, !candidate.isEmpty else {
                    return nil
                }
                return OCRLine(text: candidate, boundingBox: obs.boundingBox)
            }
            DispatchQueue.main.async {
                if lines.isEmpty {
                    completion(.failure(.noText))
                } else {
                    completion(.success(lines))
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
