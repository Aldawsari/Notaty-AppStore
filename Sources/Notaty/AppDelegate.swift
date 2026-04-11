import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let windowController = NoteWindowController()
    private var settingsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = Settings.shared.theme.nsAppearance
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

        // Live-resize the note window when the default size setting changes.
        settingsCancellable = Settings.shared.$defaultWindowSize
            .dropFirst()
            .sink { [weak self] preset in
                self?.applyDefaultSize(preset.size, reposition: true)
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
        let switcherItem = NSMenuItem(
            title: "Quick Switcher…",
            action: #selector(openQuickSwitcher),
            keyEquivalent: "k"
        )
        switcherItem.target = self
        fileMenu.addItem(switcherItem)
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

        let formatMenuItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")
        let writingMenuItem = NSMenuItem(title: "Writing Direction", action: nil, keyEquivalent: "")
        let writingSubmenu = NSMenu(title: "Writing Direction")

        let naturalItem = NSMenuItem(
            title: "Natural (auto)",
            action: #selector(setDirectionAuto),
            keyEquivalent: ""
        )
        naturalItem.target = self
        writingSubmenu.addItem(naturalItem)

        let ltrItem = NSMenuItem(
            title: "Left to Right",
            action: #selector(setDirectionLTR),
            keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        )
        ltrItem.keyEquivalentModifierMask = [.control, .command]
        ltrItem.target = self
        writingSubmenu.addItem(ltrItem)

        let rtlItem = NSMenuItem(
            title: "Right to Left",
            action: #selector(setDirectionRTL),
            keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        )
        rtlItem.keyEquivalentModifierMask = [.control, .command]
        rtlItem.target = self
        writingSubmenu.addItem(rtlItem)

        writingMenuItem.submenu = writingSubmenu
        formatMenu.addItem(writingMenuItem)
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func setDirectionAuto() { applyDirection(.auto) }
    @objc func setDirectionLTR() { applyDirection(.ltr) }
    @objc func setDirectionRTL() { applyDirection(.rtl) }

    private func applyDirection(_ direction: NoteDirection) {
        guard let id = NotesStore.shared.selectedID else { return }
        NotesStore.shared.setDirection(direction, for: id)
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
        applyDefaultSize(Settings.shared.defaultWindowSize.size, reposition: false)
        positionUnderStatusItem(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func applyDefaultSize(_ size: NSSize, reposition: Bool) {
        guard let window = windowController.window else { return }
        var frame = window.frame
        let oldSize = frame.size
        frame.size = size
        // Keep the titlebar anchored (origin.y is the bottom-left in AppKit).
        frame.origin.y += oldSize.height - size.height
        window.setFrame(frame, display: true, animate: false)
        if reposition && window.isVisible {
            positionUnderStatusItem(window)
        }
    }

    @objc func saveAs() {
        NotatyActions.saveSelectedNoteAs()
    }

    @objc func openSettings() {
        SettingsWindowController.show()
    }

    @objc func openQuickSwitcher() {
        QuickSwitcherWindowController.show()
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
