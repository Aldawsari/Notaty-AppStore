import SwiftUI
import AppKit

struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    private var note: Note? {
        store.notes.first(where: { $0.id == noteID })
    }

    private var layoutDirection: LayoutDirection {
        let mode = note?.direction ?? .auto
        let text = note?.text ?? ""
        let direction = NoteTextEditor.resolveDirection(mode: mode, text: text)
        return direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Untitled", text: store.titleBinding(for: noteID))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .environment(\.layoutDirection, layoutDirection)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            NoteTextEditor(
                text: store.textBinding(for: noteID),
                directionMode: note?.direction ?? .auto
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
