# Voice Note Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the per-recording player + transcription bubble UI from the pre-unification `VoiceNoteView`, adapted to the multi-voice-note-per-note model. In-app recordings live in a new strip above the attachment strip, with play/pause, drag-to-seek waveform, transcribe toggle, copy-to-note, and delete on each card.

**Architecture:** A new `isVoiceNote: Bool` flag on `Attachment` separates in-app recordings from user-imported audio. `VoiceNoteStripView` filters `note.attachments` to voice notes; `AttachmentStripView` filters to non-voice. A session-scoped `TranscriptCache` singleton holds per-storedName transcript state. A `VoicePlaybackCoordinator` enforces single-active-player across cards. A v2 migration flips the flag on existing voice attachments created before the field existed.

**Tech Stack:** Swift / SwiftUI / AppKit / AVFoundation (existing `AudioPlayer`, `WaveformView`), `SpeechTranscriber`, `NotesStore`, `Settings`.

**Spec:** `docs/superpowers/specs/2026-05-01-voice-note-strip-design.md`

**Scope:** No automated tests (Notaty has no test target). Validation via the acceptance checklist in Task 13, walked manually.

---

## File Structure

| Path | Change |
|------|--------|
| `Sources/Notaty/Attachment.swift` | Modify: add `isVoiceNote: Bool` field with backward-compatible decoder default |
| `Sources/Notaty/RecordingSession.swift` | Modify: set `isVoiceNote = true` on the new attachment in `stop()`; trigger auto-transcribe |
| `Sources/Notaty/VoiceMigration.swift` | Modify: v1 sets `isVoiceNote = true`; **add v2 sweep** for pre-flag voice attachments |
| `Sources/Notaty/Settings.swift` | Modify: add `@Published autoTranscribe: Bool` + UserDefaults key |
| `Sources/Notaty/SettingsView.swift` | Modify: add "Transcribe automatically" toggle to Voice Notes section |
| `Sources/Notaty/TranscriptCache.swift` | **New.** Session-scoped transcript state, keyed by `Attachment.storedName` |
| `Sources/Notaty/VoicePlaybackCoordinator.swift` | **New.** Single-active-player invariant across cards |
| `Sources/Notaty/VoiceNoteCardView.swift` | **New.** Per-recording player bar + collapsible transcript bubble |
| `Sources/Notaty/VoiceNoteStripView.swift` | **New.** Vertical stack of cards, hidden when no voice notes |
| `Sources/Notaty/AttachmentStripView.swift` | Modify: filter `attachments` computed property to non-voice |
| `Sources/Notaty/NoteView.swift` | Modify: render `VoiceNoteStripView` between `RecordingBanner` and `AttachmentStripView` |
| `CHANGELOG.md` | Append a bullet under "Unreleased" |

---

## Task 1: Add `isVoiceNote` field to Attachment

**Files:**
- Modify: `Sources/Notaty/Attachment.swift`

- [ ] **Step 1: Replace the file with the new model**

```swift
import Foundation

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String
    var storedName: String
    var byteSize: Int64
    var addedAt: Date
    /// True if this attachment was created by an in-app voice recording —
    /// either via `RecordingSession.stop()` or `VoiceMigration`. Voice-note
    /// attachments render in `VoiceNoteStripView`; everything else renders
    /// in `AttachmentStripView`.
    var isVoiceNote: Bool

    init(
        id: UUID = UUID(),
        originalName: String,
        storedName: String,
        byteSize: Int64,
        addedAt: Date = Date(),
        isVoiceNote: Bool = false
    ) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.byteSize = byteSize
        self.addedAt = addedAt
        self.isVoiceNote = isVoiceNote
    }

    private enum CodingKeys: String, CodingKey {
        case id, originalName, storedName, byteSize, addedAt, isVoiceNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.originalName = try c.decode(String.self, forKey: .originalName)
        self.storedName = try c.decode(String.self, forKey: .storedName)
        self.byteSize = try c.decode(Int64.self, forKey: .byteSize)
        self.addedAt = try c.decode(Date.self, forKey: .addedAt)
        self.isVoiceNote = try c.decodeIfPresent(Bool.self, forKey: .isVoiceNote) ?? false
    }

    /// File extension without the dot, lowercased, derived from `originalName`.
    var fileExtension: String {
        (originalName as NSString).pathExtension.lowercased()
    }

    /// True if `fileExtension` is one of the image types we render thumbnails for.
    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp"].contains(fileExtension)
    }

    /// True if `fileExtension` is one of the audio types the app can
    /// transcribe and play inline.
    var isAudio: Bool {
        ["m4a", "mp3", "wav", "aiff"].contains(fileExtension)
    }

    /// Up-to-4-character uppercase label for non-image type icons.
    var typeLabel: String {
        let ext = fileExtension
        if ext.isEmpty { return "FILE" }
        return String(ext.prefix(4)).uppercased()
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build (no errors). Existing `Attachment(...)` callers compile because `isVoiceNote` has a default.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/Attachment.swift
git commit -m "feat(notaty): add isVoiceNote field to Attachment with backward-compatible decode"
```

---

## Task 2: RecordingSession.stop() sets isVoiceNote = true

**Files:**
- Modify: `Sources/Notaty/RecordingSession.swift`

- [ ] **Step 1: Update the attachment construction in `stop()`**

Find this block:

```swift
        let attachment = Attachment(
            originalName: originalName,
            storedName: storedName,
            byteSize: size
        )
```

Replace with:

```swift
        let attachment = Attachment(
            originalName: originalName,
            storedName: storedName,
            byteSize: size,
            isVoiceNote: true
        )
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/RecordingSession.swift
git commit -m "feat(notaty): mark recording-session attachments as isVoiceNote"
```

---

## Task 3: VoiceMigration v1 sets the flag + new v2 sweep for existing data

**Files:**
- Modify: `Sources/Notaty/VoiceMigration.swift`

- [ ] **Step 1: Replace the file**

```swift
import Foundation

/// Two-phase migration:
///   v1 — convert legacy voice notes (`audioFilename` set) into regular notes
///        with the audio attached. Sets `isVoiceNote = true` on the new
///        attachment.
///   v2 — one-shot sweep for users on the unreleased build whose voice
///        attachments were created before `isVoiceNote` existed. Flips the
///        flag on attachments whose `originalName` matches the values
///        produced by v1 and `RecordingSession.stop()`.
///
/// Each phase has its own UserDefaults flag so neither re-runs.
enum VoiceMigration {
    private static let v1Key = "didMigrateVoiceToAttachments"
    private static let v2Key = "didMigrateVoiceNoteFlag"

    static func runIfNeeded() {
        runV1IfNeeded()
        runV2IfNeeded()
    }

    private static func runV1IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: v1Key) else { return }
        defer { UserDefaults.standard.set(true, forKey: v1Key) }

        let store = NotesStore.shared
        var migratedCount = 0

        for note in store.notes {
            guard let filename = note.audioFilename else { continue }
            let oldURL = NotesStore.audioDir.appendingPathComponent(filename)
            let newURL = NotesStore.attachmentsDir.appendingPathComponent(filename)
            store.ensureAttachmentsDir()

            if FileManager.default.fileExists(atPath: oldURL.path) {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.removeItem(at: newURL)
                }
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                } catch {
                    if (try? FileManager.default.copyItem(at: oldURL, to: newURL)) != nil {
                        try? FileManager.default.removeItem(at: oldURL)
                    } else {
                        NSLog("VoiceMigration: failed to relocate \(filename): \(error)")
                        continue
                    }
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: newURL.path)[.size] as? Int64) ?? 0
                let attachment = Attachment(
                    originalName: "Voice Note.m4a",
                    storedName: filename,
                    byteSize: size,
                    isVoiceNote: true
                )
                store.update(id: note.id) {
                    $0.attachments.append(attachment)
                    $0.audioFilename = nil
                }
                migratedCount += 1
            } else {
                // Audio file is missing on disk — clear the dangling reference.
                store.update(id: note.id) { $0.audioFilename = nil }
            }
        }

        if migratedCount > 0 {
            NSLog("VoiceMigration v1: converted \(migratedCount) voice notes to regular notes with audio attachments")
        }

        // Anything v1 just produced already has isVoiceNote = true, so skip v2
        // for first-launch users.
        UserDefaults.standard.set(true, forKey: v2Key)
    }

    private static func runV2IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: v2Key) else { return }
        defer { UserDefaults.standard.set(true, forKey: v2Key) }

        let store = NotesStore.shared
        var flippedCount = 0

        for note in store.notes {
            var newAttachments = note.attachments
            var changed = false
            for idx in newAttachments.indices {
                let att = newAttachments[idx]
                if !att.isVoiceNote
                    && (att.originalName == "Recording.m4a" || att.originalName == "Voice Note.m4a") {
                    newAttachments[idx].isVoiceNote = true
                    changed = true
                    flippedCount += 1
                }
            }
            if changed {
                store.update(id: note.id) { $0.attachments = newAttachments }
            }
        }

        if flippedCount > 0 {
            NSLog("VoiceMigration v2: flipped \(flippedCount) attachments to isVoiceNote=true")
        }
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/VoiceMigration.swift
git commit -m "feat(notaty): voice migration sets isVoiceNote; add v2 sweep for pre-flag data"
```

---

## Task 4: Add `Settings.autoTranscribe`

**Files:**
- Modify: `Sources/Notaty/Settings.swift`

- [ ] **Step 1: Add the property**

After the `transcribeLanguage` `@Published` block (around line 86), insert:

```swift
    @Published var autoTranscribe: Bool {
        didSet { UserDefaults.standard.set(autoTranscribe, forKey: Self.autoTranscribeKey) }
    }
```

- [ ] **Step 2: Add the UserDefaults key**

In the `private static let *Key = "..."` block (around line 105), add:

```swift
    private static let autoTranscribeKey = "autoTranscribe"
```

- [ ] **Step 3: Initialize in `init()`**

After the line that sets `self.transcribeLanguage` (around line 123), insert:

```swift
        self.autoTranscribe = UserDefaults.standard.bool(forKey: Self.autoTranscribeKey)
```

(`UserDefaults.bool(forKey:)` returns `false` for missing keys, so the default-off requirement is satisfied without explicit checking.)

- [ ] **Step 4: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/Settings.swift
git commit -m "feat(notaty): add autoTranscribe setting (default off)"
```

---

## Task 5: Add "Transcribe automatically" toggle to SettingsView

**Files:**
- Modify: `Sources/Notaty/SettingsView.swift`

- [ ] **Step 1: Insert the toggle into the Voice Notes section**

Find the Voice Notes `settingsCard { ... }` block (around lines 63–84). Inside the existing `if settings.voiceNotesEnabled { ... }` branch, after the language `HStack`, add a Divider and toggle:

```swift
                    if settings.voiceNotesEnabled {
                        Divider()

                        HStack {
                            rowLabel("Transcription Language")
                            Spacer()
                            Picker("", selection: $settings.transcribeLanguage) {
                                ForEach(Settings.supportedLanguages, id: \.id) { lang in
                                    Text(lang.label).tag(lang.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Divider()

                        Toggle(isOn: $settings.autoTranscribe) {
                            rowLabel("Transcribe automatically")
                        }
                        .toggleStyle(.switch)
                    }
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/SettingsView.swift
git commit -m "feat(notaty): add 'Transcribe automatically' toggle to Settings"
```

---

## Task 6: Create `TranscriptCache`

**Files:**
- Create: `Sources/Notaty/TranscriptCache.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation
import Combine

/// Session-scoped, in-memory transcript store for voice-note attachments.
/// Keyed by `Attachment.storedName`. Cleared on app quit (no persistence).
/// VoiceNoteCardView observes via `@ObservedObject` and reads via
/// `state(for:)`.
final class TranscriptCache: ObservableObject {
    static let shared = TranscriptCache()

    enum State {
        case idle
        case loading
        case ready(String)
        case failed(Error)
    }

    @Published private(set) var states: [String: State] = [:]

    private init() {}

    func state(for storedName: String) -> State {
        states[storedName] ?? .idle
    }

    /// Run on the main actor so observed UI updates dispatch correctly.
    @MainActor
    func transcribe(storedName: String, audioURL: URL) async {
        states[storedName] = .loading
        do {
            let text = try await SpeechTranscriber.transcribe(audioURL: audioURL)
            states[storedName] = .ready(text)
        } catch {
            states[storedName] = .failed(error)
        }
    }

    func clear(storedName: String) {
        states.removeValue(forKey: storedName)
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/TranscriptCache.swift
git commit -m "feat(notaty): add TranscriptCache for session-scoped transcripts"
```

---

## Task 7: Create `VoicePlaybackCoordinator`

**Files:**
- Create: `Sources/Notaty/VoicePlaybackCoordinator.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Enforces a single-active-player invariant across all VoiceNoteCardView
/// instances. Each card calls `didStartPlaying(_:)` from its play action;
/// the coordinator pauses any prior player. Holds a weak reference so
/// nothing leaks when a card is dismantled.
final class VoicePlaybackCoordinator {
    static let shared = VoicePlaybackCoordinator()

    private weak var activePlayer: AudioPlayer?

    private init() {}

    func didStartPlaying(_ player: AudioPlayer) {
        if let prior = activePlayer, prior !== player {
            prior.pause()
        }
        activePlayer = player
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/VoicePlaybackCoordinator.swift
git commit -m "feat(notaty): add VoicePlaybackCoordinator for single-active-player"
```

---

## Task 8: Create `VoiceNoteCardView`

**Files:**
- Create: `Sources/Notaty/VoiceNoteCardView.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import AppKit

/// One row in `VoiceNoteStripView` — a player bar plus an optional
/// collapsible transcript bubble for a single voice-note Attachment.
struct VoiceNoteCardView: View {
    let attachment: Attachment
    let noteID: UUID

    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var cache = TranscriptCache.shared
    @StateObject private var player = AudioPlayer()
    @State private var showTranscription = false
    @State private var didLoadAudio = false

    private var audioURL: URL { NotesStore.attachmentURL(for: attachment) }

    private var transcriptState: TranscriptCache.State {
        cache.state(for: attachment.storedName)
    }

    /// Whether the bubble is rendered. We hide it when transcript state is
    /// .idle (nothing to show) regardless of `showTranscription`, since the
    /// bubble would otherwise flash on first transcribe-tap before the
    /// loading state is set.
    private var bubbleVisible: Bool {
        guard showTranscription else { return false }
        switch transcriptState {
        case .idle: return false
        case .loading, .ready, .failed: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            playerBar
            if bubbleVisible {
                Divider().opacity(0.4)
                bubble
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .onAppear {
            if !didLoadAudio {
                player.load(url: audioURL)
                didLoadAudio = true
            }
        }
        .onDisappear { player.pause() }
    }

    // MARK: - Player bar

    private var playerBar: some View {
        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Play")

            WaveformView(
                audioURL: audioURL,
                progress: player.duration > 0 ? player.currentTime / player.duration : 0
            )
            .frame(height: 32)
            .contentShape(Rectangle())
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard player.duration > 0 else { return }
                                    let ratio = max(0, min(1, value.location.x / geo.size.width))
                                    player.seek(to: ratio * player.duration)
                                }
                        )
                }
            )

            Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: handleTranscribeTap) {
                Image(systemName: transcribeIconName)
                    .font(.system(size: 14))
                    .foregroundColor(transcribeIconColor)
            }
            .buttonStyle(.plain)
            .disabled(transcriptState.isLoading)
            .help(transcribeHelpText)

            Button(action: confirmDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete voice note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript bubble

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Voice Transcription")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if case .ready = transcriptState {
                    Button(action: copyTranscriptionToNote) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to note")
                }
            }
            bubbleBody
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch transcriptState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Transcribing…")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        case .ready(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, transcriptDirection(text))
        case .failed(let error):
            Text("Couldn't transcribe — \(error.localizedDescription)")
                .font(.system(size: 12))
                .foregroundColor(.red)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Icon resolution

    private var transcribeIconName: String {
        switch transcriptState {
        case .ready:
            return showTranscription ? "text.badge.minus" : "text.badge.plus"
        case .idle, .loading, .failed:
            return "text.badge.plus"
        }
    }

    private var transcribeIconColor: Color {
        switch transcriptState {
        case .loading: return Color.secondary.opacity(0.5)
        case .ready where showTranscription: return .secondary
        case .ready: return .accentColor
        case .idle, .failed: return .accentColor
        }
    }

    private var transcribeHelpText: String {
        switch transcriptState {
        case .idle: return "Transcribe"
        case .loading: return "Transcribing…"
        case .ready: return showTranscription ? "Hide transcription" : "Show transcription"
        case .failed: return "Try again"
        }
    }

    // MARK: - Actions

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            VoicePlaybackCoordinator.shared.didStartPlaying(player)
            player.play()
        }
    }

    private func handleTranscribeTap() {
        switch transcriptState {
        case .idle, .failed:
            showTranscription = true
            Task {
                await cache.transcribe(storedName: attachment.storedName, audioURL: audioURL)
            }
        case .ready:
            showTranscription.toggle()
        case .loading:
            break
        }
    }

    private func copyTranscriptionToNote() {
        guard case .ready(let text) = transcriptState else { return }
        let separator = "━━━━━━━━━━━━━━━━━━━━"
        let block = "\(separator)\n🎙✍️ Transcription\n\(separator)\n\(text)\n\(separator)\n\n"
        store.update(id: noteID) { $0.text = block + $0.text }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete this voice note?"
        alert.informativeText = "The recording will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cache.clear(storedName: attachment.storedName)
        store.removeAttachment(attachment.id, from: noteID)
    }

    // MARK: - Helpers

    private func transcriptDirection(_ text: String) -> LayoutDirection {
        let dir = NoteTextEditor.resolveDirection(mode: .auto, text: text)
        return dir == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension TranscriptCache.State {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build. Notaty already imports AppKit + AVFoundation transitively via existing files; no additional Package.swift work.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/VoiceNoteCardView.swift
git commit -m "feat(notaty): VoiceNoteCardView — player bar + transcript bubble"
```

---

## Task 9: Create `VoiceNoteStripView`

**Files:**
- Create: `Sources/Notaty/VoiceNoteStripView.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import AppKit

/// Strip section that lists all in-app voice recordings for a note as
/// stacked `VoiceNoteCardView`s. Hidden entirely when the active note has
/// no voice notes. Sits between `RecordingBanner` and `AttachmentStripView`
/// inside `NoteView`.
struct VoiceNoteStripView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    private var voiceNotes: [Attachment] {
        store.note(for: noteID)?.attachments.filter { $0.isVoiceNote } ?? []
    }

    var body: some View {
        if voiceNotes.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                ForEach(voiceNotes) { attachment in
                    VoiceNoteCardView(attachment: attachment, noteID: noteID)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/VoiceNoteStripView.swift
git commit -m "feat(notaty): VoiceNoteStripView — vertical stack of voice cards"
```

---

## Task 10: Filter voice notes out of `AttachmentStripView`

**Files:**
- Modify: `Sources/Notaty/AttachmentStripView.swift`

- [ ] **Step 1: Update the `attachments` computed property**

Find this block (around line 27):

```swift
    private var attachments: [Attachment] {
        store.note(for: noteID)?.attachments ?? []
    }
```

Replace with:

```swift
    private var attachments: [Attachment] {
        // Voice-note attachments render in VoiceNoteStripView. Everything
        // else (files, user-imported audio) renders here.
        (store.note(for: noteID)?.attachments ?? []).filter { !$0.isVoiceNote }
    }
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AttachmentStripView.swift
git commit -m "feat(notaty): hide voice-note attachments from AttachmentStripView"
```

---

## Task 11: Render `VoiceNoteStripView` in `NoteView`

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`

- [ ] **Step 1: Insert the strip between the banner and the attachment strip**

Find this block in `body` (around lines 56–58):

```swift
            RecordingBanner(noteID: noteID)

            AttachmentStripView(noteID: noteID)
```

Replace with:

```swift
            RecordingBanner(noteID: noteID)

            VoiceNoteStripView(noteID: noteID)

            AttachmentStripView(noteID: noteID)
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/NoteView.swift
git commit -m "feat(notaty): mount VoiceNoteStripView between recording banner and attachments"
```

---

## Task 12: Wire auto-transcribe trigger into `RecordingSession.stop()`

**Files:**
- Modify: `Sources/Notaty/RecordingSession.swift`

- [ ] **Step 1: Trigger `TranscriptCache.transcribe` when the setting is on**

In `stop()`, after the `NotesStore.shared.update(...)` line that appends the new attachment, before `return storedName`, insert:

```swift
        if Settings.shared.autoTranscribe {
            Task { @MainActor in
                await TranscriptCache.shared.transcribe(
                    storedName: storedName,
                    audioURL: url
                )
            }
        }
```

The complete `stop()` body should now look like:

```swift
    @MainActor
    @discardableResult
    func stop() -> String? {
        guard isActive, let noteID = currentNoteID else { return nil }
        guard let url = recorder.stopRecording() else { return nil }
        let storedName = url.lastPathComponent
        let originalName = "Recording.m4a"
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let attachment = Attachment(
            originalName: originalName,
            storedName: storedName,
            byteSize: size,
            isVoiceNote: true
        )
        NotesStore.shared.update(id: noteID) { $0.attachments.append(attachment) }
        if Settings.shared.autoTranscribe {
            Task { @MainActor in
                await TranscriptCache.shared.transcribe(
                    storedName: storedName,
                    audioURL: url
                )
            }
        }
        return storedName
    }
```

- [ ] **Step 2: Build to verify compile**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/RecordingSession.swift
git commit -m "feat(notaty): auto-transcribe on stop when the Settings toggle is on"
```

---

## Task 13: Update CHANGELOG and run the manual acceptance checklist

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append a bullet to the "Unreleased" section**

Open `CHANGELOG.md`. Inside the existing `## Unreleased` block (above `## v1.2.1`), add this bullet at the bottom of the list:

```markdown
- Voice notes have their own dedicated strip above the file-attachment strip. Each in-app recording renders as a player card with inline waveform, drag-to-seek, play/pause, transcribe toggle, copy-to-note (✏️), and delete (×). The transcript bubble is collapsible — first tap on the transcribe icon runs transcription and opens the bubble; subsequent taps show/hide. Transcripts are session-scoped (cleared on app quit). Auto-transcribe is available as a Settings toggle (Voice Notes section, default off): when enabled, transcription starts automatically as soon as a recording stops. Existing voice notes from the unreleased build migrate automatically on first launch.
```

- [ ] **Step 2: Build the debug app**

Run: `./run-debug.sh`
Expected: build clean and `Notaty-Debug.app` opens with the new icon visible in the menu bar.

- [ ] **Step 3: Walk the acceptance checklist**

Click the menu bar icon. With at least one note in your store, run through:

- [ ] **A1.** Click the mic 🎤 in a note's title row. Recording banner appears. Click Stop. A new card appears in a strip *above* any other attachment chips (a strip didn't exist before — it should appear now).
- [ ] **A2.** Click the paperclip 📎. Pick a non-audio file (e.g., a PDF or PNG). It appears as a chip in the regular attachment strip *below* the voice strip. Voice strip is unaffected.
- [ ] **A3.** Click the paperclip 📎. Pick an audio file from Finder (e.g., an `.mp3`). It appears in the regular attachment strip — *not* in the voice strip.
- [ ] **A4.** On a voice card: tap ▶. Audio plays. Tap ⏸. Stops. Drag the waveform left/right. Playhead seeks.
- [ ] **A5.** Tap the transcribe icon (`text.badge.plus`). Bubble opens with "Transcribing…", then the transcript text after a few seconds.
- [ ] **A6.** Tap the transcribe icon again (now `text.badge.minus`). Bubble hides. Tap again. Bubble re-opens with the same transcript — no re-transcribe.
- [ ] **A7.** Tap the ✏️ icon in the bubble header. The note body now starts with the formatted transcript block (`━━━━━━━━━━━━━━━━━━━━` separators + `🎙✍️ Transcription`).
- [ ] **A8.** Tap ✏️ a second time. Body now has *two* prepended blocks — the action is non-destructive copy, not a one-shot move.
- [ ] **A9.** Open the menu bar's hamburger ▸ Settings. Voice Notes section now has a "Transcribe automatically" toggle. Turn it on.
- [ ] **A10.** Record a new voice note. As soon as you click Stop, the new card appears with the bubble already showing "Transcribing…" — no manual tap needed.
- [ ] **A11.** Quit Notaty (⌘Q). Re-open. Voice cards still appear. Their bubbles are *closed* and the transcribe icon is back to `text.badge.plus` (cache is session-scoped).
- [ ] **A12.** Tap × on a voice card. Confirm. Card disappears. The audio file is in the user's Trash.
- [ ] **A13.** Create a second voice note. Tap ▶ on the first card. Tap ▶ on the second card. The first one auto-pauses (single-active-player invariant).
- [ ] **A14.** *Migration check:* if you had voice notes recorded on the build *before* this change (their `isVoiceNote` was implicitly false), launch this build and verify they have moved to the voice strip. (Skip if you don't have pre-existing data.)

If any check fails, file a bug and stop — do not commit step 4 until everything passes.

- [ ] **Step 4: Commit the CHANGELOG update**

```bash
git add CHANGELOG.md
git commit -m "docs(notaty): note voice strip + auto-transcribe in CHANGELOG"
```

---

## Done

The feature is fully wired up:

- Voice notes live in their own strip (`VoiceNoteStripView`) above the file attachment strip.
- Each card has play/pause, drag-to-seek waveform, transcribe toggle, copy-to-note, and delete.
- Transcripts are session-scoped (`TranscriptCache`).
- Single-active-player is enforced (`VoicePlaybackCoordinator`).
- Auto-transcribe is wired through Settings → `RecordingSession.stop()`.
- Existing voice attachments from the unreleased build are migrated automatically (`VoiceMigration.runV2IfNeeded`).

User does the version bump and OTA deploy when they are ready (per repo convention; see `feedback_versioning_control.md`).
