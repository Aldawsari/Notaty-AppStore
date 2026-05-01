import SwiftUI
import AppKit

/// Strip section that lists all in-app voice recordings for a note as
/// stacked `VoiceNoteCardView`s. Hidden entirely when the active note has
/// no voice notes. Sits between `RecordingBanner` and `AttachmentStripView`
/// inside `NoteView`.
struct VoiceNoteStripView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    private var voiceNotes: [Attachment] {
        store.note(for: noteID)?.attachments.filter { $0.isVoiceNote } ?? []
    }

    var body: some View {
        if voiceNotes.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                ForEach(Array(voiceNotes.enumerated()), id: \.element.id) { pair in
                    VoiceNoteCardView(
                        attachment: pair.element,
                        noteID: noteID,
                        index: pair.offset
                    )
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }
}
