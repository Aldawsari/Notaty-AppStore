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

        // Prefer English + Arabic + French when Vision supports them.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["en-US", "ar-SA", "ar", "fr-FR"]
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
