# Notaty — Menu Bar Drop-to-Attach (Design Spec)

**Date:** 2026-04-30
**Status:** Approved for implementation
**Branch:** `feature/attachments` (extends the existing attachments feature)

---

## Problem

Today, Notaty supports four ways to attach a file to a note: paperclip button, drag-drop on the note window, ⌘V paste, and the ⌥⌘A menu shortcut. All four require the note window to already be visible, with the target note already selected.

A common macOS pattern — drag a file onto an app's icon (Dock or menu bar) to open/act on it — is not yet supported. Users have to open Notaty, select the right note, then drag the file in. That's two clicks of preamble for what feels like one action.

## Goal

Let the user drop one or more files onto Notaty's menu bar status icon and pick the target note from the resulting open window. The drop is the *trigger*; the user retains *control over which note* receives the attachment.

## Out of scope

- Dropping URLs (web links) onto the icon — only file URLs, matching the existing attachments scope
- Dropping onto the Dock icon — Notaty is `LSUIElement = true` (no dock icon)
- Auto-pinning the window during the pending state (separate "pin" feature exists; orthogonal)
- Time-based timeout on the pending state — explicit dismiss only
- Persisting pending attachments across launches — pending is in-memory only

---

## UX flow

1. User drags one or more files from Finder over the Notaty menu bar icon
2. Icon visually indicates "drop will work" (highlight / dragging-over visual)
3. User releases — drop is accepted
4. Notaty's main window opens (or comes to front if hidden)
5. **A sticky banner appears at the top of the window** above the tab bar:

   - Single file: *"Attaching `screenshot.png` — click a tab to choose, or ＋ for a new note"*
   - Multiple files: *"Attaching 3 files — click a tab to choose, or ＋ for a new note"*
   - The banner has a small `×` to cancel

6. The dropped file(s) are held in a `PendingAttachments` state on AppDelegate
7. **The user picks the destination** by doing one of:

   - **Clicking any existing tab** → that note becomes selected, files attach to it, banner clears
   - **Clicking ＋ (new note)** → new note created, becomes selected, files attach to it, banner clears
   - **Pressing Esc** → pending state cleared, banner clears, files NOT attached, staged copies removed
   - **Clicking the banner's `×`** → same as Esc
   - **Closing the window** (red traffic light or window-close shortcut) → pending state cleared, banner clears

8. When the destination is picked, the `AttachmentImporter.attach(urls:to:)` flow runs (same code path as drag-drop on note window), so size warnings and copy-error alerts behave identically.

## State

A new singleton-ish state object owned by `AppDelegate`:

```swift
final class PendingAttachments {
    private(set) var urls: [URL] = []
    var isPending: Bool { !urls.isEmpty }
    var description: String {
        if urls.count == 1 { return urls[0].lastPathComponent }
        return "\(urls.count) files"
    }
    func set(_ urls: [URL]) { self.urls = urls }
    func consume() -> [URL] {
        let out = urls
        urls = []
        return out
    }
    func clear() { urls = [] }
}
```

`AppDelegate` exposes `@Published var pendingAttachments: PendingAttachments`. Banner observes it; banner shows iff `isPending == true`.

**Pending state lifecycle:**
- Set: status item drop handler calls `pendingAttachments.set(urls)`, AppDelegate calls `showWindow()`
- Consume: tab click or ＋ click triggers `let urls = pendingAttachments.consume(); AttachmentImporter.attach(urls: urls, to: noteID)`
- Clear: Esc, banner ×, or window close

## Status item drop handling

NSStatusItem's `button` is an `NSStatusBarButton` (the system creates it). To accept drags onto it, we need to:

- Register the button for `[.fileURL]` dragged types
- Hook the dragging-destination methods (`draggingEntered`, `draggingUpdated`, `prepareForDragOperation`, `performDragOperation`)

There are two viable AppKit techniques; the implementation plan picks one based on what compiles cleanly:

| Approach | How |
|---|---|
| **Subclass NSStatusBarButton via swizzling** | Override the dragging-destination methods on the system-provided button class through Objective-C method swizzling at app startup. Most invasive; AppKit-private surface area. |
| **Overlay an NSView on top of the button** | Add a transparent custom NSView as a subview of `statusItem.button?.window?.contentView`, sized and positioned to overlay the button's frame. The overlay handles drags; clicks pass through to the button below for normal status-item interaction. Less invasive; well-documented pattern. |

**Recommended:** the overlay approach. It avoids touching the system's button class, keeps drag handling in our code, and clicks for "open window" still flow to the original button.

## Banner UI

A new SwiftUI view, `MenuBarDropBanner`, inserted in `NotatyRootView` ABOVE the existing `TabBar`:

```swift
struct NotatyRootView: View {
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var pending = PendingAttachments.shared

    var body: some View {
        VStack(spacing: 0) {
            if pending.isPending {
                MenuBarDropBanner(
                    description: pending.description,
                    onCancel: { pending.clear() }
                )
            }
            TabBar(store: store)
            Divider().opacity(0.5)
            // ...existing content
        }
    }
}
```

`MenuBarDropBanner` visual:

- Background: `Color.accentColor.opacity(0.18)` (subtle blue tint)
- Text: 12pt medium weight, primary color
- Icon: SF Symbol `paperclip` on the left
- × button on the right to cancel
- Padding: vertical 8, horizontal 14
- Bottom border: 1px hairline

## Tab click and ＋ click interception

Both interactions must:
1. Check `pending.isPending` before doing their normal action
2. If pending: do their normal action (select tab / create note) AND attach the consumed URLs to the resulting note ID

Cleanest place: in `TabBar` and the existing `addNote()` flow. Two small modifications:

- The existing tab `Button(action: ...)` for selecting a note: after `store.selectedID = note.id`, check `pending.consume()` and if non-empty, call `AttachmentImporter.attach(urls: pendingURLs, to: note.id)`
- The existing ＋ button: after `let new = store.addNote()`, check `pending.consume()` and if non-empty, attach to `new.id`

This way the consume happens AFTER the destination note exists. The banner reactively disappears because `pending.isPending` becomes false.

## Cancel / dismiss

Three cancel paths converge on `pending.clear()`:

1. **Banner × button** → `pending.clear()` directly
2. **Esc** → existing Esc handler in AppDelegate calls `pending.clear()` (in addition to its current `hideWindow()` call)
3. **Window close (red traffic light)** → AppDelegate observes window-will-close notification; if pending, clear it

Note: Esc currently both hides the window and (now) clears pending. That's a single key for "I'm done with this." Acceptable conflation.

## Edge cases

- **Drop while window is already open with a note selected:** banner appears on top of the current note. User must explicitly click a tab (even the active one) to confirm. Active note is NOT auto-attached — the click is the explicit choice. (Avoids the "I dropped on the icon and immediately attached to whatever was active" surprise.)
- **Drop while no notes exist:** banner shows. Tab list is empty. Only ＋ does anything; Esc cancels.
- **Multi-file drop:** banner says "N files". All N attach to the chosen destination.
- **Second drop while banner already up:** previous pending replaced (last-drop-wins). Staged copies of the previous file(s) are removed before the new ones are staged.
- **Window minimized/hidden when drop happens:** showWindow() reveals it.
- **Drop a non-file URL** (e.g. http URL): drop is rejected; nothing happens.

---

## Files touched

| Path | Change |
|---|---|
| `Sources/Notaty/PendingAttachments.swift` | **New.** State holder + shared instance |
| `Sources/Notaty/StatusItemDropOverlay.swift` | **New.** NSView subclass that overlays the menu bar button and handles drags |
| `Sources/Notaty/MenuBarDropBanner.swift` | **New.** SwiftUI banner view |
| `Sources/Notaty/AppDelegate.swift` | Wire up the overlay on the status item; clear pending on Esc / window close |
| `Sources/Notaty/NotatyRootView.swift` | Insert `MenuBarDropBanner` above `TabBar`; intercept tab clicks and ＋ to consume pending |
| `CHANGELOG.md` | Add to Unreleased entry |

## Acceptance criteria

The feature is "done" when all of these pass on a debug build:

1. Drag a single PNG from Finder over the menu bar icon → drop indicator visible during hover.
2. Release the drop → Notaty's main window opens (or comes to front).
3. Banner appears at top of window: "Attaching screenshot.png — click a tab to choose, or ＋ for a new note."
4. Click any existing tab → file attaches as a chip in that note → banner disappears.
5. Repeat the drop → click ＋ instead → new note created → file attaches → banner disappears.
6. Drop, then press Esc → banner disappears, no file attached, no chip, no orphan files in `~/Library/Application Support/Notaty/attachments/`.
7. Drop, then click banner's × → same as Esc.
8. Drop multiple files at once → banner says count → click a tab → all files attach to that note.
9. Drop while no notes exist → banner shows, only ＋ creates a note + attaches.
10. Drop a non-file URL (a Safari link) → ignored; no banner, no window-open.
11. Drop a second file while banner is showing the first → banner updates to the second; first's staged copy is removed.
12. `swift build -c release` succeeds; `bash build.sh` produces a working `.app`.

## Risks

- **NSStatusBarButton drag handling is finicky.** The overlay approach is well-documented but the exact frame/positioning needs care so clicks still reach the button beneath. Implementation plan should test that clicking the icon (without dragging) still opens/closes the window normally.
- **Esc handler conflict.** Notaty's existing Esc handler already hides the window. Adding "clear pending" to it is fine but the order matters: clear pending first, then hide. Otherwise a hidden window with pending state lingers (banner on next show).
- **Pending state ordering on tab click.** The tab's existing onTapGesture sets `selectedID` — we must consume pending AFTER selectedID is set so the banner disappears for the right note. A quick `DispatchQueue.main.async { ... }` wrapper around the consume call ensures the SwiftUI render cycle has updated state before we attach.

---

## Out of scope, follow-ups

- Drag and drop **multiple times in sequence** (queue) — for v1, last-drop-wins. Multi-drop queue can be a follow-up.
- **Pin tab while dragging** so the user can position the cursor precisely — macOS provides this natively.
- **Per-file destinations** when multiple files are dropped — for v1, all N go to the chosen note. Could add a UI for "this file → note A, that file → note B" later.
