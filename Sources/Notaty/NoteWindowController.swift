import AppKit
import SwiftUI
import Combine

final class NoteWindowController: NSWindowController {
    private var cancellable: AnyCancellable?
    private var resizeObserver: NSObjectProtocol?

    private static let widthKey = "windowWidth"
    private static let heightKey = "windowHeight"

    // Returns the last user-resized size, or the Settings default if the
    // user has never resized.
    static var savedSize: NSSize {
        let defaults = UserDefaults.standard
        let w = defaults.double(forKey: widthKey)
        let h = defaults.double(forKey: heightKey)
        if w >= 280, h >= 180 {
            return NSSize(width: w, height: h)
        }
        return Settings.shared.defaultWindowSize.size
    }

    static func saveSize(_ size: NSSize) {
        let defaults = UserDefaults.standard
        defaults.set(Double(size.width), forKey: widthKey)
        defaults.set(Double(size.height), forKey: heightKey)
    }

    init() {
        let initialSize = Self.savedSize

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

        // Persist user-resized dimensions so the window reopens at the same size.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let w = notification.object as? NSWindow else { return }
            Self.saveSize(w.frame.size)
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
