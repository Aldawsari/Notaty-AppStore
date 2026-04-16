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

    private init() {
        ensureAppSupportDir()
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

    @discardableResult
    func addVoiceNote() -> Note {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        let timestamp = f.string(from: Date())
        let id = UUID()
        let note = Note(
            id: id,
            title: "ملاحظة صوتية \(timestamp)",
            text: "",
            type: .voice,
            audioFilename: "\(id.uuidString).m4a"
        )
        notes.append(note)
        indexByID[note.id] = notes.count - 1
        selectedID = note.id
        return note
    }

    func delete(id: UUID) {
        guard let index = indexByID[id] else { return }
        let note = notes[index]
        if note.type == .voice, let filename = note.audioFilename {
            let audioURL = Self.audioDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: audioURL)
        }
        notes.remove(at: index)
        rebuildIndex()
        if selectedID == id {
            selectedID = notes.first?.id
        }
    }

    static func audioURL(for note: Note) -> URL? {
        guard let filename = note.audioFilename else { return nil }
        return audioDir.appendingPathComponent(filename)
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

    func ensureAudioDir() {
        try? FileManager.default.createDirectory(
            at: Self.audioDir,
            withIntermediateDirectories: true
        )
    }
}
