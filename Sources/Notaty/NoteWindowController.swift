import AppKit
import SwiftUI
import Combine

final class NoteWindowController: NSWindowController {
    let noteID: UUID
    private var cancellable: AnyCancellable?

    init(noteID: UUID) {
        self.noteID = noteID

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Note: we intentionally do NOT set window.level = .floating —
        // macOS native window tabbing refuses to merge floating windows into
        // a tab group, which breaks the multi-tab feature. The window still
        // comes to the front on every status-item click via NSApp.activate.
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 250, height: 150)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "notaty"
        window.contentViewController = NSHostingController(rootView: NoteView(noteID: noteID))
        window.setFrameAutosaveName("NotatyWindow")
        if window.frame.origin == .zero {
            window.center()
        }

        super.init(window: window)

        // Keep window.title (and therefore the native tab label) in sync with
        // the note's title as the user edits it.
        cancellable = NotesStore.shared.$notes
            .map { notes in notes.first(where: { $0.id == noteID })?.title ?? "" }
            .removeDuplicates()
            .sink { [weak window] title in
                window?.title = title.isEmpty ? "Untitled" : title
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
