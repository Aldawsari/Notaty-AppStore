# Notaty — Pinned Window (Always-On-Top Toggle)

**Date:** 2026-04-30
**Status:** Approved for implementation
**Branch:** `feature/floating-window`

---

## Problem

Notaty's main window is a menu-bar-app window. By default it floats above other apps' windows (window level `.floating`) and stays visible across app switches (`hidesOnDeactivate = false`). However, the AppDelegate also installs a global mouse-down monitor that **dismisses the window on any click outside it** — useful for the typical "click status icon, jot a note, click away to dismiss" flow, frustrating when the user wants to keep the note visible while working in another app (e.g., copy text from Safari into a Notaty note that stays put).

There is no user-facing way to disable this auto-dismiss behavior today.

## Goal

Add a "Pin window" toggle that, when enabled, keeps the main window stuck open — the user is the only one who decides when to dismiss it (via the close button or Esc). Default is **off** (current behavior preserved).

The toggle lives in two equivalent places — a pin icon in the tab bar (always visible, one click to toggle) and a checkbox in Settings (canonical setting). Both reflect and update the same underlying state.

## Out of scope

- **Per-window pinning.** Notaty has one main window today; this isn't a multi-window app.
- **Pinning across reboots of the OS / sleep.** The window state is restored normally on next launch; pinning is a runtime preference, not a window-state attribute.
- **Pin to specific corner / edge** (sticky positioning) — separate feature.
- **Pin across all macOS Spaces** (`collectionBehavior = .canJoinAllSpaces`) — separate feature, may be relevant later.
- **Keyboard shortcut for the toggle** (e.g. ⌥⌘P) — easy to add later, not needed for v1.
- **Hamburger menu entry** for the toggle — pin icon + Settings is sufficient for v1.

---

## State

A new property on `Settings.shared`:

```swift
@Published var pinned: Bool {
    didSet { UserDefaults.standard.set(pinned, forKey: Self.pinnedKey) }
}
```

- UserDefaults key: `"windowPinned"`
- Default: `false` — preserves existing behavior for current users
- `@Published` so SwiftUI views observing `Settings.shared` re-render when the value flips

## UI — Pin icon in tab bar

A new SwiftUI `Button` in `TabBar` (`NotatyRootView.swift`), positioned **between the paperclip and the ＋ new-note button**:

| `pinned` state | SF Symbol | Foreground color | Tooltip |
|---|---|---|---|
| `false` | `pin` (outline) | `.secondary` | "Pin window on top" |
| `true` | `pin.fill` (filled) | `.accentColor` | "Unpin window" |

- Same `frame(width: 24, height: 22)` and `.buttonStyle(.plain)` as siblings
- Click action: `Settings.shared.pinned.toggle()`
- Always visible regardless of state — pinned and unpinned both show a clickable icon

## UI — Settings window toggle

A new toggle row added to `SettingsView.swift` in the existing **"Window"** section (around line 20–43, alongside the existing `defaultWindowSize` picker and `launchAtLogin` toggle). Place the new toggle directly below `launchAtLogin`:

```swift
Toggle(isOn: $settings.pinned) {
    Text("Keep window on top (pinned)")
}
```

Bound to `Settings.shared.pinned`. Flipping this checkbox updates the same state as clicking the tab bar icon — both views auto-update via the `@Published` property.

Bound to `Settings.shared.pinned`. Flipping this checkbox updates the same state as clicking the tab bar icon — both views auto-update via the `@Published` property.

## Behavior — AppDelegate

The dismiss-on-outside-click behavior is implemented today via `installDismissMonitors()` (called from somewhere on app/window lifecycle) which adds an `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` that calls `hideWindow()` on outside click.

**The pinned state must gate this monitor:**

- When `pinned == true`: monitor is **not active** (either uninstalled if currently installed, or never installed in the first place). Outside clicks do not hide the window.
- When `pinned == false`: monitor is active (current default behavior). Outside clicks hide the window.

**Implementation:** AppDelegate observes `Settings.shared.$pinned` via a Combine sink stored in a cancellable. On each value change:
- New value `true` → call `removeDismissMonitors()` if currently installed
- New value `false` → call `installDismissMonitors()` if currently visible and not already installed

Wire this in `applicationDidFinishLaunching` so the observation begins on launch and the initial state is honored.

## Behavior — what stays the same

- **Window level** stays `.floating` regardless of pinned state. The window has always floated above other apps' regular windows; pinning only affects the auto-hide-on-outside-click behavior.
- **Esc dismisses the window** in either pinned or unpinned state — Esc is the user's explicit dismiss action, not "click outside."
- **Close button (red traffic light)** dismisses the window in either state — same rationale.
- **Status-bar icon click** still toggles window visibility in either state.
- **`hidesOnDeactivate = false`** stays false — the window is visible across app switches in either state.

## Edge cases

- **Toggle ON while window is visible:** dismiss monitor is removed; the window stays put. No visible animation; just becomes "sticky."
- **Toggle OFF while window is visible:** dismiss monitor is reinstalled; the window stays where it is until the next outside click. No immediate hide.
- **Window hidden while pinned == true:** the monitor wasn't installed anyway, so nothing to remove. Toggle remains in `pinned == true` state. Re-showing the window respects pinned.
- **Multiple rapid toggles:** the Combine sink debouncing isn't necessary; install/remove are idempotent on the monitor's `nil` check.
- **Existing `suppressDismiss` flag** (used by VoiceNoteView and now AttachmentImporter on the attachments branch) is independent of `pinned` — it's a short-lived suppression for modal flows. `pinned` is the long-lived user preference. Both can be true simultaneously without conflict.

---

## Files touched

| File | Change |
|---|---|
| `Sources/Notaty/Settings.swift` | Add `pinned` property with UserDefaults persistence and the `pinnedKey` constant |
| `Sources/Notaty/NotatyRootView.swift` | Insert pin Button in `TabBar` between paperclip and ＋, with `pin`/`pin.fill` SF Symbol switching on `Settings.shared.pinned` |
| `Sources/Notaty/SettingsView.swift` | Add the "Keep window on top (pinned)" Toggle row |
| `Sources/Notaty/AppDelegate.swift` | Observe `Settings.shared.$pinned`; gate `installDismissMonitors`/`removeDismissMonitors` on the value |
| `CHANGELOG.md` | Add Unreleased entry |

## Acceptance criteria

The feature is "done" when all of these are observable in a debug build:

1. With pinned == false (default), the window auto-hides when the user clicks outside it (preserves current behavior).
2. With pinned == true, the window remains visible after clicks outside.
3. Toggling pinned via the tab-bar pin icon updates the icon glyph (`pin` ↔ `pin.fill`), color, and tooltip immediately.
4. Toggling pinned via the Settings checkbox updates the tab-bar icon glyph, color, and tooltip immediately. Both controls are always in sync.
5. Esc still closes the window when pinned.
6. The traffic-light close button still closes the window when pinned.
7. Pinned state persists across app restarts.
8. Default value is `false` (existing users see no behavior change without opting in).
9. Toggling the value at runtime never crashes the app or produces orphan event monitors.
10. `swift build -c release` succeeds; `bash build.sh` produces a working `.app`.

## Tests

**No automated tests for this release.** Notaty has no test target (precedent: voice notes, OCR, drag-to-reorder, attachments all shipped without tests). Validation is the manual acceptance-criteria walkthrough above.

## Risks

- **Sequencing of dismiss-monitor install on launch.** The current `installDismissMonitors()` is called somewhere in the show-window flow. We need to ensure that when the user has previously left `pinned == true` and relaunches, the monitor is NOT installed even on the first window-show. The Combine observer pattern handles this if installed at launch time.
- **Suppress vs pinned interaction.** During a NSOpenPanel (attachments) the `suppressDismiss` flag is set true temporarily. If `pinned` is also true, the flag is redundant but harmless. No conflict.
- **Visual styling of the pin icon.** The accentColor + filled-pin treatment is the cleanest macOS convention but worth a sanity check during smoke test — the user can flip the styling if it feels off.
