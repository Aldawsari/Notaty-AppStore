# Notaty

A small macOS menu bar app for quick note-taking with multi-note tabs, OCR
from screen selection, and full RTL / Arabic support.

## Features

- Menu bar icon (⌘-click the `note.text` icon to open the popover)
- Multi-note tabs with a custom Safari-style tab strip and ⌘K quick switcher
- Per-note title + body with auto-saving to `UserDefaults`
- RTL auto-detection (Arabic, Hebrew, Persian, etc.) plus manual override via
  ⌃⌘→ / ⌃⌘← (standard macOS writing direction shortcuts)
- OCR: click the camera icon, drag a region on any display, and the text is
  dropped into a new note. Uses Apple Vision (`VNRecognizeTextRequest`) with
  English, Arabic, and other languages when the current macOS supports them.
- Settings: default window size, light/dark/system theme
- Save As… to export any note as `.txt`

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (for `swift build`)
- Python is **not** required — the icon is generated via `make_icon.swift`

## Building

```sh
swift build -c release
./build.sh 0.8         # assembles dist/Notaty-0.8.app (signs with local dev cert if available)
```

`build.sh` refuses to overwrite an existing `dist/Notaty-<version>.app`, so
bump the version argument for each deployment.

### One-time signing setup

macOS TCC (Screen Recording permission for OCR) keys off the app's code
signature. If you rebuild without a stable signing identity, macOS treats
each build as a brand-new app and forgets the permission.

Run this once on your machine to create a persistent local signing identity:

```sh
./setup-signing.sh
```

This creates a self-signed certificate called `Notaty Local Dev` in your
login keychain. After that, every `./build.sh` automatically signs with it,
and macOS keeps Screen Recording permission across rebuilds.

## Project layout

```
Notaty/
├── Package.swift              # SPM executable target, macOS 13+
├── Sources/Notaty/
│   ├── main.swift             # NSApplication bootstrap (accessory mode)
│   ├── AppDelegate.swift      # Status item + main menu + OCR pipeline
│   ├── NotatyApp                  ❯ nothing (see main.swift)
│   ├── NotatyRootView.swift   # SwiftUI root: tab strip + editor card
│   ├── NoteView.swift         # Title field + editor wrapper
│   ├── NoteTextEditor.swift   # NSTextView wrapped for RTL control
│   ├── NoteWindowController.swift
│   ├── NotesStore.swift       # @Published notes, JSON-persisted
│   ├── Note.swift
│   ├── Settings.swift + SettingsView.swift + SettingsWindowController.swift
│   ├── QuickSwitcher.swift    # ⌘K palette
│   ├── OCRService.swift       # Vision wrapper
│   ├── ScreenRegionSelector.swift  # Per-display overlay panel selector
│   ├── NotatyMenuBuilder.swift # Hamburger menu
│   ├── NotatyActions.swift    # Save As, responder-chain edit helpers
│   └── VisualEffectView.swift
├── build.sh                   # Release build → versioned .app bundle
├── setup-signing.sh           # One-time local signing cert bootstrap
├── make_icon.swift            # Generates AppIcon.icns from SF Symbols
└── AppIcon.icns               # Generated, committed for convenience
```

## Contributing

Branch off `main`, keep commits small, and run `swift build` before pushing.
For UI work, rebuild in place at the current version (`rm -rf
dist/Notaty-<v>.app && ./build.sh <v>`) and test manually — the app is
~100% UI glue with no automated tests.
