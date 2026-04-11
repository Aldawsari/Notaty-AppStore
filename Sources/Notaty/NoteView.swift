import SwiftUI

struct NoteView: View {
    @AppStorage("noteText") private var noteText: String = ""

    var body: some View {
        TextEditor(text: $noteText)
            .font(.system(size: 14))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
