import AppKit

enum NotatyMenuBuilder {
    static func presentHamburgerMenu(anchoredTo button: NSView) {
        guard let window = button.window else { return }

        let menu = NSMenu()
        menu.autoenablesItems = true

        if let textView = firstTextView(in: window.contentView) {
            // Make sure the text view is first responder so the menu reflects
            // current state (enabled Undo/Redo, paste availability, etc.).
            window.makeFirstResponder(textView)

            let sourceMenu = textView.menu(for: NSApp.currentEvent ?? NSEvent()) ?? textView.menu
            if let source = sourceMenu {
                for item in source.items {
                    if let clone = item.copy() as? NSMenuItem {
                        menu.addItem(clone)
                    }
                }
            }
        }

        if !menu.items.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let saveItem = NSMenuItem(
            title: "Save As…",
            action: #selector(AppDelegate.saveAs),
            keyEquivalent: "s"
        )
        saveItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit Notaty",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // Pop up flush below the button.
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }
}
