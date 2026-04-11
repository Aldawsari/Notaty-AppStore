import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = SettingsWindowController()
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Notaty Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 340))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}
