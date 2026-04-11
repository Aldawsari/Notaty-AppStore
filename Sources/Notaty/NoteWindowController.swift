import AppKit
import SwiftUI
import Combine

final class NoteWindowController: NSWindowController {
    private var cancellable: AnyCancellable?

    init() {
        let initialSize = Settings.shared.defaultWindowSize.size

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 280, height: 180)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: NotatyRootView())

        super.init(window: window)

        // Keep the window title in sync with the currently selected note.
        cancellable = Publishers.CombineLatest(
            NotesStore.shared.$notes,
            NotesStore.shared.$selectedID
        )
        .map { notes, id -> String in
            guard let id, let note = notes.first(where: { $0.id == id }) else { return "Notaty" }
            let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Untitled" : trimmed
        }
        .removeDuplicates()
        .sink { [weak window] title in
            window?.title = title
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
