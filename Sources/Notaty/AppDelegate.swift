import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let windowController = NoteWindowController()

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
            NotesStore.shared.addNote()
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
        let newNoteItem = NSMenuItem(
            title: "New Note",
            action: #selector(newNote),
            keyEquivalent: "t"
        )
        newNoteItem.target = self
        fileMenu.addItem(newNoteItem)
        let saveAsItem = NSMenuItem(
            title: "Save As…",
            action: #selector(saveAs),
            keyEquivalent: "s"
        )
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = self
        fileMenu.addItem(saveAsItem)
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
            toggleWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "t")
        newItem.target = self
        menu.addItem(newItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit Notaty",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        if let button = statusItem.button, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    private func toggleWindow() {
        guard let window = windowController.window else { return }
        if window.isVisible {
            window.orderOut(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        positionUnderStatusItem(window)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func saveAs() {
        NotatyActions.saveSelectedNoteAs()
    }

    @objc private func newNote() {
        NotesStore.shared.addNote()
        guard let window = windowController.window else { return }
        if !window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            positionUnderStatusItem(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // Snap the window flush below the menu bar, horizontally centered under
    // the status item button, clamped inside the screen's visible frame.
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
}
