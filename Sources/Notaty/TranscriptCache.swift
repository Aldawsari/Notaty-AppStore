import Foundation
import Combine

/// Session-scoped, in-memory transcript store for voice-note attachments.
/// Keyed by `Attachment.storedName`. Cleared on app quit (no persistence).
/// VoiceNoteCardView observes via `@ObservedObject` and reads via
/// `state(for:)`.
final class TranscriptCache: ObservableObject {
    static let shared = TranscriptCache()

    enum State {
        case idle
        case loading
        case ready(String)
        case failed(Error)
    }

    @Published private(set) var states: [String: State] = [:]

    private init() {}

    func state(for storedName: String) -> State {
        states[storedName] ?? .idle
    }

    /// Run on the main actor so observed UI updates dispatch correctly.
    @MainActor
    func transcribe(storedName: String, audioURL: URL) async {
        states[storedName] = .loading
        do {
            let text = try await SpeechTranscriber.transcribe(audioURL: audioURL)
            states[storedName] = .ready(text)
        } catch {
            states[storedName] = .failed(error)
        }
    }

    func clear(storedName: String) {
        states.removeValue(forKey: storedName)
    }
}
