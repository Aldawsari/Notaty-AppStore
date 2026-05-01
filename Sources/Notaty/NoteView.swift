import SwiftUI
import AppKit

struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var recordingSession = RecordingSession.shared
    @ObservedObject private var settings = Settings.shared

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
                    // Apply RTL alignment to the title text only — keep the
                    // row's icon order fixed (paperclip + mic on the right)
                    // regardless of the note's detected language.
                    .environment(\.layoutDirection, layoutDirection)

                Button(action: { AttachmentImporter.openPicker(targetNoteID: noteID) }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Attach file (⌥⌘A)")

                if settings.voiceNotesEnabled {
                    Button(action: { RecordingSession.shared.start(in: noteID) }) {
                        Image(systemName: "mic")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("New voice note (⇧⌘N)")
                    .disabled(recordingSession.isActive)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            RecordingBanner(noteID: noteID)

            AttachmentStripView(noteID: noteID)

            NoteTextEditor(
                text: store.textBinding(for: noteID),
                directionMode: note?.direction ?? .auto,
                noteID: noteID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    @MainActor
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [noteID] in
            AttachmentImporter.attach(urls: urls, to: noteID)
        }
        return true
    }
}
