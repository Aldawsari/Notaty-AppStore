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

    static func exportAllNotes() {
        let notes = NotesStore.shared.notes
        guard !notes.isEmpty else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "zip")!]
        panel.nameFieldStringValue = "Notaty-Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Write each note as a .txt file
            for (index, note) in notes.enumerated() {
                let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeName = (trimmed.isEmpty ? "Untitled" : trimmed)
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let fileName = "\(index + 1) - \(safeName).txt"
                let fileURL = tempDir.appendingPathComponent(fileName)
                try note.text.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            // Create zip using ditto (macOS built-in, preserves Unicode filenames)
            let zipProcess = Process()
            zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zipProcess.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, url.path]
            try zipProcess.run()
            zipProcess.waitUntilExit()

            // Cleanup temp
            try? FileManager.default.removeItem(at: tempDir)

            if zipProcess.terminationStatus != 0 {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not create zip file."
                alert.alertStyle = .warning
                alert.runModal()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    // Send a standard editing action through the responder chain so it reaches
    // the currently focused NSTextView regardless of which view is hosting it.
    static func sendEditAction(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
