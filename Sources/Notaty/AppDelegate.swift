import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let windowController = NoteWindowController()
    private var settingsCancellable: AnyCancellable?
    private var pinnedCancellable: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var localEscMonitor: Any?
    /// Set to true to prevent the window from auto-hiding on outside clicks.
    /// File pickers and permission dialogs set this to avoid dismissing the
    /// window while AppKit owns the interaction.
    var suppressDismiss = false

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

        // Respond to runtime toggles of the pinned setting:
        // - true → ensure the dismiss monitor is removed (window stays put)
        // - false → if the window is currently visible, reinstall the monitor
        pinnedCancellable = Settings.shared.$pinned
            .dropFirst()  // skip the initial value; showWindow handles first install
            .sink { [weak self] pinned in
                guard let self else { return }
                if pinned {
                    self.removeDismissMonitors()
                } else if let window = self.windowController.window, window.isVisible {
                    self.installDismissMonitors()
                }
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
        menu.addItem(withTitle: "Quit Notaty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        // Only install the dismiss monitor when the user hasn't pinned the
        // window. When pinned, the window stays put until explicitly closed.
        if !Settings.shared.pinned {
            installDismissMonitors()
        }
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
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, !self.suppressDismiss else { return }
            self.hideWindow()
        }
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

    @objc func exportAll() {
        NotatyActions.exportAllNotes()
    }

    @objc func openSettings() {
        SettingsWindowController.show()
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
                // QR detection runs first; it never blocks downstream OCR
                // (returns [] on any failure). OCR runs regardless. We then
                // interleave the two streams by visual position.
                QRDecoder.detect(image: image) { [weak self] qrs in
                    guard let self else { return }
                    OCRService.recognize(image: image) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success(let lines):
                            let combined = self.composeQRsAndOCR(qrs: qrs, ocrLines: lines)
                            if !combined.isEmpty {
                                self.createNoteFromOCR(text: combined)
                            } else {
                                self.showOCRError(.noText)
                            }
                        case .failure(let error):
                            if qrs.isEmpty {
                                self.showOCRError(error)
                            } else {
                                let combined = self.composeQRsAndOCR(qrs: qrs, ocrLines: [])
                                self.createNoteFromOCR(text: combined)
                            }
                        }
                        self.restoreWindow(wasVisible: wasVisible)
                    }
                }
            } else {
                self.restoreWindow(wasVisible: wasVisible)
            }
        }
    }

    /// Merges QR payloads and OCR lines into a single string sorted top-to-
    /// bottom by Vision's normalized boundingBox.midY (descending), tie-broken
    /// by midX (ascending). Adjacent text lines are joined by `\n`; any
    /// boundary touching a QR uses `\n\n` so each QR payload sits in its own
    /// paragraph regardless of where it falls between OCR lines. Mirrors the
    /// Nassakh `deliverCombined` ordering rule.
    private func composeQRsAndOCR(qrs: [DetectedQR], ocrLines: [OCRLine]) -> String {
        struct Item {
            let isQR: Bool
            let midY: CGFloat
            let midX: CGFloat
            let text: String
        }

        let items: [Item] =
            qrs.map { Item(isQR: true, midY: $0.boundingBox.midY, midX: $0.boundingBox.midX, text: $0.payload) }
            + ocrLines.map { Item(isQR: false, midY: $0.boundingBox.midY, midX: $0.boundingBox.midX, text: $0.text) }

        let sorted = items.sorted { a, b in
            if a.midY != b.midY { return a.midY > b.midY }
            return a.midX < b.midX
        }

        guard !sorted.isEmpty else { return "" }

        var combined = sorted[0].text
        for i in 1..<sorted.count {
            let separator = (sorted[i].isQR || sorted[i - 1].isQR) ? "\n\n" : "\n"
            combined += separator + sorted[i].text
        }
        return combined
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
