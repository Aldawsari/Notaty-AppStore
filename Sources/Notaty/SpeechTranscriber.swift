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

    /// Transcribe by running Arabic and English in parallel, return the best result.
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

        async let arabic = transcribeWith(locale: Locale(identifier: "ar-SA"), audioURL: audioURL)
        async let english = transcribeWith(locale: Locale(identifier: "en-US"), audioURL: audioURL)

        let arResult = await arabic
        let enResult = await english

        // Pick the result with higher confidence, fall back to whichever succeeded
        switch (arResult, enResult) {
        case (.success(let ar), .success(let en)):
            // Use the one with higher confidence
            if ar.confidence >= en.confidence {
                return ar.text
            } else {
                return en.text
            }
        case (.success(let ar), .failure):
            return ar.text
        case (.failure, .success(let en)):
            return en.text
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
