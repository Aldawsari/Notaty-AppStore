# NotatyAppstore

The App Store variant of Notaty, a small macOS menu bar app for quick
note-taking with multi-note tabs, OCR from screen selection, and full RTL /
Arabic support.

This repository is separate from the direct-distribution Notaty app. Sparkle
OTA updates and external deployment scripts are intentionally removed for App
Store preparation.

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
./build.sh 1.0         # assembles dist/NotatyAppstore-1.0.app
```

`build.sh` refuses to overwrite an existing `dist/NotatyAppstore-<version>.app`, so
bump the version argument for each deployment.

For App Store packaging, archive/export with an Apple Distribution identity
and an App Store Connect provisioning profile. `NotatyAppstore.entitlements`
enables App Sandbox, microphone input, user-selected file access, and outbound
network access for Speech recognition. The local `build.sh` can ad-hoc sign
for validation if no matching identity is available.

## Project layout

```
NotatyAppstore/
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
├── build.sh                   # App Store-oriented local .app bundle
├── run-debug.sh               # Builds and launches a debug .app bundle
├── NotatyAppstore.entitlements
├── APP_STORE_BUILD.md         # Repo safety marker for App Store variant
├── make_icon.swift            # Generates AppIcon.icns from SF Symbols
└── AppIcon.icns               # Generated, committed for convenience
```

## Contributing

Branch off `main`, keep commits small, and run `swift build` before pushing.
For UI work, rebuild in place at the current version (`rm -rf
dist/NotatyAppstore-<v>.app && ./build.sh <v>`) and test manually — the app is
~100% UI glue with no automated tests.
