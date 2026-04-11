import AppKit
import SwiftUI

final class NoteWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Notaty"
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 250, height: 150)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: NoteView())
        window.setFrameAutosaveName("NotatyWindow")
        // If no saved frame exists yet, center on screen.
        if window.frameAutosaveName.isEmpty || window.frame.origin == .zero {
            window.center()
        }
        self.init(window: window)
    }
}
