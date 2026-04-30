import AppKit
import SwiftUI

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let directionMode: NoteDirection
    var noteID: UUID? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build a scrollable text view backed by NotatyTextView (so paste
        // can intercept file-URL pastes and divert them to attachments).
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textView = NotatyTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.usesFindBar = true

        context.coordinator.textView = textView
        context.coordinator.directionMode = directionMode
        textView.attachmentTargetNoteID = noteID
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Rebind the coordinator to the current struct's state every update.
        context.coordinator.text = $text
        let directionModeChanged = context.coordinator.directionMode != directionMode
        context.coordinator.directionMode = directionMode

        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView
        if let nty = textView as? NotatyTextView {
            nty.attachmentTargetNoteID = noteID
        }

        var contentReplaced = false
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            contentReplaced = true
        }

        // Only reapply direction when something actually changed that could
        // affect it. Without this check every SwiftUI re-render (which fires
        // on every keystroke via the text binding) re-enumerates the entire
        // text storage and invalidates the whole layout.
        if directionModeChanged || contentReplaced {
            context.coordinator.applyDirection(forceRelayout: true)
        }
    }

    static func resolveDirection(mode: NoteDirection, text: String) -> NSWritingDirection {
        switch mode {
        case .ltr: return .leftToRight
        case .rtl: return .rightToLeft
        case .auto: return detect(text)
        }
    }

    // First-strong directional-character heuristic.
    static func detect(_ text: String) -> NSWritingDirection {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x0590...0x08FF).contains(v)
                || (0xFB1D...0xFDFF).contains(v)
                || (0xFE70...0xFEFF).contains(v) {
                return .rightToLeft
            }
            if (0x0041...0x005A).contains(v)
                || (0x0061...0x007A).contains(v)
                || (0x00C0...0x024F).contains(v) {
                return .leftToRight
            }
        }
        return .leftToRight
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        var directionMode: NoteDirection = .auto
        private var appliedDirection: NSWritingDirection?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            // Check whether this edit flipped the detected direction. If not,
            // skip the expensive relayout pass — the hot path of ordinary
            // typing now does almost no extra work.
            applyDirection(forceRelayout: false)
        }

        func applyDirection(forceRelayout: Bool) {
            guard let textView else { return }
            let source = textView.string
            let direction = NoteTextEditor.resolveDirection(mode: directionMode, text: source)

            if !forceRelayout && direction == appliedDirection {
                return
            }
            appliedDirection = direction

            let alignment: NSTextAlignment = (direction == .rightToLeft) ? .right : .left

            textView.baseWritingDirection = direction
            textView.alignment = alignment

            let para = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            para.baseWritingDirection = direction
            para.alignment = alignment
            textView.defaultParagraphStyle = para

            var attrs = textView.typingAttributes
            attrs[.paragraphStyle] = para
            textView.typingAttributes = attrs

            if let storage = textView.textStorage {
                let length = storage.length
                if length > 0 {
                    let fullRange = NSRange(location: 0, length: length)
                    storage.beginEditing()
                    storage.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
                        let base = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
                        let mutable = (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                        mutable.baseWritingDirection = direction
                        mutable.alignment = alignment
                        storage.addAttribute(.paragraphStyle, value: mutable, range: range)
                    }
                    storage.endEditing()
                    textView.setBaseWritingDirection(direction, range: fullRange)
                }

                if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                    let fullRange = NSRange(location: 0, length: length)
                    layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                    layoutManager.ensureLayout(for: container)
                }
            }

            let currentSelection = textView.selectedRange()
            textView.setSelectedRange(currentSelection)
            textView.updateInsertionPointStateAndRestartTimer(true)

            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
                layoutManager.textContainerChangedGeometry(container)
            }

            textView.needsDisplay = true
        }
    }
}

/// NSTextView subclass that lets file-URL pastes flow to the attachment
/// importer instead of being inserted as text. Plain-text pastes fall
/// through to super and behave exactly as before.
final class NotatyTextView: NSTextView {

    /// Set externally — the note ID this view is editing.
    var attachmentTargetNoteID: UUID?

    override func paste(_ sender: Any?) {
        if let id = attachmentTargetNoteID,
           AttachmentImporter.attachFromPasteboard(NSPasteboard.general, to: id) {
            return
        }
        super.paste(sender)
    }
}
