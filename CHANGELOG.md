# Changelog

## Unreleased

- File attachments on text notes. Attach files by: clicking the new paperclip in the tab bar, pressing ⌥⌘A, dragging from Finder onto a note, pasting a copied file with ⌘V, or **dropping files onto the Notaty menu bar icon**. Menu bar drop opens the window with a banner showing every file you've dropped — keep dropping to add more, then click any tab or ＋ to attach the whole shelf to that note (or × individual files to remove them from the shelf). Each attachment renders as a chip below the note title with a thumbnail, name, and size. Click a chip to select it (shift+click for range, cmd+click to toggle), press Space to preview with Quick Look, double-click to open in the default app, Delete to remove (with confirmation). Drag chips between tabs to move attachments between notes (multi-select moves the whole group). Drag a chip back to Finder to copy it out. Deleted attachments go to the Trash. Everything survives launches and is included in zip export/import.
- Pin window: keep Notaty's window on top until you close it. Toggle "Keep window on top" in Settings → Window. When pinned, the window no longer hides on outside clicks; Esc and the close button still dismiss as usual. Optional quick-toggle pin icon in the tab bar — enable "Show pin button in tab bar" in Settings if you want one-click access from the window itself.
- Voice notes are unified with regular notes. Recording happens via an inline banner — click 🎤 in any note's title row, or press ⇧⌘N to create a new note that auto-starts recording. Audio recordings appear as M4A attachment chips alongside any other files in the note. Right-click an audio chip to "Transcribe & Insert" the transcript into the note body, "Show in Finder", play, or remove. Existing voice notes from prior versions migrate automatically on first launch — title and body are preserved, audio becomes an attachment. The previous "auto-transcribe on stop" behavior is gone in favor of the explicit right-click action.

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
