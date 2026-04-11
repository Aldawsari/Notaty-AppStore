import AppKit
import CoreGraphics

// NSPanel subclass that can become key so it receives keyboard events for
// Esc-to-cancel, and that accepts mouse events without stealing activation.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Per-display overlay. Macos window servers often mis-handle a single
// borderless window that spans displays (the overlay becomes invisible or
// non-interactive on the secondary display). Using one non-activating panel
// PER screen guarantees each display gets its own event-routing target.
//
// Each panel's view drives a SelectorView that computes its selection rect
// in its own screen-local space, then converts to global Cocoa before
// calling the completion handler.
final class ScreenRegionSelector: NSObject, NSWindowDelegate {
    private var panels: [NSPanel] = []
    private var completion: ((NSRect?) -> Void)?
    private var retainSelf: ScreenRegionSelector?
    private var finished = false

    static func begin(_ completion: @escaping (NSRect?) -> Void) {
        let selector = ScreenRegionSelector()
        selector.retainSelf = selector
        selector.show(completion: completion)
    }

    private func show(completion: @escaping (NSRect?) -> Void) {
        self.completion = completion

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(with: nil)
            return
        }

        for screen in screens {
            let panel = OverlayPanel(
                contentRect: NSRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.worksWhenModal = true
            panel.level = .screenSaver
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.delegate = self
            panel.setFrame(screen.frame, display: true)

            let view = SelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenOriginInGlobalCocoa = screen.frame.origin
            view.onSelection = { [weak self] globalRect in
                self?.finish(with: globalRect)
            }
            view.onCancel = { [weak self] in self?.finish(with: nil) }
            panel.contentView = view

            panel.orderFrontRegardless()
            panel.makeFirstResponder(view)
            panels.append(panel)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(with rect: NSRect?) {
        guard !finished else { return }
        finished = true
        let completion = self.completion
        self.completion = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        completion?(rect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.retainSelf = nil
        }
    }
}

private final class SelectorView: NSView {
    // Origin of this view's host screen in global Cocoa coordinates.
    var screenOriginInGlobalCocoa: NSPoint = .zero
    var onSelection: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
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
        currentRect = makeRect(from: start, to: current)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentRect = nil
            needsDisplay = true
        }
        guard let rect = currentRect, rect.size.width >= 3, rect.size.height >= 3 else {
            onCancel?()
            return
        }
        let globalRect = NSRect(
            x: screenOriginInGlobalCocoa.x + rect.origin.x,
            y: screenOriginInGlobalCocoa.y + rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
        onSelection?(globalRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // escape
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let rect = currentRect {
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func makeRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}

// Captures a global-Cocoa rect to a CGImage. Multi-display safe: picks the
// NSScreen that contains (or best-intersects) the rect, converts the rect
// into that display's local Quartz coordinates (top-left origin), and uses
// CGDisplayCreateImage against that display's CGDirectDisplayID.
enum ScreenCapture {
    static func capture(rect: NSRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }

        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.frame.contains(rect) })
            ?? screens.max(by: {
                $0.frame.intersection(rect).area < $1.frame.intersection(rect).area
            })
            ?? NSScreen.main
        guard let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }

        let screenFrame = screen.frame
        let xLocal = rect.origin.x - screenFrame.origin.x
        let yLocal = screenFrame.height - (rect.origin.y - screenFrame.origin.y) - rect.height
        let localRect = CGRect(
            x: xLocal,
            y: yLocal,
            width: rect.width,
            height: rect.height
        )

        return CGDisplayCreateImage(displayID, rect: localRect)
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
