import AppKit

enum NotatyMenuBuilder {
    static func presentHamburgerMenu(anchoredTo button: NSView) {
        guard let window = button.window else { return }

        let menu = NSMenu()
        menu.autoenablesItems = true

        // Edit ▶ — clones NSTextView's own contextual menu so it includes the
        // dynamic titles (Undo Typing / Redo) and AppKit's provided
        // Find / Spelling and Grammar / Substitutions / Transformations /
        // Speech submenus.
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editSubmenu = NSMenu(title: "Edit")
        editSubmenu.autoenablesItems = true

        if let textView = firstTextView(in: window.contentView) {
            // Make sure the text view is first responder so cloned items reflect
            // current state (Undo availability, paste availability, etc.).
            window.makeFirstResponder(textView)

            let sourceMenu = textView.menu(for: NSApp.currentEvent ?? NSEvent()) ?? textView.menu
            if let source = sourceMenu {
                for item in source.items {
                    if let clone = item.copy() as? NSMenuItem {
                        editSubmenu.addItem(clone)
                    }
                }
            }
        }

        editItem.submenu = editSubmenu
        editItem.isEnabled = !editSubmenu.items.isEmpty
        menu.addItem(editItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

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
