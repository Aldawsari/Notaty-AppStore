# Voice Notes Design

## Goal

Add the ability to create voice notes in Notaty — record audio, auto-transcribe to editable text, and keep the audio for playback.

## Note Model Changes

Add `NoteType` enum and optional `audioFilename` to `Note`:

```swift
enum NoteType: String, Codable {
    case text
    case voice
}
```

New fields on `Note`:
- `type: NoteType` — defaults to `.text`, decoded via `decodeIfPresent` for backward compatibility
- `audioFilename: String?` — e.g. `"<UUID>.m4a"`, stored in `~/Library/Application Support/Notaty/audio/`

Existing notes decode as `.text` with `nil` audioFilename. No migration needed.

## Audio Storage

- Format: `.m4a` (AAC) — native macOS codec, good compression
- Location: `~/Library/Application Support/Notaty/audio/`
- Naming: `{note.id}.m4a`
- The `audio/` subdirectory is created on first recording
- When a voice note is deleted, its audio file is also deleted from disk

## Recording

`AudioRecorder` class wrapping `AVAudioRecorder`:
- Records to a temporary file, then moves to final path on stop
- Audio settings: AAC codec, 44100 Hz sample rate, 1 channel (mono), high quality
- Exposes `isRecording` state for UI binding
- Provides `startRecording(noteID:)` and `stopRecording() -> URL?`

## Transcription

`SpeechTranscriber` class wrapping `SFSpeechRecognizer`:
- On-device recognition (no network required)
- Supports Arabic and English via system locale detection
- `transcribe(audioURL:) async throws -> String`
- Runs after recording stops
- Result is set as the note's `text` field
- If transcription fails, text is set to empty string (user can still play audio)

## Playback

`AudioPlayer` class wrapping `AVAudioPlayer`:
- `play()`, `pause()`, `stop()`
- Published properties: `isPlaying`, `currentTime`, `duration`
- Uses a timer to update `currentTime` during playback
- `load(url:)` to load an audio file

## UI

### VoiceNoteView

Shown when `note.type == .voice`:
- **Title field** — same as text notes, editable
- **Player bar** — horizontal bar with:
  - Play/pause button (SF Symbol: `play.circle.fill` / `pause.circle.fill`)
  - Progress bar showing current position / duration
  - Duration label (e.g. "1:23")
- **Recording state** — when actively recording:
  - Red pulsing dot + "Recording..." / "جاري التسجيل..."
  - Stop button to finish
  - Duration counter showing elapsed time
- **Transcription area** — editable `NoteTextEditor` below the player bar, same component as text notes
- **Transcribing state** — spinner + "Transcribing..." / "جاري التفريغ..." shown while speech recognition runs

### NoteView Changes

Branch on `note.type`:
- `.text` — existing text editor (no changes)
- `.voice` — `VoiceNoteView`

Add a small microphone button in the note view toolbar. Tapping it on a text note converts it to voice type and starts recording.

### Menu Additions

Add "New Voice Note" item in `NotatyMenuBuilder`:
- Position: after the existing "New Note" item
- Keyboard shortcut: Cmd+Shift+N
- Action: creates a new voice note and immediately starts recording

### NotatyActions

Add `newVoiceNote()`:
- Calls `NotesStore.shared.addVoiceNote()` which creates a note with `type: .voice` and title "ملاحظة صوتية" + timestamp
- Opens the note window if not visible
- Starts recording immediately

## NotesStore Changes

- `addVoiceNote() -> Note` — creates note with `type: .voice`, title auto-generated with timestamp
- `delete(id:)` — modified to also delete the audio file from disk when deleting a voice note
- Audio directory management: `ensureAudioDir()` creates `~/Library/Application Support/Notaty/audio/` if needed

## Permissions

Required entitlements/Info.plist keys:
- `NSMicrophoneUsageDescription` — "Notaty needs microphone access to record voice notes"
- `NSSpeechRecognitionUsageDescription` — "Notaty uses speech recognition to transcribe voice notes"

These need to be added via the app's entitlements or Info.plist, configured in Package.swift or build settings.

## New Files

| File | Responsibility |
|------|---------------|
| `AudioRecorder.swift` | AVAudioRecorder wrapper — start/stop recording, save to App Support |
| `AudioPlayer.swift` | AVAudioPlayer wrapper — play/pause, time tracking |
| `SpeechTranscriber.swift` | SFSpeechRecognizer wrapper — transcribe audio file to text |
| `VoiceNoteView.swift` | Player bar + recording state + transcription text for voice notes |

## Modified Files

| File | Change |
|------|--------|
| `Note.swift` | Add `NoteType` enum, `type` and `audioFilename` fields |
| `NotesStore.swift` | Add `addVoiceNote()`, delete audio on note delete, audio dir management |
| `NoteView.swift` | Branch on `note.type` — show `VoiceNoteView` for voice notes, add mic button |
| `NotatyMenuBuilder.swift` | Add "New Voice Note" menu item with Cmd+Shift+N |
| `NotatyActions.swift` | Add `newVoiceNote()` action |
| `Package.swift` | Add entitlements for microphone + speech recognition |

## Backward Compatibility

- Existing notes decode as `type: .text` with `audioFilename: nil` — no migration
- The JSON format is extended, not changed — old versions ignore unknown keys
- No changes to export/import (voice notes export the transcription text; audio files are not included in zip export)
