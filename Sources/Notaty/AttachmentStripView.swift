import SwiftUI

struct AttachmentStripView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    /// Coordinator owned by the strip; passed down to chips so Quick Look has
    /// a single retained data source for the panel.
    private let preview = AttachmentPreviewCoordinator.shared

    private var attachments: [Attachment] {
        store.note(for: noteID)?.attachments ?? []
    }

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            stripContent
        }
    }

    private var stripContent: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentChipView(
                    attachment: attachment,
                    onRemove: { store.removeAttachment(attachment.id, from: noteID) },
                    onSingleClick: { preview.show(attachments: attachments, startAt: attachment.id) },
                    onDoubleClick: { NSWorkspace.shared.open(NotesStore.attachmentURL(for: attachment)) }
                )
                .onDrag {
                    let url = NotesStore.attachmentURL(for: attachment)
                    let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
                    provider.suggestedName = attachment.originalName
                    return provider
                }
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

/// Wraps children left-to-right, breaking to a new line when the next child
/// would overflow. SwiftUI has no built-in for this in macOS 13.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: proposal.width ?? x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
