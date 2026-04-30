import AppKit

/// A transparent NSView placed over the menu bar status item button.
/// Receives drag-and-drop of file URLs and reports them via `onDrop`.
/// Mouse clicks fall through to the underlying button (overridden hitTest).
final class StatusItemDropOverlay: NSView {

    /// Called on a successful drop. Always invoked on the main thread.
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Mouse clicks pass through to the underlying status item button.
    // Drag events do NOT go through hitTest — they're delivered directly to
    // views registered via `registerForDraggedTypes`, regardless of hitTest.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else { return [] }
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasFileURLs(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = readFileURLs(sender), !urls.isEmpty else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.onDrop?(urls)
        }
        return true
    }

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        readFileURLs(sender)?.isEmpty == false
    }

    private func readFileURLs(_ sender: NSDraggingInfo) -> [URL]? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
