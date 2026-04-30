import SwiftUI
import AppKit

struct AttachmentStripView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    /// Currently-selected chips. Plain click → just this one. Shift+click →
    /// range from the anchor to the clicked chip. Cmd+click → toggle one.
    @State private var selectedIDs: Set<UUID> = []
    /// The "anchor" — the last chip clicked without shift. Range select
    /// extends from this anchor to the shift-clicked chip.
    @State private var anchorID: UUID?

    private let preview = AttachmentPreviewCoordinator.shared

    private var attachments: [Attachment] {
        store.note(for: noteID)?.attachments ?? []
    }

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            stripContent
                .background(SpaceKeyMonitor(isEnabled: !selectedIDs.isEmpty) { handleSpacebar() })
        }
    }

    private var stripContent: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentChipView(
                    attachment: attachment,
                    isSelected: selectedIDs.contains(attachment.id),
                    onSelect: {
                        handleClick(on: attachment.id)
                        // Move first responder away from the text editor so the
                        // spacebar key event reaches our SpaceKeyMonitor instead
                        // of the text view (where it would type a space).
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    },
                    onOpen: {
                        NSWorkspace.shared.open(NotesStore.attachmentURL(for: attachment))
                    },
                    onRemove: {
                        selectedIDs.remove(attachment.id)
                        if anchorID == attachment.id { anchorID = nil }
                        store.removeAttachment(attachment.id, from: noteID)
                    }
                )
                .onDrag {
                    // Register the URL itself (not the file's contents) so
                    // internal drop targets like other tabs receive the
                    // original path. NSItemProvider(contentsOf:) would
                    // expose a temp-file copy instead, breaking our internal
                    // "move attachment between notes" detection by storedName.
                    let url = NotesStore.attachmentURL(for: attachment)
                    let provider = NSItemProvider(object: url as NSURL)
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

    private func handleClick(on id: UUID) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = anchorID {
            extendSelection(from: anchor, to: id)
            // Anchor stays put — shift+click extends from the same anchor on
            // each subsequent shift+click (Finder behavior).
        } else if modifiers.contains(.command) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
            anchorID = id
        } else {
            selectedIDs = [id]
            anchorID = id
        }
    }

    private func extendSelection(from anchor: UUID, to id: UUID) {
        guard let anchorIdx = attachments.firstIndex(where: { $0.id == anchor }),
              let endIdx = attachments.firstIndex(where: { $0.id == id }) else {
            // Anchor or target not in current list — fall back to single-select.
            selectedIDs = [id]
            anchorID = id
            return
        }
        let lo = min(anchorIdx, endIdx)
        let hi = max(anchorIdx, endIdx)
        selectedIDs = Set(attachments[lo...hi].map(\.id))
    }

    private func handleSpacebar() {
        let selected = attachments.filter { selectedIDs.contains($0.id) }
        guard let first = selected.first else { return }
        preview.show(attachments: selected, startAt: first.id)
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

/// Installs an NSEvent local monitor for the spacebar key. Fires `onSpace`
/// only when (a) `isEnabled` is true and (b) the current first responder is
/// NOT an NSText (so the user can still type spaces in the body editor).
/// Returns nil from the monitor (event consumed) when both conditions hold.
private struct SpaceKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onSpace: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(onSpace: onSpace)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onSpace = onSpace
    }

    func makeCoordinator() -> Coordinator { Coordinator(isEnabled: isEnabled) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onSpace: () -> Void = {}
        private var monitor: Any?

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        func install(onSpace: @escaping () -> Void) {
            self.onSpace = onSpace
            // 49 = kVK_Space
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.isEnabled else { return event }
                guard event.keyCode == 49 else { return event }
                // Defer to text-input first responders so spaces still type.
                if let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSText || responder.isKind(of: NSText.self) {
                    return event
                }
                self.onSpace()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            uninstall()
        }
    }
}
