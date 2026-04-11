import AppKit

// Full-screen overlay that lets the user drag a rectangle. Calls the
// completion handler with the selected rect in screen coordinates (Cocoa
// origin: bottom-left of the main display), or nil if the user cancelled.
final class ScreenRegionSelector: NSObject, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var completion: ((NSRect?) -> Void)?

    static func begin(_ completion: @escaping (NSRect?) -> Void) {
        let selector = ScreenRegionSelector()
        selector.retainSelf = selector
        selector.show(completion: completion)
    }

    // Self-retain so the selector lives until the user finishes.
    private var retainSelf: ScreenRegionSelector?

    private func show(completion: @escaping (NSRect?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = NSColor.black.withAlphaComponent(0.25)
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.delegate = self

            let view = SelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onSelection = { [weak self] rectInView in
                guard let self else { return }
                // Convert view-local rect to screen coordinates.
                let screenRect = NSRect(
                    x: screen.frame.origin.x + rectInView.origin.x,
                    y: screen.frame.origin.y + rectInView.origin.y,
                    width: rectInView.size.width,
                    height: rectInView.size.height
                )
                self.finish(with: screenRect)
            }
            view.onCancel = { [weak self] in self?.finish(with: nil) }

            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(with rect: NSRect?) {
        let completion = self.completion
        self.completion = nil
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        completion?(rect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.retainSelf = nil
        }
    }
}

private final class SelectorView: NSView {
    var onSelection: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPoint!, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = rect(from: start, to: current)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.size.width >= 3, rect.size.height >= 3 else {
            onCancel?()
            return
        }
        onSelection?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // escape
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let rect = currentRect {
            // Punch a transparent hole for the selection so the user sees
            // what will be captured.
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}

// Captures a screen-coordinate rect to a CGImage using CGWindowList.
// Returns nil if the rect is empty or capture fails.
enum ScreenCapture {
    static func capture(rect: NSRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }

        // CGWindowListCreateImage uses flipped (top-left) coordinates on the
        // primary display. Convert from Cocoa's bottom-left origin.
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.height
        let flipped = CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        return CGWindowListCreateImage(
            flipped,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }
}
