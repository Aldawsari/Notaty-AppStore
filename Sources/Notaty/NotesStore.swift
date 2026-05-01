import Foundation
import Combine
import SwiftUI

final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published var notes: [Note] = []
    @Published var selectedID: UUID?

    private let storageKey = "notes"
    private let legacyTextKey = "noteText"
    private var cancellables = Set<AnyCancellable>()
    private var isLoading = false

    private var indexByID: [UUID: Int] = [:]

    // File-based backup in ~/Library/Application Support/Notaty/notes.json
    // so notes survive bundle-ID changes, plist deletions, and reinstalls.
    private static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Notaty", isDirectory: true)
    }()
    private static let backupURL: URL = {
        appSupportDir.appendingPathComponent("notes.json")
    }()
    static let audioDir: URL = {
        appSupportDir.appendingPathComponent("audio", isDirectory: true)
    }()
    static let attachmentsDir: URL = {
        appSupportDir.appendingPathComponent("attachments", isDirectory: true)
    }()

    private init() {
        ensureAppSupportDir()
        ensureAttachmentsDir()
        load()
        $notes
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] newNotes in
                guard let self, !self.isLoading else { return }
                self.save(newNotes)
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func addNote() -> Note {
        let note = Note(title: "Untitled", text: "")
        notes.append(note)
        indexByID[note.id] = notes.count - 1
        selectedID = note.id
        return note
    }

    func delete(id: UUID) {
        guard let index = indexByID[id] else { return }
        let note = notes[index]
        // Cascade: move all attachment sidecar files to the Trash. Audio
        // files are now in attachments[] (post voice migration), so we no
        // longer need to special-case voice.
        for attachment in note.attachments {
            let url = Self.attachmentURL(for: attachment)
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        notes.remove(at: index)
        rebuildIndex()
        if selectedID == id {
            selectedID = notes.first?.id
        }
    }

    static func attachmentURL(for attachment: Attachment) -> URL {
        attachmentsDir.appendingPathComponent(attachment.storedName)
    }

    func moveNote(fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let fromIndex = indexByID[fromID],
              let toIndex = indexByID[toID]
        else { return }
        let note = notes.remove(at: fromIndex)
        notes.insert(note, at: toIndex)
        rebuildIndex()
    }

    func select(_ id: UUID) {
        guard indexByID[id] != nil else { return }
        selectedID = id
    }

    func setDirection(_ direction: NoteDirection, for id: UUID) {
        update(id: id) { $0.direction = direction }
    }

    func update(id: UUID, transform: (inout Note) -> Void) {
        guard let index = indexByID[id] else { return }
        transform(&notes[index])
    }

    /// Copy each source URL into `attachmentsDir` under a UUID-based name and
    /// append a corresponding `Attachment` to the note's array. Returns the
    /// number of files successfully attached. Files that fail to copy are
    /// silently skipped (the caller handles the error UI per file).
    @discardableResult
    func addAttachments(to noteID: UUID, from sourceURLs: [URL]) -> Int {
        guard !sourceURLs.isEmpty, indexByID[noteID] != nil else { return 0 }
        ensureAttachmentsDir()

        var added: [Attachment] = []
        for source in sourceURLs {
            let originalName = source.lastPathComponent
            let ext = source.pathExtension
            let storedName = ext.isEmpty
                ? UUID().uuidString
                : "\(UUID().uuidString).\(ext)"
            let dest = Self.attachmentsDir.appendingPathComponent(storedName)

            do {
                try FileManager.default.copyItem(at: source, to: dest)
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                added.append(Attachment(
                    originalName: originalName,
                    storedName: storedName,
                    byteSize: size
                ))
            } catch {
                NSLog("Notaty: failed to attach \(originalName): \(error)")
                continue
            }
        }

        guard !added.isEmpty else { return 0 }
        update(id: noteID) { $0.attachments.append(contentsOf: added) }
        return added.count
    }

    /// Move an attachment's metadata from one note to another. The on-disk
    /// sidecar file is unchanged — only the `[Attachment]` array entry
    /// transfers. Returns true on success, false if the source can't be
    /// found, source equals destination, or destination doesn't exist.
    @discardableResult
    func moveAttachment(storedName: String, to destinationNoteID: UUID) -> Bool {
        guard indexByID[destinationNoteID] != nil else { return false }
        guard let sourceIndex = notes.firstIndex(where: { note in
            note.attachments.contains(where: { $0.storedName == storedName })
        }) else { return false }
        let sourceNoteID = notes[sourceIndex].id
        if sourceNoteID == destinationNoteID { return false }
        guard let attachment = notes[sourceIndex].attachments.first(where: { $0.storedName == storedName }) else { return false }

        update(id: sourceNoteID) { $0.attachments.removeAll { $0.storedName == storedName } }
        update(id: destinationNoteID) { $0.attachments.append(attachment) }
        return true
    }

    /// Remove a single attachment from a note: moves the sidecar file to the
    /// Trash (so the user can restore it from Finder), then drops the
    /// metadata from the note's array.
    func removeAttachment(_ attachmentID: UUID, from noteID: UUID) {
        guard let note = self.note(for: noteID),
              let target = note.attachments.first(where: { $0.id == attachmentID })
        else { return }

        let url = Self.attachmentURL(for: target)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)

        update(id: noteID) {
            $0.attachments.removeAll { $0.id == attachmentID }
        }
    }

    func note(for id: UUID) -> Note? {
        guard let index = indexByID[id] else { return nil }
        return notes[index]
    }

    // MARK: - Bindings

    func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.note(for: id)?.title ?? ""
            },
            set: { [weak self] newValue in
                self?.update(id: id) { $0.title = newValue }
            }
        )
    }

    func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.note(for: id)?.text ?? ""
            },
            set: { [weak self] newValue in
                self?.update(id: id) { $0.text = newValue }
            }
        )
    }

    // MARK: - Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }

        let defaults = UserDefaults.standard

        // 1. Try UserDefaults (primary, backward-compatible).
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data),
           !decoded.isEmpty {
            notes = decoded
            // Sync the file backup in case it's stale.
            saveToFile(decoded)
            rebuildIndex()
            selectedID = notes.first?.id
            return
        }

        // 2. Try file backup (survives bundle-ID changes and plist resets).
        if let decoded = loadFromFile(), !decoded.isEmpty {
            notes = decoded
            // Re-populate UserDefaults from the backup.
            if let data = try? JSONEncoder().encode(decoded) {
                defaults.set(data, forKey: storageKey)
            }
            rebuildIndex()
            selectedID = notes.first?.id
            return
        }

        // 3. Try legacy single-note key (pre-1.2 migration).
        if let legacyText = defaults.string(forKey: legacyTextKey) {
            notes = [Note(title: "Untitled", text: legacyText)]
            defaults.removeObject(forKey: legacyTextKey)
            save(notes)
            rebuildIndex()
            selectedID = notes.first?.id
            return
        }

        // 4. Fresh start.
        notes = []
        rebuildIndex()
        selectedID = nil
    }

    private func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
    }

    private func save(_ value: [Note]) {
        DispatchQueue.global(qos: .background).async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            // Write to both UserDefaults and the file backup.
            UserDefaults.standard.set(data, forKey: "notes")
            try? data.write(to: Self.backupURL, options: .atomic)
        }
    }

    private func saveToFile(_ value: [Note]) {
        DispatchQueue.global(qos: .background).async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: Self.backupURL, options: .atomic)
        }
    }

    private func loadFromFile() -> [Note]? {
        guard let data = try? Data(contentsOf: Self.backupURL) else { return nil }
        return try? JSONDecoder().decode([Note].self, from: data)
    }

    private func ensureAppSupportDir() {
        try? FileManager.default.createDirectory(
            at: Self.appSupportDir,
            withIntermediateDirectories: true
        )
    }

    func ensureAttachmentsDir() {
        try? FileManager.default.createDirectory(
            at: Self.attachmentsDir,
            withIntermediateDirectories: true
        )
    }

    /// Sweep `attachmentsDir` and remove any file not referenced by any note's
    /// `attachments` array. Called once on launch.
    func cleanupOrphanedAttachmentFiles() {
        let referenced = Set(notes.flatMap { $0.attachments.map(\.storedName) })
        let dir = Self.attachmentsDir
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }

        for entry in entries where !referenced.contains(entry.lastPathComponent) {
            // Trash, don't permanently delete — orphan files might come from
            // a crash mid-attach; preserving them in Trash gives the user a
            // recovery path if the metadata gets corrupted later.
            try? FileManager.default.trashItem(at: entry, resultingItemURL: nil)
        }
    }

    /// Used by the importer after directly mutating `notes` to re-establish
    /// the ID→index map. Triggers persistence via the existing $notes sink.
    func rebuildIndexAfterImport() {
        rebuildIndex()
        // Touch `notes` so the debounced save sink fires.
        let snapshot = notes
        notes = snapshot
    }
}
