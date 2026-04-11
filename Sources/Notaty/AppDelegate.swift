import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controllers: [UUID: NoteWindowController] = [:]
    private var isTerminating = false

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
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

        // Bring the first one front, then merge the rest as tabs.
        let ordered = NotesStore.shared.notes.compactMap { controllers[$0.id] }
        guard let first = ordered.first, let firstWindow = first.window else { return }
        firstWindow.makeKeyAndOrderFront(nil)

        for controller in ordered.dropFirst() {
            guard let window = controller.window else { continue }
            if window.tabGroup == nil {
                firstWindow.addTabbedWindow(window, ordered: .above)
            } else {
                window.orderFront(nil)
            }
        }
        firstWindow.makeKeyAndOrderFront(nil)
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
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isTerminating { return true }

        guard
            let controller = controllers.values.first(where: { $0.window === sender })
        else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "This note will be permanently removed and cannot be recovered."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        NotesStore.shared.delete(id: controller.noteID)
        controllers.removeValue(forKey: controller.noteID)

        // If that was the last note, create a fresh empty one so the app is
        // never in a zero-note state.
        if NotesStore.shared.notes.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let note = NotesStore.shared.addNote()
                self.makeController(for: note.id).window?.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
