import AppKit
import SwiftUI

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let directionMode: NoteDirection

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.usesFindBar = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // The Coordinator is created once by SwiftUI and reused across updates.
        // Re-point it at the CURRENT binding every update so that after a tab
        // switch the delegate writes to the newly-selected note, not the one
        // whose binding was captured when makeCoordinator first ran.
        context.coordinator.text = $text

        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        applyDirection(to: textView)
    }

    private func applyDirection(to textView: NSTextView) {
        let direction = Self.resolveDirection(mode: directionMode, text: text)
        if textView.baseWritingDirection != direction {
            textView.baseWritingDirection = direction

            // Also tag every existing paragraph, otherwise already-typed runs
            // keep their old direction and only new paragraphs flip.
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
                let base = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
                let mutable = (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                mutable.baseWritingDirection = direction
                storage.addAttribute(.paragraphStyle, value: mutable, range: range)
            }
            storage.endEditing()
        }
    }

    static func resolveDirection(mode: NoteDirection, text: String) -> NSWritingDirection {
        switch mode {
        case .ltr: return .leftToRight
        case .rtl: return .rightToLeft
        case .auto: return detect(text)
        }
    }

    // First-strong directional-character heuristic. Returns .leftToRight if
    // no strong character is present so a fresh note starts with the system
    // default rather than arbitrary.
    static func detect(_ text: String) -> NSWritingDirection {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Arabic blocks (main, supplement, extended-A, presentation forms A/B)
            // + Hebrew + Thaana + NKo + Samaritan — everything in 0x0590–0x08FF
            // is RTL in Unicode's bidi categories.
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
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
