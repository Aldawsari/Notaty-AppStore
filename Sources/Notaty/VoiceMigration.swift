import Foundation

/// One-time migration: convert voice notes (`audioFilename` set) into regular
/// notes with the audio file attached as an `Attachment`. Runs silently on
/// app launch the first time after the upgrade. Tracked by a UserDefaults
/// flag so it never re-runs.
enum VoiceMigration {
    private static let migrationKey = "didMigrateVoiceToAttachments"

    /// Call once on launch, after `NotesStore.shared` has loaded.
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let store = NotesStore.shared
        var migratedCount = 0

        for note in store.notes {
            guard let filename = note.audioFilename else { continue }
            let oldURL = NotesStore.audioDir.appendingPathComponent(filename)
            let newURL = NotesStore.attachmentsDir.appendingPathComponent(filename)

            // Make sure the destination dir exists.
            store.ensureAttachmentsDir()

            if FileManager.default.fileExists(atPath: oldURL.path) {
                // Move the file. moveItem fails if dest exists; remove it first.
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.removeItem(at: newURL)
                }
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                } catch {
                    // Fallback: copy then delete the source.
                    if (try? FileManager.default.copyItem(at: oldURL, to: newURL)) != nil {
                        try? FileManager.default.removeItem(at: oldURL)
                    } else {
                        NSLog("VoiceMigration: failed to relocate \(filename): \(error)")
                        continue
                    }
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: newURL.path)[.size] as? Int64) ?? 0
                let attachment = Attachment(
                    originalName: "Voice Note.m4a",
                    storedName: filename,
                    byteSize: size
                )
                store.update(id: note.id) {
                    $0.attachments.append(attachment)
                    $0.audioFilename = nil
                }
                migratedCount += 1
            } else {
                // Audio file is missing on disk. Just clear the dangling reference.
                store.update(id: note.id) { $0.audioFilename = nil }
            }
        }

        if migratedCount > 0 {
            NSLog("VoiceMigration: converted \(migratedCount) voice notes to regular notes with audio attachments")
        }
    }
}
