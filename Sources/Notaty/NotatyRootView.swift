import SwiftUI

struct NotatyRootView: View {
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        VStack(spacing: 0) {
            TabBar(store: store)
            Divider()
            if let id = store.selectedID, store.notes.contains(where: { $0.id == id }) {
                NoteView(noteID: id)
            } else {
                Color.clear
            }
        }
    }
}

private struct TabBar: View {
    @ObservedObject var store: NotesStore

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.notes) { note in
                        TabButton(note: note, store: store)
                    }
                }
                .padding(.horizontal, 6)
            }
            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")

            HamburgerButton()
                .frame(width: 24, height: 22)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 4)
    }
}

// NSViewRepresentable so the popup can anchor to a real NSView and we can
// clone NSTextView's own contextual Edit menu (with its dynamic titles and
// AppKit-provided Find/Spelling/Substitutions/Transformations/Speech submenus).
private struct HamburgerButton: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: "More options"
        )
        button.contentTintColor = .labelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.handleClick(_:))
        button.focusRingType = .none
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    final class Coordinator: NSObject {
        @objc func handleClick(_ sender: NSButton) {
            NotatyMenuBuilder.presentHamburgerMenu(anchoredTo: sender)
        }
    }
}

private struct TabButton: View {
    let note: Note
    @ObservedObject var store: NotesStore

    private var isActive: Bool { store.selectedID == note.id }
    private var label: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            if store.notes.count > 1 {
                Button(action: { confirmDelete() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 0.7 : 0.35)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minWidth: 60, maxWidth: 160)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture { store.select(note.id) }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "\"\(label)\" will be permanently removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.delete(id: note.id)
        }
    }
}
