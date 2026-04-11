import AppKit
import SwiftUI
import Combine

final class NoteWindowController: NSWindowController {
    let noteID: UUID
    private var cancellable: AnyCancellable?
    private var resizeObserver: NSObjectProtocol?

    init(noteID: UUID) {
        self.noteID = noteID

        // Shared size across all tabs (position is managed per-show by AppDelegate).
        // Can't use setFrameAutosaveName — multiple windows writing to the same
        // autosave key clobber each other, which among other things breaks tab
        // merging on the next show.
        let defaults = UserDefaults.standard
        let savedWidth = defaults.double(forKey: "noteWindowWidth")
        let savedHeight = defaults.double(forKey: "noteWindowHeight")
        let width = savedWidth >= 250 ? savedWidth : 400
        let height = savedHeight >= 150 ? savedHeight : 300

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

        super.init(window: window)

        // Keep window.title (and therefore the native tab label) in sync with
        // the note's title as the user edits it.
        cancellable = NotesStore.shared.$notes
            .map { notes in notes.first(where: { $0.id == noteID })?.title ?? "" }
            .removeDuplicates()
            .sink { [weak window] title in
                window?.title = title.isEmpty ? "Untitled" : title
            }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { note in
            guard let w = note.object as? NSWindow else { return }
            let size = w.frame.size
            let d = UserDefaults.standard
            d.set(Double(size.width), forKey: "noteWindowWidth")
            d.set(Double(size.height), forKey: "noteWindowHeight")
        }
    }

    deinit {
        if let obs = resizeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
