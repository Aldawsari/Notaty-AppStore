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

    /// Append to the shelf. Each drop accumulates; the user can keep dropping
    /// files onto the menu bar icon before picking a destination, and all
    /// of them attach to the chosen note. URLs already in the shelf are
    /// skipped (drop the same file twice → counts once).
    func add(_ newURLs: [URL]) {
        let existing = Set(urls)
        let toAppend = newURLs.filter { !existing.contains($0) }
        guard !toAppend.isEmpty else { return }
        urls.append(contentsOf: toAppend)
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
