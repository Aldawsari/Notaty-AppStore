# Voice Note Strip — Design Spec

Date: 2026-05-01
Topic: dedicated UI strip for in-app voice recordings (player + transcribe + copy-to-note)

## Overview

Restore the player + transcription bubble UI from the pre-unification `VoiceNoteView` (deleted in commit `568c1dc`), adapted to the current multi-voice-note-per-note model. Each in-app recording renders as a full-width player card with inline waveform, play/pause, a collapsible transcription bubble, and a copy-to-body action. Voice notes live in their own strip, separate from file attachments.

## Goals

- In-app recordings have a dedicated UI separate from file attachments.
- Each recording can be played, transcribed, and have its transcript copied to the note body without leaving the strip.
- Restore the visual idiom from the pre-unification design (waveform player, transcription bubble) at a per-recording granularity.
- Session-scoped transcripts: held in memory only, recomputed each launch.

## Non-goals

- Persisting transcripts across launches.
- Adding a strip for user-imported audio (those continue to render in `AttachmentStripView`).
- Re-introducing the old single-audio-per-note semantics.
- Voice-note attachments — voice notes do not carry their own attachments (deferred separately).

## Data model

`Attachment` gains one field:

```swift
struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String
    var storedName: String
    var byteSize: Int64
    var addedAt: Date
    var isVoiceNote: Bool   // NEW; default false; decoder defaults old data to false
}
```

`RecordingSession.stop()` and `VoiceMigration` set `isVoiceNote = true` on the attachments they create. All other paths leave it `false`.

A v2 migration walks existing `attachments[]` and flips `isVoiceNote = true` for entries whose `originalName` is `"Recording.m4a"` or `"Voice Note.m4a"` (the values produced by the v1 migration and the current `RecordingSession.stop`). Tracked by a new UserDefaults flag `didMigrateVoiceNoteFlag`.

## Transcript cache (session-scoped)

In-memory singleton, no persistence:

```swift
final class TranscriptCache: ObservableObject {
    static let shared = TranscriptCache()
    enum State { case idle, loading, ready(String), failed(Error) }
    @Published private(set) var states: [String: State] = [:]   // keyed by Attachment.storedName
    func state(for storedName: String) -> State
    func transcribe(storedName: String, audioURL: URL) async
    func clear(storedName: String)
}
```

Cache lives only in this process; cleared on app quit.

## Settings

`Settings.shared.autoTranscribe: Bool` — defaults `false`. UserDefaults key `autoTranscribe`. Surfaced in `SettingsView` under the existing voice section.

When `true`, `RecordingSession.stop()` invokes `TranscriptCache.shared.transcribe(...)` immediately for the storedName it just finalized. The card appears with `state == .loading` and the bubble already expanded.

## UI

### Strip placement

`NoteView` body, in this order (from top):

```
RecordingBanner(noteID: …)
VoiceNoteStripView(noteID: …)        ← NEW
AttachmentStripView(noteID: …)
NoteTextEditor(…)
```

`AttachmentStripView` filters to attachments where `isVoiceNote == false`. The voice strip filters the opposite way. Each kind appears in exactly one place.

### VoiceNoteStripView

- Vertical `VStack` of cards, one per voice note (no FlowLayout — full-width cards stack better than wrap).
- Hidden entirely (`EmptyView`) when the active note has zero voice notes.
- Same wrapping container, separator line, and padding as `AttachmentStripView` for visual continuity.

### VoiceNoteCardView

Per voice note. Two sections:

**Player bar** (always visible):

```
[ ▶/⏸ play.circle.fill / pause.circle.fill, size 22, accent ]
[ WaveformView(audioURL:, progress:), height 32, drag-to-seek ]
[ "0:23 / 1:47" 11pt monospaced secondary ]
[ text.badge.plus / text.badge.minus, size 14, accent/secondary ]   ← transcribe toggle
[ xmark.circle.fill, size 14, secondary ]                            ← delete
```

Padding: 12 horizontal / 8 vertical.

**Transcribe icon resolution:** the icon shown on the player bar reflects the underlying state:

| State | Icon | Tap action |
|-------|------|-----------|
| `.idle` | `text.badge.plus` (accent) | Run transcription, then auto-show bubble |
| `.loading` | `text.badge.plus` (greyed) | Disabled |
| `.ready` | `text.badge.minus` (secondary) | Toggle `showTranscription` |
| `.failed` | `text.badge.plus` (accent) | Re-run transcription |

**Transcript bubble** (visible only when `showTranscription == true` AND state is `.loading`, `.ready`, or `.failed`):

```
[ mic.fill 10pt secondary ] [ "Voice Transcription" 10pt medium secondary ]
                                                                          [ Spacer ]
                                                                          [ square.and.pencil 11pt secondary, copy-to-note ]
[ transcript text, 13pt primary, textSelection enabled, auto-direction ]
```

Background: `Color.primary.opacity(0.06)`, corner radius 14, internal padding 12. A `Divider` separates it from the player bar above.

- `.loading` — the bubble body is `ProgressView()` + "Transcribing…" 13pt secondary; the copy-to-note button is hidden.
- `.failed` — body is "Couldn't transcribe — {localized error}" 12pt red; the copy-to-note button is hidden; the transcribe button (now `text.badge.plus`) lets the user retry.
- `.ready` — body is the transcript text as described; copy-to-note button is enabled.

Card states drive a per-card `@StateObject AudioPlayer` and a `@State Bool showTranscription`. Transcript state comes from `TranscriptCache.shared.states[storedName]`.

### Behaviors

| Action | Result |
|--------|--------|
| Tap play/pause | Toggle this card's player. Tapping play on a different card pauses the previous one (single-active-player invariant — see `VoicePlaybackCoordinator` below). |
| Drag waveform | `player.seek(to: ratio * duration)`. |
| Tap transcribe (`text.badge.plus`) when state `.idle` | `state = .loading`, run `SpeechTranscriber.transcribe(audioURL:)`, store result; auto-set `showTranscription = true`. |
| Tap transcribe (`text.badge.minus`) when state `.ready` | Toggle `showTranscription` only — no re-transcribe. |
| Tap transcribe when state `.failed` | Re-run transcription. |
| Tap copy-to-note (`square.and.pencil`) | Prepend the formatted block (see Insert format) to `note.text`. Transcript stays in the cache so the user can copy again. |
| Tap × | Confirm-then-remove via existing `store.removeAttachment(...)`. Clear the corresponding `TranscriptCache` entry. |

### VoicePlaybackCoordinator

```swift
final class VoicePlaybackCoordinator {
    static let shared = VoicePlaybackCoordinator()
    private weak var activePlayer: AudioPlayer?
    func didStartPlaying(_ player: AudioPlayer) {
        if let prior = activePlayer, prior !== player { prior.pause() }
        activePlayer = player
    }
}
```

Each card calls `didStartPlaying(player)` from its play action.

### Insert format

Mirrors the pre-unification `VoiceNoteView.copyTranscriptionToNote`:

```
━━━━━━━━━━━━━━━━━━━━
🎙✍️ Transcription
━━━━━━━━━━━━━━━━━━━━
{transcript}
━━━━━━━━━━━━━━━━━━━━


```

Always **prepended** to `note.text`.

The simpler `\n\n---\n` separator used by the existing `AttachmentStripView.transcribeAndInsert` (right-click on user-imported audio) is left unchanged for non-voice audio. The two flows produce different formatting on purpose: the voice card is a deliberate UX surface, the right-click on imported audio is a quick utility.

## File-level changes

| File | Change |
|------|--------|
| `Attachment.swift` | Add `isVoiceNote: Bool`; decoder defaults old data to `false`. |
| `RecordingSession.swift` | Set `isVoiceNote = true` on the attachment created in `stop()`. If `Settings.autoTranscribe`, kick off a `TranscriptCache.transcribe` task for the new storedName before returning. |
| `VoiceMigration.swift` | Existing v1 migration sets `isVoiceNote = true` on its newly-created attachments. New v2 migration (separate UserDefaults flag) walks existing attachments and flips the field for entries whose `originalName` matches the v1 outputs (`Recording.m4a` / `Voice Note.m4a`). |
| `Settings.swift` | Add `@Published var autoTranscribe: Bool` (UserDefaults key `autoTranscribe`, default false). |
| `SettingsView.swift` | Add toggle in voice section. |
| `AttachmentStripView.swift` | Filter to non-voice attachments. Existing right-click "Transcribe & Insert" stays for non-voice audio. |
| `NoteView.swift` | Render `VoiceNoteStripView(noteID:)` between `RecordingBanner` and `AttachmentStripView`. |
| `TranscriptCache.swift` | NEW. |
| `VoicePlaybackCoordinator.swift` | NEW. |
| `VoiceNoteStripView.swift` | NEW. |
| `VoiceNoteCardView.swift` | NEW. |

## Edge cases

- Note has only voice notes, no other attachments → `AttachmentStripView` renders `EmptyView` (existing guard); voice strip renders the cards.
- App quit during transcription → in-flight `Task` cancels naturally; cache is discarded.
- Many voice notes (e.g., 20) → vertical stack inside the existing scroll view; no special pagination.
- Active recording → not yet an attachment; the existing `RecordingBanner` handles it. The card appears only after `RecordingSession.stop()`.
- Re-transcribing → state goes `.ready` → `.loading` → `.ready` again; bubble shows the spinner during the loading phase.
- Non-voice audio files (`song.mp3` the user attached) → stay in attachment strip; existing right-click flow unchanged.
- Multi-card playback → enforcing single-active-player via `VoicePlaybackCoordinator`.

## Out-of-scope follow-ups

- Persisted transcripts (rejected during this brainstorm — we picked session-scoped).
- Voice-note attachments (voice notes carrying their own files) — already deferred.
- Per-voice-note rename / titling.
- Volume / playback rate controls.
