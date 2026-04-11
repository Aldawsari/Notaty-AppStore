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
        // Match Settings: opaque, windowBackgroundColor, no popover material.
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentViewController = NSHostingController(rootView: NotatyRootView())

        super.init(window: window)

        // Keep the window title in sync with the currently selected note's
        // title. `.removeDuplicates()` ensures the `window?.title` setter only
        // runs when the resolved string actually changes, so body-only edits
        // don't hit AppKit.
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
        .receive(on: DispatchQueue.main)
        .sink { [weak window] title in
            window?.title = title
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
