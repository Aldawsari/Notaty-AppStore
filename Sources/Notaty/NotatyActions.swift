import AppKit
import UniformTypeIdentifiers

// App-level actions shared between the menu bar and the in-window hamburger menu.
enum NotatyActions {
    static func saveSelectedNoteAs() {
        guard
            let id = NotesStore.shared.selectedID,
            let note = NotesStore.shared.notes.first(where: { $0.id == id })
        else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = trimmed.isEmpty ? "Untitled" : trimmed

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try note.text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    // Send a standard editing action through the responder chain so it reaches
    // the currently focused NSTextView regardless of which view is hosting it.
    static func sendEditAction(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
