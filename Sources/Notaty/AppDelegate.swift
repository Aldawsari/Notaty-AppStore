import AppKit
import Combine
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let windowController = NoteWindowController()
    private var settingsCancellable: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var localEscMonitor: Any?
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
                NoteWindowController.saveSize(preset.size)
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
            hideWindow()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        applyDefaultSize(NoteWindowController.savedSize, reposition: false)
        positionUnderStatusItem(window)

        // Fade in.
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        installDismissMonitors()
    }

    private func hideWindow() {
        guard let window = windowController.window, window.isVisible else { return }
        removeDismissMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        })
    }

    private func installDismissMonitors() {
        // Click outside the note window → hide (native popover behavior).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hideWindow()
        }
        // Escape inside the window → hide.
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && event.window === self?.windowController.window {
                self?.hideWindow()
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
        if let m = localEscMonitor {
            NSEvent.removeMonitor(m)
            localEscMonitor = nil
        }
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
        SettingsWindowController.show(updater: updaterController.updater)
    }

    @objc func openQuickSwitcher() {
        QuickSwitcherWindowController.show()
    }

    @objc func startOCRCapture() {
        // Screen Recording permission is required for CGWindowListCreateImage
        // to see anything other than the desktop wallpaper. On unsigned local
        // builds the TCC prompt doesn't always appear automatically, so ask
        // for it explicitly the first time and fall through only when granted.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission required"
            alert.informativeText = """
            Notaty needs Screen Recording permission to capture a region of the screen for OCR.

            Open System Settings → Privacy & Security → Screen Recording and enable Notaty, then quit and relaunch Notaty.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        guard let window = windowController.window else { return }
        let wasVisible = window.isVisible
        if wasVisible { window.orderOut(nil) }

        ScreenRegionSelector.begin { [weak self] rect in
            guard let self else { return }
            if let rect, let image = ScreenCapture.capture(rect: rect) {
                Self.playShutterSound()
                OCRService.recognize(image: image) { result in
                    switch result {
                    case .success(let text):
                        self.createNoteFromOCR(text: text)
                    case .failure(let error):
                        self.showOCRError(error)
                    }
                    self.restoreWindow(wasVisible: wasVisible)
                }
            } else {
                self.restoreWindow(wasVisible: wasVisible)
            }
        }
    }

    private func createNoteFromOCR(text: String) {
        let note = NotesStore.shared.addNote()
        NotesStore.shared.update(id: note.id) {
            $0.title = "Scanned " + Self.ocrTimestamp()
            $0.text = text
        }
    }

    private func showOCRError(_ error: OCRError) {
        let alert = NSAlert()
        switch error {
        case .emptyImage:
            alert.messageText = "Nothing to scan"
            alert.informativeText = "The selection was empty."
        case .noText:
            alert.messageText = "No text found"
            alert.informativeText = "Notaty could not recognize any text in that selection."
        case .vision(let err):
            alert.messageText = "OCR failed"
            alert.informativeText = err.localizedDescription
        }
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func restoreWindow(wasVisible: Bool) {
        guard wasVisible, let window = windowController.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        positionUnderStatusItem(window)
        window.makeKeyAndOrderFront(nil)
    }

    private static func playShutterSound() {
        let candidates = [
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path),
               let sound = NSSound(contentsOfFile: path, byReference: true) {
                sound.play()
                return
            }
        }
        NSSound.beep()
    }

    private static func ocrTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: Date())
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
