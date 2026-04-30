# Notaty Menu Bar Drop-to-Attach — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users drop files onto Notaty's menu bar status icon. The window opens, a banner appears, and the user picks a destination note (any tab or ＋ for a new note). The file(s) attach to whatever is picked.

**Architecture:** A new `PendingAttachments` shared state holds the dropped URLs in memory. A custom `NSView` overlaid on the status bar button handles `NSDraggingDestination` calls; on drop, it stores the URLs in `PendingAttachments` and triggers `showWindow()`. A SwiftUI banner observes the state and disappears when the user picks a destination. Tab and ＋ click handlers consume the pending state and call the existing `AttachmentImporter.attach(urls:to:)` for the actual copy/persist.

**Tech Stack:** Swift, AppKit (NSView, NSDraggingDestination, NSStatusItem), SwiftUI, Combine, the existing `AttachmentImporter` and `NotesStore.addAttachments`.

**Spec:** `docs/superpowers/specs/2026-04-30-menubar-drop-design.md`

**Scope:** No automated tests (Notaty has no test target). Manual acceptance criteria walkthrough in the final task.

---

## File Structure

| Path | Change |
|---|---|
| `Sources/Notaty/PendingAttachments.swift` | **New.** ObservableObject state holder for in-flight drop URLs |
| `Sources/Notaty/StatusItemDropOverlay.swift` | **New.** NSView subclass that registers for `.fileURL` drags, overlaid on the menu bar button |
| `Sources/Notaty/MenuBarDropBanner.swift` | **New.** SwiftUI banner shown above the tab bar when there's a pending attachment |
| `Sources/Notaty/AppDelegate.swift` | Install the overlay during status item setup; clear pending on Esc and window-close |
| `Sources/Notaty/NotatyRootView.swift` | Insert `MenuBarDropBanner` above `TabBar`; intercept tab clicks and ＋ to consume pending |
| `CHANGELOG.md` | Append to existing Unreleased entry |

---

## Task 1: PendingAttachments state holder

**Files:**
- Create: `Sources/Notaty/PendingAttachments.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import Combine

/// In-memory state for drop-to-attach: holds the URLs that landed on the menu
/// bar icon until the user picks a destination note. The UI observes
/// `urls.isEmpty` to show/hide the banner.
final class PendingAttachments: ObservableObject {
    static let shared = PendingAttachments()

    @Published private(set) var urls: [URL] = []

    var isPending: Bool { !urls.isEmpty }

    /// Human-readable description for the banner: filename for one, count for many.
    var description: String {
        if urls.count == 1 { return urls[0].lastPathComponent }
        return "\(urls.count) files"
    }

    /// Replace the pending list. Last-drop-wins semantics: a fresh drop while
    /// a banner is up replaces the previous URLs.
    func set(_ newURLs: [URL]) {
        urls = newURLs
    }

    /// Atomically take the URLs and clear the state. Returns the URLs the
    /// caller should attach.
    func consume() -> [URL] {
        let out = urls
        urls = []
        return out
    }

    /// Discard pending without attaching. Used for Esc / banner ×.
    func clear() {
        urls = []
    }

    private init() {}
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/PendingAttachments.swift
git commit -m "feat: PendingAttachments state holder for drop-to-attach flow"
```

---

## Task 2: StatusItemDropOverlay (NSView with dragging destination)

**Files:**
- Create: `Sources/Notaty/StatusItemDropOverlay.swift`

This NSView is overlaid on the menu bar status item button. It registers for `.fileURL` drags and reports them via a callback. It returns `nil` from `hitTest(_:)` so mouse clicks pass through to the underlying button (preserving the existing click-to-toggle-window behavior).

- [ ] **Step 1: Create the file**

```swift
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
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/StatusItemDropOverlay.swift
git commit -m "feat: StatusItemDropOverlay NSView for menu bar drag handling"
```

---

## Task 3: Install the overlay on the status item button

**Files:**
- Modify: `Sources/Notaty/AppDelegate.swift`

Add an instance property holding the overlay, attach it during `applicationDidFinishLaunching` after the existing status item setup, and wire `onDrop` to populate `PendingAttachments` and call `toggleWindow`.

- [ ] **Step 1: Add the property**

Open `Sources/Notaty/AppDelegate.swift`. Find the existing instance properties block at the top of the class (around line 7–20, where `statusItem`, `outsideClickMonitor`, etc. live). Add:

```swift
    private var statusDropOverlay: StatusItemDropOverlay?
```

- [ ] **Step 2: Install the overlay after status item button setup**

Find this existing block in `applicationDidFinishLaunching` (around line 26–35):

```swift
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "Notaty"
            )
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
```

Add immediately after the closing `}` of the `if let button = statusItem.button` block, BEFORE the next blank line:

```swift
        installStatusDropOverlay()
```

- [ ] **Step 3: Add the `installStatusDropOverlay` method**

Add this method anywhere in the AppDelegate class (near the other private helpers like `installDismissMonitors`):

```swift
    private func installStatusDropOverlay() {
        guard let button = statusItem.button,
              let buttonSuperview = button.superview else { return }

        let overlay = StatusItemDropOverlay(frame: button.frame)
        overlay.autoresizingMask = [.width, .height]
        overlay.onDrop = { [weak self] urls in
            self?.handleStatusItemDrop(urls)
        }
        buttonSuperview.addSubview(overlay, positioned: .above, relativeTo: button)
        statusDropOverlay = overlay
    }

    private func handleStatusItemDrop(_ urls: [URL]) {
        PendingAttachments.shared.set(urls)
        // Reveal the window so the user can pick a destination note.
        if let window = windowController.window, !window.isVisible {
            toggleWindow()
        } else {
            // Already visible — bring to front so the banner is seen.
            NSApp.activate(ignoringOtherApps: true)
            windowController.window?.makeKeyAndOrderFront(nil)
        }
    }
```

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 5: Smoke test — drag-handling at the menu bar**

Run: `bash run-debug.sh`

Manual check:
- The menu bar shows the Notaty icon as before
- Clicking the icon still toggles the window normally (no regression — overlay's hitTest returns nil for clicks)
- Drag a file from Finder over the icon → drag highlight should appear (the system shows it because the overlay accepts the drag)
- Release the file → Notaty window opens; nothing visible changes inside the window yet (banner hasn't been wired up — that's Task 4–5). The window simply appears.

If the icon doesn't accept drags (no highlight) OR clicks no longer open the window, STOP and report — the overlay's frame or position is wrong.

- [ ] **Step 6: Commit**

```bash
git add Sources/Notaty/AppDelegate.swift
git commit -m "feat: install StatusItemDropOverlay on menu bar button; populate PendingAttachments on drop"
```

---

## Task 4: MenuBarDropBanner SwiftUI view

**Files:**
- Create: `Sources/Notaty/MenuBarDropBanner.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

/// Sticky banner shown at the top of the note window when the user has dropped
/// a file on the menu bar icon and hasn't yet picked a destination note.
struct MenuBarDropBanner: View {
    let description: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Attaching \(description)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text("Click a tab to choose, or ＋ for a new note")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel attaching")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.18))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/MenuBarDropBanner.swift
git commit -m "feat: MenuBarDropBanner SwiftUI view"
```

---

## Task 5: Insert banner in NotatyRootView; intercept tab and ＋ clicks

**Files:**
- Modify: `Sources/Notaty/NotatyRootView.swift`

This is the wiring task — the banner observes `PendingAttachments.shared`, and tab clicks / the ＋ button consume the pending URLs after triggering their existing actions.

- [ ] **Step 1: Add PendingAttachments observation to NotatyRootView**

Open `Sources/Notaty/NotatyRootView.swift`. Find the top of the `NotatyRootView` struct:

```swift
struct NotatyRootView: View {
    @ObservedObject private var store = NotesStore.shared

    var body: some View {
```

Replace with:

```swift
struct NotatyRootView: View {
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var pending = PendingAttachments.shared

    var body: some View {
```

- [ ] **Step 2: Insert the banner above the TabBar**

In the same file, find the `var body: some View { VStack(spacing: 0) { TabBar(store: store) ... } }` block. Replace just the `VStack` content's beginning to insert the banner. Find:

```swift
    var body: some View {
        VStack(spacing: 0) {
            TabBar(store: store)
            Divider()
                .opacity(0.5)
```

Replace with:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if pending.isPending {
                MenuBarDropBanner(
                    description: pending.description,
                    onCancel: { pending.clear() }
                )
            }
            TabBar(store: store)
            Divider()
                .opacity(0.5)
```

- [ ] **Step 3: Find the TabBar struct and locate the ＋ Button**

Locate the `private struct TabBar: View` (in the same file). Find the `+` button block (the one with `Image(systemName: "plus")` and action `{ store.addNote() }`).

Currently it looks like:

```swift
            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")
```

Replace the `Button(action: ...)` with:

```swift
            Button(action: handleNewNote) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")
```

- [ ] **Step 4: Add the `handleNewNote` helper to TabBar**

In the `TabBar` struct, add this method (near the existing computed properties / helpers):

```swift
    /// Creates a new note. If there are pending attachments from a menu bar
    /// drop, attaches them to the new note.
    private func handleNewNote() {
        let new = store.addNote()
        let pending = PendingAttachments.shared.consume()
        if !pending.isEmpty {
            // Defer one runloop tick so the new note is fully registered in
            // NotesStore.indexByID before addAttachments is called.
            DispatchQueue.main.async {
                AttachmentImporter.attach(urls: pending, to: new.id)
            }
        }
    }
```

- [ ] **Step 5: Find the TabStrip / TabButton tab-click handler**

Tab clicks happen in `TabButton` (also defined in `NotatyRootView.swift`). Locate that struct and find where the tap action sets `store.selectedID`. The exact code is:

```swift
            .onTapGesture {
                store.selectedID = note.id
            }
```

(or similar — read the file to confirm; the tap may be on a `Rectangle()` or the container).

Replace with:

```swift
            .onTapGesture {
                store.selectedID = note.id
                let pending = PendingAttachments.shared.consume()
                if !pending.isEmpty {
                    DispatchQueue.main.async {
                        AttachmentImporter.attach(urls: pending, to: note.id)
                    }
                }
            }
```

If the file has a different tap pattern (e.g., a `Button` instead of `.onTapGesture`), wrap the existing action in the same way: do the existing `selectedID` assignment, then consume + attach.

- [ ] **Step 6: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 7: Smoke test — full drop-to-attach flow**

Run: `bash run-debug.sh`

Manual check:
- Drag a PNG from Finder over the menu bar icon → drag highlight visible
- Release → window opens, banner shows at the top: "Attaching screenshot.png — click a tab to choose, or ＋ for a new note"
- Click an existing tab → file attaches as a chip in that note → banner disappears
- Drop again → click ＋ → new note created → file attaches → banner disappears
- Drop again → click banner's × → banner disappears, no chip created
- Drop a Safari URL (drag the address bar icon to the menu bar icon) → ignored, no banner

If any of these fails, STOP and report.

- [ ] **Step 8: Commit**

```bash
git add Sources/Notaty/NotatyRootView.swift
git commit -m "feat: drop banner + tab/＋ click consume PendingAttachments"
```

---

## Task 6: Cancel pending on Esc and window close

**Files:**
- Modify: `Sources/Notaty/AppDelegate.swift`

The existing local Esc monitor hides the window when Esc is pressed inside it. We add `PendingAttachments.shared.clear()` to that path. We also clear pending on window-close.

- [ ] **Step 1: Update the Esc handler**

Open `Sources/Notaty/AppDelegate.swift`. Find this existing block (around line 249–255):

```swift
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && event.window === self?.windowController.window {
                self?.hideWindow()
                return nil
            }
            return event
        }
```

Replace with:

```swift
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && event.window === self?.windowController.window {
                PendingAttachments.shared.clear()
                self?.hideWindow()
                return nil
            }
            return event
        }
```

(Clear pending BEFORE hiding the window so a quick window re-show doesn't briefly flash the banner.)

- [ ] **Step 2: Hook window-close to clear pending**

The window can be closed via the red traffic-light. We need to clear pending in that path too. The cleanest hook is `NSWindowDelegate.windowWillClose(_:)` or observing `NSWindow.willCloseNotification`.

In `applicationDidFinishLaunching` of `AppDelegate`, near the existing setup, add:

```swift
        // Clear any pending menu-bar drop when the window closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: windowController.window,
            queue: .main
        ) { _ in
            PendingAttachments.shared.clear()
        }
```

- [ ] **Step 3: Also clear pending in `hideWindow`**

Find the existing `hideWindow()` method (around line 213). Add at the very top of the method:

```swift
    private func hideWindow() {
        PendingAttachments.shared.clear()
        // ...existing body unchanged
```

This catches dismiss-on-outside-click paths so the banner doesn't reappear next time the user opens the window.

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 5: Smoke test — cancel paths**

Run: `bash run-debug.sh`

Manual check:
- Drop a file on menu bar → banner shows. Press Esc → banner disappears, window hides. Reopen window → banner is NOT shown.
- Drop a file → banner shows. Click outside the window → window auto-hides. Reopen → banner is NOT shown (cleared by hideWindow).
- Drop a file → banner shows. Click red close button → window closes. Reopen → banner is NOT shown.

- [ ] **Step 6: Commit**

```bash
git add Sources/Notaty/AppDelegate.swift
git commit -m "feat: clear PendingAttachments on Esc, window close, and outside-click hide"
```

---

## Task 7: Full acceptance smoke test

This task has no code; it's a manual verification pass against the spec's 12 acceptance criteria.

- [ ] **Step 1: Release build**

Run: `swift build -c release`
Expected: clean build.

- [ ] **Step 2: Production .app**

Run:
```bash
rm -rf dist/Notaty-1.0.app && bash build.sh
open dist/Notaty-1.0.app
```

- [ ] **Step 3: Walk the spec's 12 acceptance criteria**

From `docs/superpowers/specs/2026-04-30-menubar-drop-design.md` § Acceptance criteria:

1. Drag a single PNG over menu bar icon → drop indicator visible during hover
2. Release → main window opens (or comes to front)
3. Banner appears: "Attaching screenshot.png — click a tab to choose, or ＋ for a new note"
4. Click any existing tab → file attaches as chip in that note → banner disappears
5. Repeat → click ＋ → new note created → file attaches → banner disappears
6. Drop, then Esc → banner disappears, no file attached, no orphan in `~/Library/Application Support/Notaty/attachments/`
7. Drop, then click banner's × → same as Esc
8. Drop multiple files → banner says count → click a tab → all files attach
9. Drop while no notes exist (delete all notes first) → banner shows, only ＋ creates a note + attaches
10. Drag a non-file URL (e.g. drag Safari's address-bar icon) over the menu bar icon → ignored, no banner
11. Drop file A, then drop file B before clicking → banner updates to file B; A is dropped
12. `swift build -c release` and `bash build.sh` succeed (Steps 1-2 above)

If all 12 pass, this task is done. If any fails, the relevant earlier task has a bug.

---

## Task 8: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

The Unreleased section already has an entry for the existing attachments feature. Append the menu-bar-drop functionality to that same paragraph (so the user sees one cohesive line about attachments).

- [ ] **Step 1: Update the Unreleased entry**

Open `CHANGELOG.md`. Find the existing Unreleased entry (added during the attachments work):

```markdown
## Unreleased

- File attachments on text notes. Click the new paperclip in the tab bar (or press ⌥⌘A) to attach files; you can also drag-drop from Finder onto a note, or paste a copied file with ⌘V. Each attachment shows as a chip below the note title with a thumbnail, name, and size. Click a chip to select it, press Space to preview with Quick Look, double-click to open in the default app. Drag a chip back to Finder to copy it out. Attachments survive launches and are included in zip export/import.
```

Replace with:

```markdown
## Unreleased

- File attachments on text notes. Attach files by: clicking the new paperclip in the tab bar, pressing ⌥⌘A, dragging from Finder onto a note, pasting a copied file with ⌘V, or **dropping files onto the Notaty menu bar icon** (window opens with a banner — click any tab or ＋ to choose the destination note). Each attachment shows as a chip below the note title with a thumbnail, name, and size. Click a chip to select it, press Space to preview with Quick Look, double-click to open in the default app. Drag a chip back to Finder to copy it out. Attachments survive launches and are included in zip export/import.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG note for menu bar drop-to-attach"
```

---

## Self-review — coverage against the spec

| Spec section | Covered by |
|---|---|
| State (PendingAttachments) | Task 1 |
| Status item drop handling (overlay NSView) | Task 2 (the view) + Task 3 (installation + onDrop wiring) |
| Banner UI | Task 4 (view) + Task 5 (insertion + observation) |
| Tab click consumes pending | Task 5 Step 5 |
| ＋ click consumes pending | Task 5 Steps 3–4 |
| Banner × cancels | Task 4 (button calls onCancel) + Task 5 (NotatyRootView wires onCancel to `pending.clear()`) |
| Esc cancels pending + hides window | Task 6 Step 1 |
| Window close clears pending | Task 6 Step 2 |
| Outside-click-hide also clears pending | Task 6 Step 3 |
| Last-drop-wins | Task 1 (`set` replaces; `consume` clears) — verified in Task 7 Step 3.11 |
| Multi-file drop | Task 1 description handles count; Task 5 attaches all — verified in Task 7 Step 3.8 |
| Non-file URL ignored | Task 2 (`hasFileURLs` guard returns []) — verified in Task 7 Step 3.10 |
| Acceptance criteria 1–12 | Task 7 |
| CHANGELOG | Task 8 |

No spec section is uncovered. No placeholders. Type/method names consistent (`PendingAttachments.shared`, `set`, `consume`, `clear`, `isPending`, `description`).

---

**End of plan.**
