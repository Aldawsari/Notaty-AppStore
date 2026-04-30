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

            // Human-readable .txt files (preserved for backward compat —
            // users who unzip with Finder still see readable text).
            for (index, note) in notes.enumerated() {
                let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeName = (trimmed.isEmpty ? "Untitled" : trimmed)
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let fileName = "\(index + 1) - \(safeName).txt"
                let fileURL = tempDir.appendingPathComponent(fileName)
                try note.text.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            // Manifest with full structured data — this is what Notaty itself
            // reads on import to round-trip attachments. Older Notaty versions
            // (pre-attachments) ignore the manifest and just import the .txt.
            let manifestURL = tempDir.appendingPathComponent("_manifest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(notes).write(to: manifestURL, options: .atomic)

            // Copy each attachment file into the export tree, preserving
            // the storedName (so the manifest's references resolve).
            let attachmentsExportDir = tempDir.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachmentsExportDir, withIntermediateDirectories: true)
            for note in notes {
                for attachment in note.attachments {
                    let src = NotesStore.attachmentURL(for: attachment)
                    let dest = attachmentsExportDir.appendingPathComponent(attachment.storedName)
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
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

    static func importNotes() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "zip")!,
            .plainText,
        ]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if url.pathExtension.lowercased() == "zip" {
                importFromZip(url)
            } else {
                // Single .txt file
                let text = try String(contentsOf: url, encoding: .utf8)
                let title = url.deletingPathExtension().lastPathComponent
                let store = NotesStore.shared
                let note = store.addNote()
                store.update(id: note.id) {
                    $0.title = title
                    $0.text = text
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private static func importFromZip(_ url: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Unzip using ditto
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", url.path, tempDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = "Could not extract zip file."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }

            // Find all .txt files recursively
            let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
            var imported = 0

            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension.lowercased() == "txt" else { continue }
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                // Strip numbering prefix like "1 - " from export filenames
                var title = fileURL.deletingPathExtension().lastPathComponent
                if let range = title.range(of: #"^\d+\s*-\s*"#, options: .regularExpression) {
                    title = String(title[range.upperBound...])
                }

                let store = NotesStore.shared
                let note = store.addNote()
                store.update(id: note.id) {
                    $0.title = title.isEmpty ? "Untitled" : title
                    $0.text = text
                }
                imported += 1
            }

            if imported > 0 {
                NotesStore.shared.selectedID = NotesStore.shared.notes.last?.id
            }

            try? FileManager.default.removeItem(at: tempDir)

        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    @MainActor
    static func attachToSelectedNote() {
        guard let id = NotesStore.shared.selectedID else {
            NSSound.beep()
            return
        }
        AttachmentImporter.openPicker(targetNoteID: id)
    }

    // Send a standard editing action through the responder chain so it reaches
    // the currently focused NSTextView regardless of which view is hosting it.
    static func sendEditAction(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
