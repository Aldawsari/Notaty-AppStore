# Notaty — Voice Notes as Attachments (Design Spec)

**Date:** 2026-05-01
**Status:** Approved for implementation
**Branch:** new feature branch off `main`

---

## Problem

Notaty has two parallel "kinds" of note: text notes (with title, body, attachment strip) and voice notes (with `VoiceNoteView` — a dedicated recorder + waveform + transcription chat-bubble UI). The two share the `Note` struct but use entirely different views. As a result:

- Voice notes can't have file attachments.
- Text notes can't have audio recordings.
- The feature surface is lopsided: every UX decision must be made twice or scoped to one type.
- ~600 lines of voice-specific code (`VoiceNoteView` 351 + `AudioRecorder` 53 + `AudioPlayer` 61 + `SpeechTranscriber` 49 + `WaveformView` 86) carry the voice-specific concept.

## Goal

Unify the two models. Every note is a regular note. A voice recording is just a special **attachment**, rendered as the existing M4A chip. Recording happens in-place via a banner UI, doesn't take the user out of their note, and slots into the same multi-attachment workflow that already exists.

## Out of scope

- **Real-time / streaming transcription.** Transcription happens after recording stops (existing `SpeechTranscriber` is async; no live captions).
- **Audio editing** (trim, splice). The recording is a one-shot capture; editing is a future feature.
- **Cloud sync of audio.** Audio files live alongside other attachments in `~/Library/Application Support/Notaty/attachments/`.
- **Multiple simultaneous recordings.** Only one global recording at a time (mic is a singleton resource anyway).

---

## 1. Data model

### `Note` field changes

- `type: NoteType` — kept Codable (decodes existing data) but **no longer used** by any view, store method, or new note creation. New notes don't write the field. Becomes truly dead in a future release.
- `audioFilename: String?` — kept Codable (decodes existing data) but **no longer used** after migration. New notes don't write it.

### `Attachment` — no changes

Audio files are just attachments. The existing `Attachment` struct (`originalName`, `storedName`, `byteSize`, `addedAt`) handles them.

The chip view's `typeColor` already returns purple for `m4a / mp3 / wav / aiff` (set during the attachments feature work), so audio chips look identical to today's voice-note appearance.

## 2. Storage

- Audio recordings stored at `NotesStore.attachmentsDir/<UUID>.m4a` (same pattern as all attachments).
- Recordings during the in-progress state write to the same path; on Stop, the file is finalized and an `Attachment` record is appended to the note.
- The legacy `audioDir/` is unused after migration but left in place. The orphan-attachment sweep on launch only touches `attachmentsDir/`, not `audioDir/`, so legacy audio files stay safe until manually cleaned (out of scope for v1).

## 3. Recorder UX

### Visual

A slim banner inserted between the title row and the attachment strip in `NoteView`. Layout:

```
┌─────────────────────────────────────────────────┐
│ ● 0:14  ▁▃▅▇▅▃▁▃▅▇▅▃▁▃▅▇▅▃▁    [■ Stop]      │
└─────────────────────────────────────────────────┘
```

Components:
- Pulse dot — `#dc2626` 8×8 circle with subtle pulse animation
- Timer — `monospace tnum` formatted, font-weight: 600, 11.5pt
- Waveform — flex-fill region, real-time amplitude bars (re-using `WaveformView`'s existing rendering logic)
- Stop button — `#dc2626` background, white text "■ Stop", 5pt corner radius

Background: light red gradient (`#fff5f5 → #fef2f2`), 1px `#fecaca` bottom border. Sits above the strip. Total height ~38px.

The banner only renders on the note where the recording was initiated (per the global one-recording rule). When the user is on a different tab, the banner is invisible there.

### State machine

- **Idle** (no recording): banner hidden. 🎤 buttons enabled (in current note's title row + ⇧⌘N + File menu).
- **Recording** (one active globally): banner visible on originating note. All 🎤 entry points disabled globally.
- **Stopping** (transitional, 0–500ms): file finalization. Banner shows briefly until the chip lands. Should be effectively instantaneous to the user.

### Transitions

- 🎤 in title row → if Idle, request mic permission (if needed), start recording, show banner. State → Recording.
- ⇧⌘N → if Idle, create new note titled "Recording {timestamp}", select it, start recording. State → Recording.
- Stop button in banner → finalize file, build `Attachment`, append to note, hide banner. State → Idle.
- Esc while banner visible → equivalent to Stop (finalize and save; never discard).
- Window close while recording → auto-stop, save, then close. Same outcome as Stop.
- Mic permission denied / recording fails → banner shows error in red text for 2s ("Couldn't start recording"), then disappears. Note is unchanged.

### Coordinator

A new singleton `RecordingSession.shared` owns:
- The current `AudioRecorder` instance (or nil)
- The note ID that owns the recording
- A `Timer`-driven elapsed-seconds publisher
- A waveform amplitude publisher (latest sample)
- `start(in noteID: UUID)` / `stop()` / `cancel()`

Banner observes this singleton and updates accordingly. View code never touches `AudioRecorder` directly.

## 4. Transcription

**Manual only.** No automatic transcription on recording stop. (User explicitly chose this in brainstorm: option D.)

### Right-click context menu on audio chips

A new context menu on `AttachmentChipView`, conditional on `attachment.fileExtension` being one of `m4a / mp3 / wav / aiff`:

| Item | Action |
|---|---|
| **Play** | Quick Look (existing single-click behavior; menu duplicates for discoverability) |
| **Transcribe & Insert** | Run `SpeechTranscriber.transcribe(url:language:)` with `Settings.transcribeLanguage`. On completion, append the resulting text to the note's body with a `\n\n---\n` separator before. Errors → alert "Couldn't transcribe ({reason})". |
| **Show in Finder** | `NSWorkspace.shared.activateFileViewerSelecting([url])` |
| **Remove** | Same as the existing × button (with the same confirmation dialog) |

For non-audio chips, only "Show in Finder" and "Remove" appear (or no context menu at all in v1; minimum viable).

### Settings change

- `Settings.autoTranscribe` — **removed entirely** (property, didSet, UserDefaults key, init line, UI toggle row).
- `Settings.transcribeLanguage` — **kept** (used when "Transcribe & Insert" runs).
- `Settings.voiceNotesEnabled` — **kept** (controls whether 🎤 icon shows in title row + whether ⇧⌘N is wired to the recording flow vs. acting as a no-op).

## 5. Migration

One-time, silent, on launch. Triggered by AppDelegate before the main UI shows.

### Trigger

UserDefaults flag `didMigrateVoiceToAttachments`. If false, run migration. After completion, set to true. Never re-runs.

### Steps

1. Iterate `NotesStore.shared.notes`.
2. For each note where `audioFilename != nil`:
   - Resolve `oldURL = NotesStore.audioDir/<filename>`.
   - If file exists at `oldURL`:
     - Compute `newURL = NotesStore.attachmentsDir/<filename>` (preserve same UUID-based name).
     - Move file via `FileManager.moveItem(at: oldURL, to: newURL)`. On failure, fall back to `copyItem` then `removeItem(oldURL)`.
     - Read file size via `attributesOfItem`.
     - Build a new `Attachment(originalName: "Voice Note.m4a", storedName: filename, byteSize: size, addedAt: Date())`.
     - Append to the note's `attachments` array.
   - Clear `audioFilename` (set to nil).
   - Note: `type` field is **not** mutated. It stays `.voice` for old notes (harmless; ignored by all new code paths).
3. Save the migrated `notes.json`.
4. Set `didMigrateVoiceToAttachments = true`.

### Edge cases

- **File missing on disk:** clear `audioFilename` reference, keep title + body, no attachment record. Logged via NSLog for debugging.
- **Move fails (permission, etc.):** log, leave `audioFilename` set, leave file in place. The migration is best-effort; partial completion is acceptable since the flag still gets set after the loop. (Tradeoff: a manually retried migration would be possible by clearing the UserDefaults key, but not exposed in UI.)
- **Migration runs but no voice notes exist:** flag is still set; loop is a no-op.

### What does NOT change

- The `audioDir/` directory itself stays. It will likely be empty after migration but isn't deleted (cautious — no destructive directory ops).
- Existing voice notes' titles ("Voice Note Apr 28, 12:30") and bodies are preserved exactly.

## 6. Entry points & locking

### Entry points

| Action | Result |
|---|---|
| 🎤 button in title row of any note | Start recording in **that** note |
| ⇧⌘N (or File → New Voice Note menu item) | Create new note with title `Recording {timestamp}`, select it, start recording |
| File menu "New Voice Note" → still routes through the same handler |

### Global recording lock

`RecordingSession.shared.isActive` — a `@Published Bool` exposed for binding.

While `isActive == true`:
- Every 🎤 button (title-row icons and any future surfaces) is `.disabled(true)` and dimmed.
- ⇧⌘N keystroke does nothing (NSMenuItem `validateMenuItem` returns false; or AppDelegate's handler early-returns).
- Recording continues regardless of which tab the user is on.
- Switching tabs is fine; banner is per-note (only shows on the originating note).

When `isActive == false`:
- All entry points are enabled. The user can start a new recording in any note.

### Auto-recovery on app exit

If the app quits while recording (window close mid-recording, force quit, crash):
- `applicationShouldTerminate` (or `NSWindow.willCloseNotification` for the main window) calls `RecordingSession.shared.stop()` synchronously, which finalizes the AVAudioRecorder file and saves the chip to the note.
- On crash, the in-progress file may be a partial M4A. The orphan sweep on next launch cleans it. (No partial-recovery UI in v1.)

## 7. Code that goes away

| File | Status |
|---|---|
| `Sources/Notaty/VoiceNoteView.swift` | **Deleted** |
| `Sources/Notaty/SpeechTranscriber.swift` | **Kept** (used by "Transcribe & Insert") |
| `Sources/Notaty/AudioRecorder.swift` | **Kept** (used by `RecordingSession`) |
| `Sources/Notaty/AudioPlayer.swift` | **Kept or deleted** depending on whether Quick Look's audio playback is enough. Likely deletable since QL plays audio. Decide during implementation. |
| `Sources/Notaty/WaveformView.swift` | **Kept** (used by the recording banner) |
| `NoteView`'s `if note?.type == .voice` branch | **Deleted** — every note uses the unified layout |
| `NotesStore.addVoiceNote()` | **Deleted** — replaced by `addNote()` + `RecordingSession.shared.start(in:)` |

## 8. New code

| File | Responsibility |
|---|---|
| `Sources/Notaty/RecordingSession.swift` | Singleton coordinator: owns AudioRecorder, exposes `isActive`, elapsed time, current amplitude. Has `start(in: UUID)`, `stop()`, `cancel()`. ObservableObject for SwiftUI binding. |
| `Sources/Notaty/RecordingBanner.swift` | SwiftUI view: banner with pulse + timer + waveform + Stop button. Observes `RecordingSession.shared`. Renders when `isActive && currentNoteID == noteID`. |
| `Sources/Notaty/VoiceMigration.swift` | One-time migration logic. Called from AppDelegate launch. |

## 9. Modified files

| File | Change |
|---|---|
| `Sources/Notaty/NoteView.swift` | Drop the `if note?.type == .voice` branch. Insert `RecordingBanner(noteID:)` between title row and `AttachmentStripView`. |
| `Sources/Notaty/AttachmentChipView.swift` | Add `.contextMenu` with audio-conditional items (Transcribe & Insert, Show in Finder) and the always-present Remove. |
| `Sources/Notaty/AttachmentStripView.swift` | Wire the new context menu's Transcribe action through to a handler on the strip (it has access to `noteID` and `store`). |
| `Sources/Notaty/AppDelegate.swift` | Run migration on launch. Replace `newVoiceNote()` to create a regular note + start recording. Add global lock for ⇧⌘N. |
| `Sources/Notaty/NotatyRootView.swift` | The 🎤 button in `NoteView`'s title row binds disabled-state to `RecordingSession.shared.isActive` (any active recording disables all 🎤 buttons globally). |
| `Sources/Notaty/Settings.swift` | Remove `autoTranscribe` property + key + init line. Keep `voiceNotesEnabled` and `transcribeLanguage`. |
| `Sources/Notaty/SettingsView.swift` | Remove the "Auto-transcribe" toggle row. |
| `Sources/Notaty/NotesStore.swift` | Remove `addVoiceNote()`. The `delete(id:)` cascade no longer needs to special-case voice (voice notes' audio files are now in attachments[] like everything else). |
| `Sources/Notaty/Note.swift` | No code changes; `type` and `audioFilename` stay decodable for old-data compatibility. |
| `CHANGELOG.md` | Append to Unreleased entry: voice notes are unified into regular notes; recording happens via banner; transcription is now manual via right-click. |

## 10. Acceptance criteria

The feature is "done" when all of these are observable in a debug build:

1. Existing v1.2.1 notes (text) load correctly. No regression.
2. Existing voice notes (with `audioFilename`) load and show the audio as an M4A chip in the new attachment strip. The original title and body are preserved.
3. Migration runs once (on first launch of the new version). UserDefaults flag prevents re-run.
4. Click 🎤 in the title row of a text note → red banner appears below title row → live waveform animates → click Stop → chip lands in strip.
5. Press ⇧⌘N → new note created with title "Recording {timestamp}" → recording auto-starts → banner shows.
6. Right-click an audio chip → context menu shows "Play / Transcribe & Insert / Show in Finder / Remove".
7. "Transcribe & Insert" appends transcript text to the body with a `\n\n---\n` separator.
8. "Show in Finder" reveals the file in `~/Library/Application Support/Notaty/attachments/`.
9. While one recording is active, every 🎤 button (in any tab) is disabled and dimmed; ⇧⌘N is also disabled.
10. Switching tabs during recording: recording continues; banner only renders on the originating tab.
11. Esc / red close button while recording → recording stops cleanly, chip lands.
12. Settings → Voice Notes section: only "Enable Voice Notes" toggle remains. "Auto-transcribe" is gone.
13. No `note.type == .voice` branching anywhere in the new code paths.
14. `swift build -c release` succeeds; `bash build.sh` produces a working `.app`.

## 11. Tests

**No automated tests for this release** — Notaty has no test target (consistent with all prior features). Validation is the manual walkthrough of the 14 acceptance criteria above.

## 12. Risks

- **AVAudioSession permission UX:** the first time the user records, macOS prompts for microphone access. The banner should handle the "denied" case gracefully (error message, no banner persistence).
- **Migration timing:** if the migration runs **before** `NotesStore` finishes loading, the iteration sees an empty array and is a no-op (then the flag gets set, blocking future runs). Migration must run AFTER store load completes. Implementation must enforce this ordering.
- **Migration concurrency:** if the user has notes.json open in another tool (unlikely, but possible), the save could clobber. The migration uses the existing NotesStore save path (UserDefaults + atomic file write), so this is the same risk as any save.
- **WaveformView reuse:** the existing `WaveformView` is built around the recording-then-displaying-finished-waveform pattern, not real-time. May need adapting (or replacing the finished-waveform path with a new live-amplitude path). Implementation will discover this.
- **Transcription failures:** if `SpeechTranscriber` errors (no network, unsupported language), the user sees an alert. Don't append a partial or empty transcript.
- **Lost audio on crash mid-recording:** acceptable for v1. Partial M4A files in `attachmentsDir` get cleaned by orphan sweep.

## 13. Out of scope, follow-ups

- **Discard recording** option (currently every recording saves). Could add a "Cancel" button next to "Stop" later.
- **Pause/resume recording** during a session. Currently it's start → stop only.
- **Audio editing** (trim, splice) on an existing chip.
- **Live transcription** during recording (vs after).
- **Show the transcribed text in a popover before inserting** (the user explicitly chose D — append directly without preview).
- **Audio waveform visualization on a saved chip** (currently the chip just shows "M4A" with the existing icon; could show a small mini-waveform in v2).
- **Multi-recording timeline** (showing recordings as a horizontal track with labels).
