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

    private init() {
        load()
        // Persist on every change. Debounce not needed for a local string blob.
        $notes
            .dropFirst()
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
        selectedID = note.id
        return note
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = notes.first?.id
        }
    }

    func select(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func update(id: UUID, transform: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        transform(&notes[index])
    }

    // MARK: - Bindings

    func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.notes.first(where: { $0.id == id })?.title ?? ""
            },
            set: { [weak self] newValue in
                self?.update(id: id) { $0.title = newValue }
            }
        )
    }

    func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.notes.first(where: { $0.id == id })?.text ?? ""
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
            // Migrate the pre-1.2 single-note storage into the new model.
            notes = [Note(title: "Untitled", text: legacyText)]
            defaults.removeObject(forKey: legacyTextKey)
            save(notes)
        } else {
            notes = []
        }
        selectedID = notes.first?.id
    }

    private func save(_ value: [Note]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

