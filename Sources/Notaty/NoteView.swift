import SwiftUI

struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        VStack(spacing: 0) {
            TextField("Untitled", text: store.titleBinding(for: noteID))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            TextEditor(text: store.textBinding(for: noteID))
                .font(.system(size: 14))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
