import Foundation

/// Two-phase migration:
///   v1 — convert legacy voice notes (`audioFilename` set) into regular notes
///        with the audio attached. Sets `isVoiceNote = true` on the new
///        attachment.
///   v2 — one-shot sweep for users on the unreleased build whose voice
///        attachments were created before `isVoiceNote` existed. Flips the
///        flag on attachments whose `originalName` matches the values
///        produced by v1 and `RecordingSession.stop()`.
///
/// Each phase has its own UserDefaults flag so neither re-runs.
enum VoiceMigration {
    private static let v1Key = "didMigrateVoiceToAttachments"
    private static let v2Key = "didMigrateVoiceNoteFlag"

    /// Historical originalName values that mark an in-app voice recording.
    /// Used by v2 to recognize attachments created before `isVoiceNote`
    /// existed. Intentionally NOT shared with v1's attachment-creation
    /// default — these are immutable recognition patterns; adding a future
    /// naming convention belongs in a v3 sweep, not here.
    private static let v2RecognizedOriginalNames: Set<String> = [
        "Recording.m4a",
        "Voice Note.m4a",
    ]

    static func runIfNeeded() {
        runV1IfNeeded()
        runV2IfNeeded()
    }

    private static func runV1IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: v1Key) else { return }
        defer { UserDefaults.standard.set(true, forKey: v1Key) }

        let store = NotesStore.shared
        var migratedCount = 0

        for note in store.notes {
            guard let filename = note.audioFilename else { continue }
            let oldURL = NotesStore.audioDir.appendingPathComponent(filename)
            let newURL = NotesStore.attachmentsDir.appendingPathComponent(filename)
            store.ensureAttachmentsDir()

            if FileManager.default.fileExists(atPath: oldURL.path) {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.removeItem(at: newURL)
                }
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                } catch {
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
                    byteSize: size,
                    isVoiceNote: true
                )
                store.update(id: note.id) {
                    $0.attachments.append(attachment)
                    $0.audioFilename = nil
                }
                migratedCount += 1
            } else {
                // Audio file is missing on disk — clear the dangling reference.
                store.update(id: note.id) { $0.audioFilename = nil }
            }
        }

        if migratedCount > 0 {
            NSLog("VoiceMigration v1: converted \(migratedCount) voice notes to regular notes with audio attachments")
        }

        // Anything v1 just produced already has isVoiceNote = true, so skip v2
        // for first-launch users.
        UserDefaults.standard.set(true, forKey: v2Key)
    }

    private static func runV2IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: v2Key) else { return }
        defer { UserDefaults.standard.set(true, forKey: v2Key) }

        let store = NotesStore.shared
        var flippedCount = 0

        for note in store.notes {
            var newAttachments = note.attachments
            var changed = false
            for idx in newAttachments.indices {
                let att = newAttachments[idx]
                if !att.isVoiceNote
                    && Self.v2RecognizedOriginalNames.contains(att.originalName) {
                    newAttachments[idx].isVoiceNote = true
                    changed = true
                    flippedCount += 1
                }
            }
            if changed {
                store.update(id: note.id) { $0.attachments = newAttachments }
            }
        }

        if flippedCount > 0 {
            NSLog("VoiceMigration v2: flipped \(flippedCount) attachments to isVoiceNote=true")
        }
    }
}
