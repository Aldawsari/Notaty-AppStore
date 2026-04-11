import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controllers: [UUID: NoteWindowController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "Notaty"
            )
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Ensure there is always at least one note on first launch.
        if NotesStore.shared.notes.isEmpty {
            _ = NotesStore.shared.addNote()
        }
    }

    // MARK: - Main menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Notaty",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(
            title: "New Tab",
            action: #selector(newTab),
            keyEquivalent: "t"
        )
        newTabItem.target = self
        fileMenu.addItem(newTabItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status item click

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleWindows()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "New Note",
            action: #selector(newTab),
            keyEquivalent: "t"
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit Notaty",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        for item in menu.items { item.target = item.target ?? self }
        if let button = statusItem.button, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    // MARK: - Window management

    private func toggleWindows() {
        let openWindows = controllers.values.compactMap { $0.window }.filter { $0.isVisible }
        if !openWindows.isEmpty {
            for window in openWindows { window.orderOut(nil) }
            return
        }
        showAllNotes()
    }

    private func showAllNotes() {
        NSApp.activate(ignoringOtherApps: true)

        // Create any controllers we don't already have.
        for note in NotesStore.shared.notes where controllers[note.id] == nil {
            makeController(for: note.id)
        }

        let ordered = NotesStore.shared.notes.compactMap { controllers[$0.id] }
        guard let first = ordered.first, let firstWindow = first.window else { return }

        // The first window must be visible before addTabbedWindow will merge
        // anything into its tab group — otherwise the additional tabs silently
        // end up as detached windows (or not shown at all).
        positionUnderStatusItem(firstWindow)
        firstWindow.makeKeyAndOrderFront(nil)

        for controller in ordered.dropFirst() {
            guard let window = controller.window, window !== firstWindow else { continue }
            if window.tabGroup == nil {
                firstWindow.addTabbedWindow(window, ordered: .above)
            } else {
                window.orderFront(nil)
            }
        }
        firstWindow.makeKeyAndOrderFront(nil)
    }

    // Snap the given window flush below the menu bar, horizontally centered
    // under the status item button, clamped inside the screen's visible frame.
    // Called every show so the popover feel is preserved even if the user
    // previously dragged the window.
    private func positionUnderStatusItem(_ window: NSWindow) {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window
        else { return }

        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        let buttonRectOnScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let size = window.frame.size
        let x = min(
            max(visible.minX, buttonRectOnScreen.midX - size.width / 2),
            visible.maxX - size.width
        )
        let y = visible.maxY - size.height
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @discardableResult
    private func makeController(for id: UUID) -> NoteWindowController {
        let controller = NoteWindowController(noteID: id)
        controller.window?.delegate = self
        controllers[id] = controller
        return controller
    }

    @objc private func newTab() {
        let note = NotesStore.shared.addNote()
        let controller = makeController(for: note.id)
        guard let newWindow = controller.window else { return }

        NSApp.activate(ignoringOtherApps: true)
        if let key = NSApp.keyWindow ?? controllers.values.compactMap({ $0.window }).first(where: { $0.isVisible }) {
            key.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        } else {
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    // Closing a window or tab only hides the UI — the underlying note stays
    // in the store and reappears next time the user opens the menu bar.
    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let id = controllers.first(where: { $0.value.window === window })?.key
        else { return }
        controllers.removeValue(forKey: id)
    }
}
