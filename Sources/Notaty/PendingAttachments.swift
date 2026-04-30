import Foundation
import Combine

/// In-memory state for drop-to-attach: holds the URLs that landed on the menu
/// bar icon until the user picks a destination note. The UI observes
/// `urls.isEmpty` to show/hide the banner.
final class PendingAttachments: ObservableObject {
    static let shared = PendingAttachments()

    @Published private(set) var urls: [URL] = []

    var isPending: Bool { !urls.isEmpty }

    /// Human-readable description for the banner: filename for one, count for many.
    var description: String {
        if urls.count == 1 { return urls[0].lastPathComponent }
        return "\(urls.count) files"
    }

    /// Replace the pending list. Last-drop-wins semantics: a fresh drop while
    /// a banner is up replaces the previous URLs.
    func set(_ newURLs: [URL]) {
        urls = newURLs
    }

    /// Atomically take the URLs and clear the state. Returns the URLs the
    /// caller should attach.
    func consume() -> [URL] {
        let out = urls
        urls = []
        return out
    }

    /// Discard pending without attaching. Used for Esc / banner ×.
    func clear() {
        urls = []
    }

    private init() {}
}
