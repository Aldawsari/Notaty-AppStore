import SwiftUI

struct NotatyRootView: View {
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
        VStack(spacing: 0) {
            TabBar(store: store)
            Divider()
                .opacity(0.5)

            Group {
                if let id = store.selectedID, store.notes.contains(where: { $0.id == id }) {
                    NoteView(noteID: id)
                        .id(id)
                } else {
                    Color.clear
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct TabBar: View {
    @ObservedObject var store: NotesStore

    var body: some View {
        HStack(spacing: 0) {
            TabStrip(store: store)
                .frame(maxWidth: .infinity)

            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")

            Button(action: { (NSApp.delegate as? AppDelegate)?.newVoiceNote() }) {
                Image(systemName: "mic")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New voice note (⇧⌘N)")

            Button(action: { (NSApp.delegate as? AppDelegate)?.startOCRCapture() }) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("Scan text from screen")

            HamburgerButton()
                .frame(width: 24, height: 22)
                .padding(.trailing, 10)
        }
        .padding(.vertical, 6)
        .padding(.leading, 4)
    }
}

// Safari-style tab layout: tabs share the available width equally, each
// shrinking from a max of ~180px down to a min of ~72px. Past that minimum,
// the strip scrolls horizontally and the active tab auto-scrolls into view.
private struct TabStrip: View {
    @ObservedObject var store: NotesStore
    @State private var stripWidth: CGFloat = 0
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0

    private let minTabWidth: CGFloat = 72
    private let maxTabWidth: CGFloat = 180
    private let spacing: CGFloat = 4
    private let outerPadding: CGFloat = 6

    private var computedTabWidth: CGFloat {
        let count = max(1, store.notes.count)
        let usable = max(0, stripWidth - outerPadding * 2 - spacing * CGFloat(count - 1))
        let raw = usable / CGFloat(count)
        return min(max(raw, minTabWidth), maxTabWidth)
    }

    private var cellWidth: CGFloat { computedTabWidth + spacing }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(store.notes) { note in
                        let isDragging = draggingID == note.id
                        TabButton(note: note, store: store, isDragging: isDragging)
                            .frame(width: computedTabWidth)
                            .id(note.id)
                            .offset(x: isDragging ? dragOffset : 0)
                            .zIndex(isDragging ? 1 : 0)
                            .scaleEffect(isDragging ? 1.04 : 1.0)
                            .shadow(
                                color: isDragging ? Color.black.opacity(0.2) : .clear,
                                radius: isDragging ? 4 : 0,
                                y: isDragging ? 2 : 0
                            )
                            .gesture(
                                DragGesture(minimumDistance: 5)
                                    .onChanged { value in
                                        if draggingID == nil {
                                            draggingID = note.id
                                        }
                                        dragOffset = value.translation.width
                                        checkSwap(for: note.id)
                                    }
                                    .onEnded { _ in
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            dragOffset = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            draggingID = nil
                                        }
                                    }
                            )
                    }
                }
                .padding(.horizontal, outerPadding)
                .animation(.easeInOut(duration: 0.2), value: store.notes.map(\.id))
            }
            .onChange(of: store.selectedID) { id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { stripWidth = geo.size.width }
                    .onChange(of: geo.size.width) { w in stripWidth = w }
            }
        )
    }

    // When the dragged tab's center crosses into a neighbor's territory,
    // swap them in the array. The ForEach animation handles the visual slide.
    private func checkSwap(for id: UUID) {
        guard let currentIndex = store.notes.firstIndex(where: { $0.id == id }) else { return }
        let threshold = cellWidth * 0.5
        if dragOffset > threshold, currentIndex < store.notes.count - 1 {
            let neighbor = store.notes[currentIndex + 1]
            withAnimation(.easeInOut(duration: 0.2)) {
                store.moveNote(fromID: id, toID: neighbor.id)
            }
            dragOffset -= cellWidth
        } else if dragOffset < -threshold, currentIndex > 0 {
            let neighbor = store.notes[currentIndex - 1]
            withAnimation(.easeInOut(duration: 0.2)) {
                store.moveNote(fromID: id, toID: neighbor.id)
            }
            dragOffset += cellWidth
        }
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
    var isDragging: Bool = false

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
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .opacity(isDragging ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { store.select(note.id) }
    }

    private func confirmDelete() {
        // Skip the prompt for notes that were never really used: empty body
        // and either empty or default "Untitled" title. A brand-new tab the
        // user immediately closes shouldn't require a confirmation.
        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUntouched = trimmedText.isEmpty
            && (trimmedTitle.isEmpty || trimmedTitle == "Untitled")
        if isUntouched {
            store.delete(id: note.id)
            return
        }

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
