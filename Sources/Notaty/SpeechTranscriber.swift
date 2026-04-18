import Speech

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case notAvailable
        case notAuthorized
        case failed(String)
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Transcribe by running two languages in parallel (from Settings), return the best result.
    static func transcribe(audioURL: URL) async throws -> String {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            let granted = await withCheckedContinuation { cont in
                requestPermission { granted in
                    cont.resume(returning: granted)
                }
            }
            if !granted {
                throw TranscribeError.notAuthorized
            }
        }

        let lang1 = await MainActor.run { Settings.shared.transcribeLang1 }
        let lang2 = await MainActor.run { Settings.shared.transcribeLang2 }

        async let result1 = transcribeWith(locale: Locale(identifier: lang1), audioURL: audioURL)
        async let result2 = transcribeWith(locale: Locale(identifier: lang2), audioURL: audioURL)

        let r1 = await result1
        let r2 = await result2

        switch (r1, r2) {
        case (.success(let a), .success(let b)):
            return a.confidence >= b.confidence ? a.text : b.text
        case (.success(let a), .failure):
            return a.text
        case (.failure, .success(let b)):
            return b.text
        case (.failure(let err), .failure):
            throw err
        }
    }

    private struct TranscriptionResult {
        let text: String
        let confidence: Float
    }

    private static func transcribeWith(locale: Locale, audioURL: URL) async -> Result<TranscriptionResult, Error> {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return .failure(TranscribeError.notAvailable)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        do {
            let result: TranscriptionResult = try await withCheckedThrowingContinuation { continuation in
                var hasResumed = false
                recognizer.recognitionTask(with: request) { result, error in
                    guard !hasResumed else { return }
                    if let error {
                        hasResumed = true
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result, result.isFinal {
                        hasResumed = true
                        let segments = result.bestTranscription.segments
                        let avgConfidence = segments.isEmpty ? 0 : segments.reduce(0) { $0 + $1.confidence } / Float(segments.count)
                        continuation.resume(returning: TranscriptionResult(
                            text: result.bestTranscription.formattedString,
                            confidence: avgConfidence
                        ))
                    }
                }
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}
