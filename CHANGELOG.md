# Changelog

## v0.1.2 (App Store)

- Embed a Mac App Store provisioning profile so the build is TestFlight-eligible (resolves ITMS-90889). No user-facing changes.

## v0.1.1 (App Store)

- Launch at Login no longer defaults to on. The app never registers a login item without explicit user consent — it is enabled only when the user turns on the toggle in Settings. Resolves App Store review rejection for auto-launching at login without consent.

## v0.1 (App Store)

- First App Store submission of the App Store variant (voice notes, attachments, and Sparkle OTA removed). Menu bar notes with multi-note tabs, ⌘K quick switcher, RTL/Arabic support, screen-region OCR with QR decoding, and .txt export.

---

_History below is inherited from the direct-distribution Notaty app._

## v1.3.1

- Bug fixes for voice note recording and transcription.

## v1.3

- File attachments on text notes — drag, paste with ⌘V, paperclip / ⌥⌘A, or drop on the menu bar icon. Files appear as chips under the title; Space for Quick Look, drag between tabs to move, drag back to Finder to copy out. Included in zip export/import.
- Voice notes redesigned. Each in-app recording is a player card with inline waveform, drag-to-seek, play/pause, transcribe toggle, copy-to-note (✏️), and delete (×). Voice notes have their own strip above the file-attachment strip. Old voice notes migrate automatically.
- Auto-transcribe — new Settings toggle (Voice Notes, default off). When on, transcription starts as soon as a recording stops.
- Each voice note is named "Voice Note 1", "Voice Note 2", etc. The transcript bubble and the inserted text block both reference the name.
- OCR reads QR codes. Capture a region with a QR code and the payload is decoded alongside any recognized text, interleaved by visual position.
- Pin window — keep Notaty open while you work via Settings → Window → "Keep window on top". Optional pin button in the tab bar.
- "Check for Updates…" added to the right-click menu on the menu bar icon.
- Bug fixes and stability improvements.

## v1.2.1

- Added Intel Mac support (Universal binary)

## v1.2

- Voice note recording with waveform visualization
- On-device transcription (Arabic & English)
- Settings window stays above main window

## v1.1

- Launch at login support
- Export all notes as zip
- Import notes from zip or .txt
- Sparkle OTA updates with EdDSA signing

## v1.0

- Multi-note tabs with drag-to-reorder
- Quick Switcher (Cmd+K)
- RTL/LTR auto-detection
- OCR screen capture
- Menu bar app with floating window
