import AppKit

enum NotatyMenuBuilder {
    static func presentHamburgerMenu(anchoredTo button: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = true

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

        let exportItem = NSMenuItem(
            title: "Export All Notes…",
            action: #selector(AppDelegate.exportAll),
            keyEquivalent: "e"
        )
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(exportItem)

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
}
