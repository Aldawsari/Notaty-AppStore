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

    static func transcribe(audioURL: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TranscribeError.notAvailable
        }

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

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: TranscribeError.failed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
