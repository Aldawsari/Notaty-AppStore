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

    // O(1) id → index lookup, kept in sync with `notes` on every mutation.
    private var indexByID: [UUID: Int] = [:]

    private init() {
        load()
        // Debounce persistence so we don't JSON-encode + UserDefaults-write
        // on every single keystroke.
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
        notes.remove(at: index)
        rebuildIndex()
        if selectedID == id {
            selectedID = notes.first?.id
        }
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
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        } else if let legacyText = defaults.string(forKey: legacyTextKey) {
            notes = [Note(title: "Untitled", text: legacyText)]
            defaults.removeObject(forKey: legacyTextKey)
            save(notes)
        } else {
            notes = []
        }
        rebuildIndex()
        selectedID = notes.first?.id
    }

    private func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
    }

    private func save(_ value: [Note]) {
        // JSON encoding a few KB of notes takes long enough to feel on the
        // main thread if done every keystroke. Kick it to a background queue
        // once debounced.
        DispatchQueue.global(qos: .background).async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            UserDefaults.standard.set(data, forKey: Self.storageKeyStatic)
        }
    }

    // Static mirror so the background save closure doesn't capture `self`
    // and isn't affected by the singleton's lifecycle.
    private static let storageKeyStatic = "notes"
}
