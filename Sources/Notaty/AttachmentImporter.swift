import AppKit
import UniformTypeIdentifiers

/// Stateless helpers that resolve "user wants to attach X" into actual
/// `addAttachments` calls on `NotesStore`. The helpers themselves don't own
/// any state; they take a target note ID and return the count attached.
enum AttachmentImporter {

    /// Open a file picker, multi-select enabled, all types allowed. Attaches
    /// the chosen files to the target note. No-op if the user cancels.
    @MainActor
    static func openPicker(targetNoteID noteID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach Files"
        panel.title = "Attach Files"

        // AppDelegate installs a global mouse-down monitor that hides the
        // main window on any click outside it. Clicking inside NSOpenPanel
        // (e.g. the "Open" button) is technically outside our window, so
        // without suppressing the dismiss flag the main window vanishes
        // when the picker returns.
        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.suppressDismiss = true
        defer { appDelegate?.suppressDismiss = false }

        guard panel.runModal() == .OK else { return }
        attach(urls: panel.urls, to: noteID)
    }

    /// Inspect an `NSPasteboard` for file URLs. Returns true and attaches them
    /// if any are present; returns false otherwise so the caller can fall
    /// through to default text-paste behavior.
    @MainActor
    @discardableResult
    static func attachFromPasteboard(_ pasteboard: NSPasteboard, to noteID: UUID) -> Bool {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return false
        }
        attach(urls: urls, to: noteID)
        return true
    }

    /// Common backend: warn on large files, then call NotesStore.
    @MainActor
    static func attach(urls: [URL], to noteID: UUID) {
        guard !urls.isEmpty else { return }

        // Soft warning at >50MB per file (one-time, dismissible).
        let largeFiles = urls.filter { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return size > 50 * 1024 * 1024
        }
        if !largeFiles.isEmpty {
            showLargeFileWarning()
        }

        let added = NotesStore.shared.addAttachments(to: noteID, from: urls)
        let failed = urls.count - added
        if failed > 0 {
            showCopyError(count: failed)
        }
    }

    @MainActor
    private static func showLargeFileWarning() {
        let key = "didShowLargeAttachmentWarning"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Large attachment"
        alert.informativeText = "Large attachments make note backups slower."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private static func showCopyError(count: Int) {
        let alert = NSAlert()
        alert.messageText = "Could not attach file"
        alert.informativeText = count == 1
            ? "A file could not be copied. Make sure Notaty has permission and that disk space is available."
            : "\(count) files could not be copied. Make sure Notaty has permission and that disk space is available."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
