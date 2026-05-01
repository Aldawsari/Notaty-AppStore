# Voice-as-Attachment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify voice notes into the regular note model. Audio recordings become `Attachment` records like any other file. Recording happens via an inline banner; no `VoiceNoteView`, no `note.type == .voice` branching.

**Architecture:** A `RecordingSession.shared` singleton coordinates the active recording (one at a time, globally). `AudioRecorder` gains real-time metering for the live waveform. A new `RecordingBanner` view observes the session and renders between the title row and attachment strip. Migration on launch moves existing `audioFilename`-bearing notes' files from `audioDir/` to `attachmentsDir/` and converts them to `Attachment` records.

**Tech Stack:** Swift / SwiftUI / AVFoundation (AudioRecorder + meterEnabled), Combine, the existing `SpeechTranscriber` and `Attachment`/`NotesStore`.

**Spec:** `docs/superpowers/specs/2026-05-01-voice-as-attachment-design.md`

**Scope:** No automated tests (Notaty has no test target). Validation via the spec's 14 acceptance criteria, walked manually.

---

## File Structure

| Path | Change |
|---|---|
| `Sources/Notaty/AudioRecorder.swift` | Modify: enable metering, publish `recentLevels: [Float]`, change save dir to `attachmentsDir` |
| `Sources/Notaty/RecordingSession.swift` | **New.** Singleton coordinator; wraps AudioRecorder, exposes `isActive`, `currentNoteID`, `start(in:)`, `stop()` |
| `Sources/Notaty/RecordingBanner.swift` | **New.** SwiftUI banner with pulse + timer + live waveform + Stop button |
| `Sources/Notaty/VoiceMigration.swift` | **New.** One-time migration of `audioFilename`-bearing notes to `Attachment` records |
| `Sources/Notaty/NoteView.swift` | Modify: drop `if note?.type == .voice` branch; insert `RecordingBanner(noteID:)` between title row and attachment strip |
| `Sources/Notaty/AttachmentChipView.swift` | Modify: add `.contextMenu` with audio-conditional items |
| `Sources/Notaty/AttachmentStripView.swift` | Modify: pass `onTranscribe` and `onShowInFinder` callbacks to chip; implement them |
| `Sources/Notaty/AppDelegate.swift` | Modify: run `VoiceMigration` on launch; replace `newVoiceNote()` with create-note-and-record flow |
| `Sources/Notaty/Settings.swift` | Modify: remove `autoTranscribe` property + key + init line |
| `Sources/Notaty/SettingsView.swift` | Modify: remove "Auto-transcribe" Toggle row |
| `Sources/Notaty/NotesStore.swift` | Modify: delete `addVoiceNote()` method; simplify `delete(id:)` cascade (audio files are now in attachments) |
| `Sources/Notaty/VoiceNoteView.swift` | **Delete** entire file |
| `CHANGELOG.md` | Append note about voice unification to Unreleased section |

---

## Task 1: AudioRecorder gains live metering

**Files:**
- Modify: `Sources/Notaty/AudioRecorder.swift`

- [ ] **Step 1: Replace the file contents**

```swift
import AVFoundation
import Combine

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    /// Most recent normalized amplitude samples (0...1), one per metering tick.
    /// The banner's live waveform reads this; capped at the most recent 40
    /// samples so memory stays bounded for long recordings.
    @Published var recentLevels: [Float] = []

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private static let levelWindowSize = 40
    private static let meteringInterval: TimeInterval = 0.05

    func startRecording(to url: URL) {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isRecording = true
            startTime = Date()
            elapsedTime = 0
            recentLevels = []
            timer = Timer.scheduledTimer(withTimeInterval: Self.meteringInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } catch {
            NSLog("AudioRecorder: failed to start — \(error)")
        }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        // averagePower returns dB, roughly -160 (silence) to 0 (full scale).
        // Normalize -60..0 → 0..1 so quiet rooms still produce visible bars.
        let dB = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (dB + 60) / 60))
        recentLevels.append(normalized)
        if recentLevels.count > Self.levelWindowSize {
            recentLevels.removeFirst(recentLevels.count - Self.levelWindowSize)
        }
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        isRecording = false
        return url
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            NSLog("AudioRecorder: recording finished unsuccessfully")
        }
    }
}
```

Notable changes from current:
- Removed `NotesStore.shared.ensureAudioDir()` call (the new directory is managed by `RecordingSession` instead, since recordings now go into `attachmentsDir`)
- Added `isMeteringEnabled = true`
- Added `recentLevels` published property + the metering tick logic
- Timer interval shortened from 0.5s to 0.05s (20Hz) for smoother waveform animation

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AudioRecorder.swift
git commit -m "feat: AudioRecorder publishes recentLevels for live waveform"
```

---

## Task 2: RecordingSession singleton

**Files:**
- Create: `Sources/Notaty/RecordingSession.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import Combine

/// Global coordinator for the in-progress voice recording. Only one recording
/// can be active across the whole app (the mic is a singleton resource).
/// Exposes `isActive` and `currentNoteID` so views can:
///   - disable all 🎤 buttons + ⇧⌘N while a recording is active
///   - render the banner only on the originating note
final class RecordingSession: ObservableObject {
    static let shared = RecordingSession()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentNoteID: UUID? = nil

    /// The underlying recorder. Banner observes this for elapsed time and
    /// recentLevels (live waveform).
    let recorder = AudioRecorder()

    private var cancellable: AnyCancellable?

    private init() {
        // Mirror the recorder's isRecording into our isActive so observers
        // outside this class don't need to reach into the recorder.
        cancellable = recorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.isActive = recording
                if !recording { self?.currentNoteID = nil }
            }
    }

    /// Start a new recording targeted at the given note. If a recording is
    /// already active, this is a no-op (the global lock prevents concurrent
    /// recordings, but defend the API anyway).
    func start(in noteID: UUID) {
        guard !isActive else { return }
        NotesStore.shared.ensureAttachmentsDir()
        let storedName = "\(UUID().uuidString).m4a"
        let url = NotesStore.attachmentsDir.appendingPathComponent(storedName)
        currentNoteID = noteID
        recorder.startRecording(to: url)
    }

    /// Stop the active recording. Finalizes the file, builds an Attachment
    /// record, and appends it to the originating note. Returns the new
    /// attachment's storedName on success, nil on failure.
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
            byteSize: size
        )
        NotesStore.shared.update(id: noteID) { $0.attachments.append(attachment) }
        return storedName
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/RecordingSession.swift
git commit -m "feat: RecordingSession singleton coordinator for global recording state"
```

---

## Task 3: RecordingBanner view

**Files:**
- Create: `Sources/Notaty/RecordingBanner.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

/// Slim red banner shown between the title row and the attachment strip while
/// a recording is active for the given note. Displays a pulsing dot, elapsed
/// timer, live amplitude waveform, and a Stop button. Renders nothing when
/// no recording is active or when this isn't the originating note.
struct RecordingBanner: View {
    let noteID: UUID
    @ObservedObject private var session = RecordingSession.shared
    @ObservedObject private var recorder = RecordingSession.shared.recorder

    var body: some View {
        if session.isActive, session.currentNoteID == noteID {
            content
        } else {
            EmptyView()
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            pulseDot
            Text(formattedElapsed)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundColor(.primary)
                .frame(minWidth: 32, alignment: .leading)
            waveform
                .frame(maxWidth: .infinity)
            stopButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 1.0, green: 0.96, blue: 0.96))
        .overlay(
            Rectangle()
                .fill(Color(red: 0.99, green: 0.79, blue: 0.79))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var pulseDot: some View {
        Circle()
            .fill(Color(red: 0.86, green: 0.15, blue: 0.15))
            .frame(width: 8, height: 8)
            // SwiftUI macOS 13: use .opacity animation for the pulse since
            // box-shadow keyframes aren't available cross-platform.
            .opacity(pulseOn ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseOn)
            .onAppear { pulseOn = true }
    }

    @State private var pulseOn = false

    private var waveform: some View {
        GeometryReader { geo in
            let levels = recorder.recentLevels
            let count = max(1, levels.count)
            let spacing: CGFloat = 1.5
            let availableWidth = geo.size.width
            let barWidth = max(1.5, (availableWidth - spacing * CGFloat(count - 1)) / CGFloat(40))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<levels.count, id: \.self) { i in
                    let amplitude = max(0.05, CGFloat(levels[i]))
                    Capsule()
                        .fill(Color(red: 0.86, green: 0.15, blue: 0.15))
                        .frame(width: barWidth, height: max(2, amplitude * geo.size.height))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
    }

    private var stopButton: some View {
        Button(action: { _ = session.stop() }) {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .heavy))
                Text("Stop")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(red: 0.86, green: 0.15, blue: 0.15))
            )
        }
        .buttonStyle(.plain)
        .help("Stop recording")
    }

    private var formattedElapsed: String {
        let total = Int(recorder.elapsedTime)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/RecordingBanner.swift
git commit -m "feat: RecordingBanner view with pulse, timer, live waveform, Stop"
```

---

## Task 4: Insert RecordingBanner into NoteView; drop the voice branch

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`

- [ ] **Step 1: Replace the file's body**

Open `Sources/Notaty/NoteView.swift`. Find:

```swift
    var body: some View {
        if note?.type == .voice {
            VoiceNoteView(noteID: noteID)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    TextField("Untitled", text: store.titleBinding(for: noteID))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))

                    Button(action: { AttachmentImporter.openPicker(targetNoteID: noteID) }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Attach file (⌥⌘A)")

                    if Settings.shared.voiceNotesEnabled {
                        Button(action: { (NSApp.delegate as? AppDelegate)?.newVoiceNote() }) {
                            Image(systemName: "mic")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("New voice note (⇧⌘N)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .environment(\.layoutDirection, layoutDirection)

                Divider()

                AttachmentStripView(noteID: noteID)

                NoteTextEditor(
                    text: store.textBinding(for: noteID),
                    directionMode: note?.direction ?? .auto,
                    noteID: noteID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
        }
    }
```

Replace the entire `var body: some View { ... }` with:

```swift
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Untitled", text: store.titleBinding(for: noteID))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))

                Button(action: { AttachmentImporter.openPicker(targetNoteID: noteID) }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Attach file (⌥⌘A)")

                if Settings.shared.voiceNotesEnabled {
                    Button(action: { (NSApp.delegate as? AppDelegate)?.newVoiceNote() }) {
                        Image(systemName: "mic")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("New voice note (⇧⌘N)")
                    .disabled(RecordingSession.shared.isActive)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .environment(\.layoutDirection, layoutDirection)

            Divider()

            RecordingBanner(noteID: noteID)

            AttachmentStripView(noteID: noteID)

            NoteTextEditor(
                text: store.textBinding(for: noteID),
                directionMode: note?.direction ?? .auto,
                noteID: noteID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
```

Key changes:
- Removed `if note?.type == .voice { VoiceNoteView(noteID: noteID) } else { ... }` — now always uses the unified layout
- Inserted `RecordingBanner(noteID: noteID)` between `Divider()` and `AttachmentStripView`
- The mic button now `.disabled(RecordingSession.shared.isActive)` (global lock visual)

Note: making mic button disabled-state reactive requires observing the session. The current pattern reads it imperatively, which won't trigger SwiftUI re-renders when isActive changes. We fix this in Task 5 (where we wire reactive observation).

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success. (May still see the imperatively-read disabled flag not updating on isActive changes — fixed in Task 5.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/NoteView.swift
git commit -m "feat: drop note.type voice branch; render RecordingBanner inline"
```

---

## Task 5: Reactive global lock on the mic button

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`

The `.disabled(RecordingSession.shared.isActive)` from Task 4 reads imperatively — SwiftUI won't re-render when `isActive` changes. Add an `@ObservedObject` so the disabled state binds reactively.

- [ ] **Step 1: Add the observed object**

Open `Sources/Notaty/NoteView.swift`. Find the existing properties at the top:

```swift
struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared
```

Add immediately after:

```swift
    @ObservedObject private var recordingSession = RecordingSession.shared
```

- [ ] **Step 2: Update the disabled binding to read from the observed object**

Find:

```swift
                    .help("New voice note (⇧⌘N)")
                    .disabled(RecordingSession.shared.isActive)
```

Replace with:

```swift
                    .help("New voice note (⇧⌘N)")
                    .disabled(recordingSession.isActive)
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NoteView.swift
git commit -m "fix: mic button disabled state observes RecordingSession reactively"
```

---

## Task 6: Wire 🎤 button to start recording

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`

The mic button currently calls `(NSApp.delegate as? AppDelegate)?.newVoiceNote()` which creates a new note. We need it to instead start recording in the **current** note.

- [ ] **Step 1: Change the mic button action**

Open `Sources/Notaty/NoteView.swift`. Find:

```swift
                if Settings.shared.voiceNotesEnabled {
                    Button(action: { (NSApp.delegate as? AppDelegate)?.newVoiceNote() }) {
                        Image(systemName: "mic")
```

Replace with:

```swift
                if Settings.shared.voiceNotesEnabled {
                    Button(action: { RecordingSession.shared.start(in: noteID) }) {
                        Image(systemName: "mic")
```

(Just the action closure changes; everything else stays.)

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Smoke test**

Run: `bash run-debug.sh`. Click 🎤 in any text note's title row. The banner should appear with a pulsing dot, ticking timer, and live waveform that responds to mic input. Click Stop. The banner should disappear and an M4A chip should land in the strip.

If the banner doesn't appear, check that `RecordingSession.shared.start` is being called and `currentNoteID` matches `noteID` in the banner.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NoteView.swift
git commit -m "feat: 🎤 in title row starts recording in the current note"
```

---

## Task 7: ⇧⌘N creates new note + starts recording

**Files:**
- Modify: `Sources/Notaty/AppDelegate.swift`

The existing `newVoiceNote()` method calls `NotesStore.shared.addVoiceNote()`. Replace its body to:
1. Create a regular note (no `type: .voice`) with title `"Recording {timestamp}"`
2. Select it
3. Start recording

- [ ] **Step 1: Replace `newVoiceNote()` body**

Open `Sources/Notaty/AppDelegate.swift`. Find:

```swift
    @objc func newVoiceNote() {
        NotesStore.shared.addVoiceNote()
```

(The full method may have additional logic — show window, etc. Read the surrounding code before editing.)

Replace the method body's note-creation step with:

```swift
    @objc func newVoiceNote() {
        guard Settings.shared.voiceNotesEnabled else { return }
        guard !RecordingSession.shared.isActive else { return }

        // Create a regular note. No type=.voice. Title is timestamp-based.
        let newNote = NotesStore.shared.addNote()
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        let timestamp = f.string(from: Date())
        NotesStore.shared.update(id: newNote.id) {
            $0.title = "Recording \(timestamp)"
        }
        NotesStore.shared.selectedID = newNote.id

        // If the existing method had window-show logic, preserve it here.
        // Then start recording in the new note.
        DispatchQueue.main.async {
            RecordingSession.shared.start(in: newNote.id)
        }
```

(Note: the closing brace of the method is unchanged. Only the body before the brace is modified. Keep any post-creation logic — show window, etc. — that already existed.)

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success. If `addVoiceNote()` no longer exists in NotesStore, that's expected — Task 9 deletes it.

If the build fails because `addVoiceNote()` is referenced elsewhere, find it and apply the same replacement (regular addNote + RecordingSession.start).

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AppDelegate.swift
git commit -m "feat: ⇧⌘N creates regular note + starts recording (no more type=.voice)"
```

---

## Task 8: Voice migration on launch

**Files:**
- Create: `Sources/Notaty/VoiceMigration.swift`
- Modify: `Sources/Notaty/AppDelegate.swift`

- [ ] **Step 1: Create `VoiceMigration.swift`**

```swift
import Foundation

/// One-time migration: convert voice notes (`audioFilename` set) into regular
/// notes with the audio file attached as an `Attachment`. Runs silently on
/// app launch the first time after the upgrade. Tracked by a UserDefaults
/// flag so it never re-runs.
enum VoiceMigration {
    private static let migrationKey = "didMigrateVoiceToAttachments"

    /// Call once on launch, after `NotesStore.shared` has loaded.
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let store = NotesStore.shared
        var migratedCount = 0

        for note in store.notes {
            guard let filename = note.audioFilename else { continue }
            let oldURL = NotesStore.audioDir.appendingPathComponent(filename)
            let newURL = NotesStore.attachmentsDir.appendingPathComponent(filename)

            // Make sure the destination dir exists.
            store.ensureAttachmentsDir()

            if FileManager.default.fileExists(atPath: oldURL.path) {
                // Move the file. moveItem fails if dest exists; remove it first.
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.removeItem(at: newURL)
                }
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                } catch {
                    // Fallback: copy then delete the source.
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
                    byteSize: size
                )
                store.update(id: note.id) {
                    $0.attachments.append(attachment)
                    $0.audioFilename = nil
                }
                migratedCount += 1
            } else {
                // Audio file is missing on disk. Just clear the dangling reference.
                store.update(id: note.id) { $0.audioFilename = nil }
            }
        }

        if migratedCount > 0 {
            NSLog("VoiceMigration: converted \(migratedCount) voice notes to regular notes with audio attachments")
        }
    }
}
```

- [ ] **Step 2: Call from `applicationDidFinishLaunching`**

Open `Sources/Notaty/AppDelegate.swift`. Find `applicationDidFinishLaunching`. Locate the existing line:

```swift
        NotesStore.shared.cleanupOrphanedAttachmentFiles()
```

Add immediately BEFORE that line:

```swift
        // Migrate legacy voice notes (audioFilename → attachments[]) before
        // the orphan sweep runs, so migrated files are referenced when we
        // check for orphans.
        VoiceMigration.runIfNeeded()
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 4: Smoke test (with caution!)**

If you have voice notes in your real data, this is the moment of truth.

```bash
# OPTIONAL — back up notes first
cp ~/Library/Application\ Support/Notaty/notes.json ~/notes-pre-migration.json
ls -la ~/Library/Application\ Support/Notaty/audio/

bash run-debug.sh
```

Open the app. Voice notes should now display in the unified layout with their audio file as a chip in the attachment strip. Title and body preserved.

```bash
# Verify post-migration state
ls -la ~/Library/Application\ Support/Notaty/audio/
ls -la ~/Library/Application\ Support/Notaty/attachments/
```

The audio dir should now be empty (or contain leftover unrelated files if any). The attachments dir should now contain the migrated `.m4a` files.

If any voice note didn't migrate, check console logs (`NSLog` from VoiceMigration) and the UserDefaults flag (`defaults read com.aldawsari.Notaty didMigrateVoiceToAttachments`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/VoiceMigration.swift Sources/Notaty/AppDelegate.swift
git commit -m "feat: migrate voice notes to attachments[] on first launch"
```

---

## Task 9: Drop `addVoiceNote` and simplify `delete` cascade in NotesStore

**Files:**
- Modify: `Sources/Notaty/NotesStore.swift`

- [ ] **Step 1: Delete `addVoiceNote()`**

Find this method in `Sources/Notaty/NotesStore.swift`:

```swift
    @discardableResult
    func addVoiceNote() -> Note {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        let timestamp = f.string(from: Date())
        let id = UUID()
        let note = Note(
            id: id,
            title: "Voice Note \(timestamp)",
            text: "",
            type: .voice,
            audioFilename: "\(id.uuidString).m4a"
        )
        notes.append(note)
        indexByID[note.id] = notes.count - 1
        selectedID = note.id
        return note
    }
```

Delete the entire method.

- [ ] **Step 2: Simplify the `delete(id:)` cascade**

Find:

```swift
        // Cascade: move the audio sidecar (voice notes) and all attachment
        // sidecars (text notes can have any number) to the Trash so the user
        // can restore them from Finder if needed.
        if note.type == .voice, let filename = note.audioFilename {
            let audioURL = Self.audioDir.appendingPathComponent(filename)
            try? FileManager.default.trashItem(at: audioURL, resultingItemURL: nil)
        }
        for attachment in note.attachments {
            let url = Self.attachmentURL(for: attachment)
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
```

Replace with:

```swift
        // Cascade: move all attachment sidecar files to the Trash. Audio
        // files are now in attachments[] (post voice migration), so we no
        // longer need to special-case voice.
        for attachment in note.attachments {
            let url = Self.attachmentURL(for: attachment)
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
```

- [ ] **Step 3: Keep `audioURL(for:)` and `audioDir` for now**

The `static let audioDir` and `static func audioURL(for note: Note) -> URL?` may still be referenced by code we haven't removed yet (VoiceNoteView). Leave them for now; they're cleaned up in Task 10.

- [ ] **Step 4: Build to verify**

Run: `swift build`

If build fails because `addVoiceNote()` is called from somewhere we missed, find and replace those call sites with the create-note-and-record flow used in Task 7.

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/NotesStore.swift
git commit -m "refactor: drop NotesStore.addVoiceNote; simplify delete cascade"
```

---

## Task 10: Delete `VoiceNoteView.swift` and its dependencies

**Files:**
- Delete: `Sources/Notaty/VoiceNoteView.swift`
- Modify: `Sources/Notaty/NotesStore.swift` (cleanup)

- [ ] **Step 1: Delete the file**

```bash
rm /Users/aldawsari/Documents/Lab/Notaty/Sources/Notaty/VoiceNoteView.swift
```

- [ ] **Step 2: Search for any remaining references**

```bash
grep -rn "VoiceNoteView\|audioURL(for:)\|audioDir" /Users/aldawsari/Documents/Lab/Notaty/Sources/Notaty/
```

For each match (other than the definitions themselves):
- If a reference is genuinely unused (e.g., a test that was for VoiceNoteView): remove it.
- If it's still load-bearing for some flow we missed: STOP and report. Do not silently remove things that are still in use.

- [ ] **Step 3: Remove `audioDir` and `audioURL(for:)` from NotesStore if no longer referenced**

If grep showed no remaining users for these (other than VoiceMigration which uses `audioDir` to find old files), they can be deleted. Find in `NotesStore.swift`:

```swift
    static let audioDir: URL = {
        appSupportDir.appendingPathComponent("audio", isDirectory: true)
    }()
```

Keep this — `VoiceMigration` references it. The directory itself stays empty after migration but the URL helper is still useful for the migration code.

```swift
    static func audioURL(for note: Note) -> URL? {
        guard let filename = note.audioFilename else { return nil }
        return audioDir.appendingPathComponent(filename)
    }
```

If no callers remain, delete this method. (Run grep again to confirm before deleting.)

```swift
    func ensureAudioDir() {
```

Same — if no callers, delete. (`AudioRecorder` no longer calls it because Task 1 removed that call.)

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: compile success. If not, fix the remaining references reported by the compiler.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/Notaty/
git commit -m "refactor: delete VoiceNoteView; clean up audioURL/ensureAudioDir if unused"
```

---

## Task 11: Remove `autoTranscribe` from Settings + SettingsView

**Files:**
- Modify: `Sources/Notaty/Settings.swift`
- Modify: `Sources/Notaty/SettingsView.swift`

- [ ] **Step 1: Remove from `Settings.swift`**

Find and delete:

```swift
    @Published var autoTranscribe: Bool {
        didSet { UserDefaults.standard.set(autoTranscribe, forKey: Self.autoTranscribeKey) }
    }
```

```swift
    private static let autoTranscribeKey = "autoTranscribe"
```

```swift
        self.autoTranscribe = UserDefaults.standard.object(forKey: Self.autoTranscribeKey) != nil
            ? UserDefaults.standard.bool(forKey: Self.autoTranscribeKey)
            : false
```

(Three places: property, key constant, init.)

- [ ] **Step 2: Remove from `SettingsView.swift`**

Find the Toggle row referencing `$settings.autoTranscribe` (likely in the Voice Notes section). It looks like:

```swift
                    if settings.voiceNotesEnabled {
                        Divider()

                        Toggle(isOn: $settings.autoTranscribe) {
                            rowLabel("Auto-transcribe on stop")
                        }
                        .toggleStyle(.switch)
                    }
```

Or some variation. Remove the entire Toggle block (and the surrounding Divider if it was added solely for this toggle). Keep the surrounding Voice Notes section structure intact; only the autoTranscribe row goes.

- [ ] **Step 3: Search for any other references**

```bash
grep -rn "autoTranscribe" /Users/aldawsari/Documents/Lab/Notaty/Sources/Notaty/
```

If anything else references it, that code was depending on auto-transcribe firing — and since we no longer auto-transcribe, those code paths should be removed (transcription now goes through the right-click menu path in Tasks 12–13).

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/Settings.swift Sources/Notaty/SettingsView.swift
git commit -m "refactor: remove Settings.autoTranscribe (transcription is now manual)"
```

---

## Task 12: Right-click context menu on audio chips

**Files:**
- Modify: `Sources/Notaty/AttachmentChipView.swift`
- Modify: `Sources/Notaty/AttachmentStripView.swift`

- [ ] **Step 1: Add context-menu callbacks to `AttachmentChipView`**

Open `Sources/Notaty/AttachmentChipView.swift`. Find the existing properties:

```swift
struct AttachmentChipView: View {
    let attachment: Attachment
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRemove: () -> Void
```

Add two more callbacks:

```swift
struct AttachmentChipView: View {
    let attachment: Attachment
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onTranscribe: () -> Void
    let onShowInFinder: () -> Void
```

- [ ] **Step 2: Add the context menu modifier to the chip's body**

Find the OUTER HStack at the end of the chip's `body`. After the existing `.shadow(...)` line (or wherever the last modifier is on the outer chip view), add:

```swift
        .contextMenu {
            Button("Play") { onOpen() }
            if attachment.isAudio {
                Button("Transcribe & Insert") { onTranscribe() }
            }
            Button("Show in Finder") { onShowInFinder() }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
```

- [ ] **Step 3: Add `isAudio` to `Attachment`**

Open `Sources/Notaty/Attachment.swift`. After the existing `isImage` computed property, add:

```swift
    /// True if `fileExtension` is one of the audio types the app can
    /// transcribe and play inline.
    var isAudio: Bool {
        ["m4a", "mp3", "wav", "aiff"].contains(fileExtension)
    }
```

- [ ] **Step 4: Wire the new callbacks in `AttachmentStripView`**

Open `Sources/Notaty/AttachmentStripView.swift`. Find the `AttachmentChipView(...)` constructor call. Add the two new callbacks. The full call should now look like:

```swift
                AttachmentChipView(
                    attachment: attachment,
                    isSelected: selectedIDs.contains(attachment.id),
                    onSelect: {
                        handleClick(on: attachment.id)
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    },
                    onOpen: {
                        NSWorkspace.shared.open(NotesStore.attachmentURL(for: attachment))
                    },
                    onRemove: {
                        confirmAndRemove([attachment.id])
                    },
                    onTranscribe: {
                        transcribeAndInsert(attachment)
                    },
                    onShowInFinder: {
                        NSWorkspace.shared.activateFileViewerSelecting([NotesStore.attachmentURL(for: attachment)])
                    }
                )
```

- [ ] **Step 5: Add the `transcribeAndInsert` method to AttachmentStripView**

In the same file, add this method (alongside the other private helpers):

```swift
    @MainActor
    private func transcribeAndInsert(_ attachment: Attachment) {
        let url = NotesStore.attachmentURL(for: attachment)
        Task {
            do {
                let transcript = try await SpeechTranscriber.transcribe(audioURL: url)
                await MainActor.run {
                    let separator = "\n\n---\n"
                    var current = store.note(for: noteID)?.text ?? ""
                    if !current.isEmpty { current += separator }
                    current += transcript
                    store.update(id: noteID) { $0.text = current }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't transcribe"
                    alert.informativeText = "\(error)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
```

- [ ] **Step 6: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 7: Smoke test**

`bash run-debug.sh`. Right-click an audio chip — context menu should show Play / Transcribe & Insert / Show in Finder / Remove. Right-click a non-audio chip (PDF, image) — Transcribe should NOT appear. Click "Show in Finder" — Finder opens with the file selected. Click "Transcribe & Insert" — transcript appended to body after a few seconds (or alert if it fails).

- [ ] **Step 8: Commit**

```bash
git add Sources/Notaty/AttachmentChipView.swift Sources/Notaty/AttachmentStripView.swift Sources/Notaty/Attachment.swift
git commit -m "feat: right-click context menu on chips; Transcribe & Insert for audio"
```

---

## Task 13: Full acceptance smoke test

This task has no code; it's a manual verification pass against the spec's 14 acceptance criteria.

- [ ] **Step 1: Release build**

Run: `swift build -c release`
Expected: clean build.

- [ ] **Step 2: Production .app**

```bash
rm -rf dist/Notaty-1.0.app && bash build.sh
open dist/Notaty-1.0.app
```

- [ ] **Step 3: Walk the spec's 14 acceptance criteria**

From `docs/superpowers/specs/2026-05-01-voice-as-attachment-design.md` § Acceptance criteria:

1. Existing v1.2.1 text notes load correctly
2. Existing voice notes (with `audioFilename`) loaded and converted into regular notes with M4A attachment chips
3. Migration ran once on first launch; UserDefaults flag prevents re-run
4. Click 🎤 in title row → red banner appears → live waveform → click Stop → chip lands
5. ⇧⌘N → new note titled "Recording {timestamp}" → recording auto-starts
6. Right-click audio chip → context menu shows Play / Transcribe & Insert / Show in Finder / Remove
7. "Transcribe & Insert" appends transcript to body with separator
8. "Show in Finder" reveals the file
9. While recording: every 🎤 in any tab is disabled; ⇧⌘N is disabled
10. Switching tabs during recording: recording continues; banner only on originating tab
11. Esc / red close button while recording → recording stops cleanly, chip lands
12. Settings → Voice Notes: only "Enable Voice Notes" remains; Auto-transcribe gone
13. No `note.type == .voice` branching in any new code path
14. `swift build -c release` and `bash build.sh` succeed

If any fails, the relevant earlier task has a bug.

---

## Task 14: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append to the existing Unreleased section**

Open `CHANGELOG.md`. The Unreleased section already exists from the attachments + pin features. Append a new bullet directly under it:

```markdown
- Voice notes are unified with regular notes. Recording happens via an inline banner — click 🎤 in any note's title row, or press ⇧⌘N to create a new note that auto-starts recording. Audio recordings appear as M4A attachment chips alongside any other files in the note. Right-click an audio chip to "Transcribe & Insert" the transcript into the note body, "Show in Finder", play, or remove. Existing voice notes from prior versions migrate automatically on first launch — title and body are preserved, audio becomes an attachment. The previous "auto-transcribe on stop" behavior is gone in favor of the explicit right-click action.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG note for voice-as-attachment unification"
```

---

## Self-review — coverage against the spec

| Spec section | Covered by |
|---|---|
| §1 Data model — `type` and `audioFilename` decodable but unused | Task 7 (new note creation skips them) + Task 8 (migration clears audioFilename) + Task 9 (no more addVoiceNote) |
| §2 Storage — recordings to `attachmentsDir` | Task 1 (recorder config) + Task 2 (RecordingSession URL construction) |
| §3 Recorder UX — banner with pulse/timer/waveform/stop | Task 3 (banner view) + Task 4 (insert into NoteView) |
| §3 State machine — Idle / Recording / Stopping | Task 2 (RecordingSession) + Task 6 (start) + Task 3 (Stop button) |
| §3 Esc / window-close auto-stop | Inherited from `RecordingSession.stop()` being safely callable; window/Esc handlers can call it during cleanup. Verified in Task 13 step 11. |
| §4 Transcription manual via context menu | Task 12 |
| §4 Right-click items: Play / Transcribe & Insert / Show in Finder / Remove | Task 12 |
| §4 Settings.autoTranscribe removed | Task 11 |
| §5 Migration: silent, one-time, file move | Task 8 |
| §5 Missing audio file: drop reference | Task 8 |
| §6 ⇧⌘N → create + record | Task 7 |
| §6 🎤 → record in current note | Task 6 |
| §6 Global recording lock | Task 5 (reactive observed object) + Task 7 (early return on isActive) |
| §7 Code that goes away — VoiceNoteView | Task 10 |
| §7 Code that goes away — addVoiceNote | Task 9 |
| §8 New code — RecordingSession, RecordingBanner, VoiceMigration | Tasks 2, 3, 8 |
| §9 NoteView modifications | Tasks 4–6 |
| §10 Acceptance criteria | Task 13 |
| §11 No automated tests | Honored throughout (no test target additions) |
| §12 Risks acknowledged | WaveformView replaced with custom live waveform in Task 3; metering enabled in Task 1; migration ordering documented in Task 8 |
| CHANGELOG | Task 14 |

No spec section is uncovered. No "TBD/TODO" placeholders. Type/method names consistent (`RecordingSession.shared`, `start(in:)`, `stop()`, `isActive`, `currentNoteID`, `recorder.recentLevels`).

---

**End of plan.**
