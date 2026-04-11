import AppKit
import SwiftUI
import Combine

final class NoteWindowController: NSWindowController {
    private var cancellable: AnyCancellable?
    private var resizeObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        let savedWidth = defaults.double(forKey: "noteWindowWidth")
        let savedHeight = defaults.double(forKey: "noteWindowHeight")
        let width = savedWidth >= 250 ? savedWidth : 420
        let height = savedHeight >= 150 ? savedHeight : 340

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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
