# Notaty — Design Spec

**Date:** 2026-04-11
**Status:** Approved for planning

## Summary

Notaty is a minimal macOS menu bar app for quick note-taking. Clicking the menu bar icon toggles a small floating window containing a single plain-text field. The note auto-saves and persists across launches. The window floats above other apps and can be dragged and resized.

## Goals

- Zero-friction quick notes: one click to open, start typing immediately
- Always accessible: floats above other windows
- Persistent: last note content, window size, and window position all survive relaunch
- Tiny footprint: no Dock icon, minimal UI

## Non-Goals

- Multiple notes or note list
- Rich text or markdown formatting
- Sync, export, or sharing
- Global hotkey (menu bar click only)
- Search, tags, or organization features

## Platform & Stack

- **Target:** macOS 13+
- **Language:** Swift 5.9+
- **UI:** SwiftUI (with minimal AppKit for `NSStatusItem` + `NSWindow`)
- **Build:** Swift Package Manager executable (matches sibling Lab apps: Taqweem, Radio)
- **Persistence:** `UserDefaults` via `@AppStorage`
- **Bundle:** `LSUIElement = true` (no Dock icon, menu bar only)

## Architecture

Single SwiftUI `App` with an `NSApplicationDelegateAdaptor`. The app delegate owns the status item and a single window controller. The window hosts a SwiftUI view via `NSHostingController`.

### File Layout

```
Notaty/
├── Package.swift
├── Sources/Notaty/
│   ├── NotatyApp.swift          # @main entry
│   ├── AppDelegate.swift        # NSStatusItem + window toggling
│   ├── NoteWindowController.swift  # NSWindow configuration
│   └── NoteView.swift           # SwiftUI TextEditor
└── Resources/
    └── Info.plist               # LSUIElement=true
```

### Components

**NotatyApp.swift**
- `@main struct NotatyApp: App`
- `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`
- Empty `Settings {}` scene (no main window scene; delegate manages window)

**AppDelegate.swift**
- `NSObject, NSApplicationDelegate`
- Owns: `statusItem: NSStatusItem`, `windowController: NoteWindowController`
- `applicationDidFinishLaunching`:
  - Create `NSStatusItem` of variable length
  - Set button image to SF Symbol `note.text` (via `NSImage(systemSymbolName:accessibilityDescription:)`)
  - Set button target/action to `toggleWindow`
  - Instantiate `NoteWindowController`
- `@objc toggleWindow`:
  - If window is visible → `window.orderOut(nil)`
  - Else → `window.makeKeyAndOrderFront(nil)` and activate app

**NoteWindowController.swift**
- Subclass or wrapper around `NSWindowController`
- Creates an `NSWindow` with:
  - `styleMask`: `[.titled, .closable, .resizable, .fullSizeContentView]`
  - `level = .floating` (stays above normal windows)
  - `isMovableByWindowBackground = true`
  - `titlebarAppearsTransparent = true`
  - `title = "Notaty"`
  - Default content size `400×300`, min size `250×150`
  - `setFrameAutosaveName("NotatyWindow")` for persistent frame
- `contentViewController = NSHostingController(rootView: NoteView())`

**NoteView.swift**
- `struct NoteView: View`
- `@AppStorage("noteText") private var noteText: String = ""`
- Body: `TextEditor(text: $noteText)` with padding, system font, filling the window

## Data Flow

1. User clicks menu bar icon → `AppDelegate.toggleWindow` → window shows at saved frame
2. User types in `TextEditor` → `@AppStorage` writes to `UserDefaults.standard` on every change
3. User drags/resizes window → AppKit writes frame to `UserDefaults` via autosave
4. User clicks icon again → window hides (data already persisted)
5. Next launch → `@AppStorage` reads last text; window restores last frame

No model layer, no services, no observers beyond what SwiftUI provides natively.

## Persistence Keys

| Key | Type | Source |
|-----|------|--------|
| `noteText` | String | `@AppStorage` |
| `NSWindow Frame NotatyWindow` | String | `setFrameAutosaveName` |

## Error Handling

Minimal by design. No network, no file I/O, no external APIs. `UserDefaults` writes for a single string do not fail in practice. If `statusItem.button` is unexpectedly nil, the app still launches cleanly — the icon simply will not appear (not expected on supported macOS versions).

## Testing Strategy

Manual smoke test only. The app is ~100 lines of UI glue with no business logic worth unit-testing.

**Smoke test checklist:**
1. Build and launch → menu bar icon appears, no Dock icon
2. Click icon → floating window appears above other apps
3. Type text → close window → reopen → text still present
4. Drag window by background → close → relaunch → position restored
5. Resize window → close → relaunch → size restored
6. Click icon while window open → window hides
7. Window remains above other apps when they gain focus

## Build & Deployment

- Build via `swift build -c release` then package into `.app` bundle
- Per project CLAUDE.md versioning rule: first build is `dist/Notaty-1.0.app`
- Never overwrite previous builds; increment minor version per feature

## Open Questions

None. All design decisions confirmed with user during brainstorming.
