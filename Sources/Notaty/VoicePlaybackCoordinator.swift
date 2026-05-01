import Foundation

/// Enforces a single-active-player invariant across all VoiceNoteCardView
/// instances. Each card calls `didStartPlaying(_:)` from its play action;
/// the coordinator pauses any prior player. Holds a weak reference so
/// nothing leaks when a card is dismantled.
final class VoicePlaybackCoordinator {
    static let shared = VoicePlaybackCoordinator()

    private weak var activePlayer: AudioPlayer?

    private init() {}

    func didStartPlaying(_ player: AudioPlayer) {
        if let prior = activePlayer, prior !== player {
            prior.pause()
        }
        activePlayer = player
    }
}
