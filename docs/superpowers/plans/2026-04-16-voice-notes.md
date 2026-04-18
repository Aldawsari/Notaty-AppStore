# Voice Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add voice note recording with automatic speech-to-text transcription and audio playback to Notaty.

**Architecture:** Extend the `Note` model with a `type` field (`.text`/`.voice`) and optional `audioFilename`. New `AudioRecorder`, `AudioPlayer`, and `SpeechTranscriber` classes handle recording, playback, and transcription. A new `VoiceNoteView` replaces the text editor for voice-type notes. Audio files are stored as `.m4a` in `~/Library/Application Support/Notaty/audio/`.

**Tech Stack:** Swift, AVFoundation (recording/playback), Speech framework (SFSpeechRecognizer), SwiftUI, macOS 13+

---

## File Structure

```
New files:
  Sources/Notaty/AudioRecorder.swift     — AVAudioRecorder wrapper, start/stop, save m4a
  Sources/Notaty/AudioPlayer.swift       — AVAudioPlayer wrapper, play/pause, time tracking
  Sources/Notaty/SpeechTranscriber.swift  — SFSpeechRecognizer wrapper, transcribe file to text
  Sources/Notaty/VoiceNoteView.swift      — Recording UI + player bar + transcription text

Modified files:
  Sources/Notaty/Note.swift              — Add NoteType enum, type + audioFilename fields
  Sources/Notaty/NotesStore.swift         — Add addVoiceNote(), delete audio on note delete, audio dir
  Sources/Notaty/NoteView.swift           — Branch on note.type, add mic button
  Sources/Notaty/NotatyRootView.swift     — Add mic button to TabBar
  Sources/Notaty/AppDelegate.swift        — Add newVoiceNote() action, menu items
  Sources/Notaty/NotatyMenuBuilder.swift  — Add "New Voice Note" to hamburger menu
```

---

### Task 1: Extend Note model

**Files:**
- Modify: `Sources/Notaty/Note.swift`

- [ ] **Step 1: Add NoteType enum and new fields**

Replace the entire contents of `Sources/Notaty/Note.swift` with:

```swift
import Foundation

enum NoteDirection: String, Codable {
    case auto, ltr, rtl
}

enum NoteType: String, Codable {
    case text
    case voice
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var direction: NoteDirection
    var type: NoteType
    var audioFilename: String?

    init(id: UUID = UUID(), title: String = "", text: String = "", direction: NoteDirection = .auto, type: NoteType = .text, audioFilename: String? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.direction = direction
        self.type = type
        self.audioFilename = audioFilename
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, direction, type, audioFilename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.text = try c.decode(String.self, forKey: .text)
        self.direction = try c.decodeIfPresent(NoteDirection.self, forKey: .direction) ?? .auto
        self.type = try c.decodeIfPresent(NoteType.self, forKey: .type) ?? .text
        self.audioFilename = try c.decodeIfPresent(String.self, forKey: .audioFilename)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/aldawsari/Documents/Lab/Notaty && swift build 2>&1 | tail -5
```

Expected: Build succeeds (existing code uses default `.text` type).

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/Note.swift
git commit -m "feat: add NoteType and audioFilename to Note model"
```

---

### Task 2: Update NotesStore for voice notes

**Files:**
- Modify: `Sources/Notaty/NotesStore.swift`

- [ ] **Step 1: Add audio directory management and addVoiceNote()**

In `NotesStore.swift`, add the audio directory URL after the existing `backupURL`:

```swift
static let audioDir: URL = {
    appSupportDir.appendingPathComponent("audio", isDirectory: true)
}()
```

Add `ensureAudioDir()` method:

```swift
func ensureAudioDir() {
    try? FileManager.default.createDirectory(
        at: Self.audioDir,
        withIntermediateDirectories: true
    )
}
```

Add `addVoiceNote()` method after the existing `addNote()`:

```swift
@discardableResult
func addVoiceNote() -> Note {
    let f = DateFormatter()
    f.dateFormat = "MMM d, HH:mm"
    let timestamp = f.string(from: Date())
    let id = UUID()
    let note = Note(
        id: id,
        title: "ملاحظة صوتية \(timestamp)",
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

- [ ] **Step 2: Update delete() to remove audio file**

Replace the existing `delete(id:)` method:

```swift
func delete(id: UUID) {
    guard let index = indexByID[id] else { return }
    let note = notes[index]
    // Delete audio file if this is a voice note
    if note.type == .voice, let filename = note.audioFilename {
        let audioURL = Self.audioDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: audioURL)
    }
    notes.remove(at: index)
    rebuildIndex()
    if selectedID == id {
        selectedID = notes.first?.id
    }
}
```

- [ ] **Step 3: Add audioURL helper**

Add a static helper to resolve audio file paths:

```swift
static func audioURL(for note: Note) -> URL? {
    guard let filename = note.audioFilename else { return nil }
    return audioDir.appendingPathComponent(filename)
}
```

- [ ] **Step 4: Build and verify**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/NotesStore.swift
git commit -m "feat: addVoiceNote(), audio dir management, delete audio on note delete"
```

---

### Task 3: AudioRecorder

**Files:**
- Create: `Sources/Notaty/AudioRecorder.swift`

- [ ] **Step 1: Create AudioRecorder.swift**

```swift
import AVFoundation
import Combine

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?

    func startRecording(to url: URL) {
        NotesStore.shared.ensureAudioDir()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            isRecording = true
            startTime = Date()
            elapsedTime = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        } catch {
            print("AudioRecorder: failed to start — \(error)")
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
            print("AudioRecorder: recording finished unsuccessfully")
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AudioRecorder.swift
git commit -m "feat: AudioRecorder — AVAudioRecorder wrapper for voice notes"
```

---

### Task 4: AudioPlayer

**Files:**
- Create: `Sources/Notaty/AudioPlayer.swift`

- [ ] **Step 1: Create AudioPlayer.swift**

```swift
import AVFoundation
import Combine

final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
        } catch {
            print("AudioPlayer: failed to load — \(error)")
        }
    }

    func play() {
        player?.play()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentTime = self.player?.currentTime ?? 0
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AudioPlayer.swift
git commit -m "feat: AudioPlayer — AVAudioPlayer wrapper with time tracking"
```

---

### Task 5: SpeechTranscriber

**Files:**
- Create: `Sources/Notaty/SpeechTranscriber.swift`

- [ ] **Step 1: Create SpeechTranscriber.swift**

```swift
import Speech

final class SpeechTranscriber {
    enum TranscribeError: Error {
        case notAvailable
        case notAuthorized
        case failed(String)
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    static func transcribe(audioURL: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TranscribeError.notAvailable
        }

        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            // Request permission synchronously via continuation
            let granted = await withCheckedContinuation { cont in
                requestPermission { granted in
                    cont.resume(returning: granted)
                }
            }
            if !granted {
                throw TranscribeError.notAuthorized
            }
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: TranscribeError.failed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/SpeechTranscriber.swift
git commit -m "feat: SpeechTranscriber — on-device speech-to-text via SFSpeechRecognizer"
```

---

### Task 6: VoiceNoteView

**Files:**
- Create: `Sources/Notaty/VoiceNoteView.swift`

- [ ] **Step 1: Create VoiceNoteView.swift**

```swift
import SwiftUI

struct VoiceNoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()
    @State private var isTranscribing = false

    private var note: Note? {
        store.note(for: noteID)
    }

    private var audioURL: URL? {
        guard let note else { return nil }
        return NotesStore.audioURL(for: note)
    }

    private var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var layoutDirection: LayoutDirection {
        let mode = note?.direction ?? .auto
        let text = note?.text ?? ""
        let direction = NoteTextEditor.resolveDirection(mode: mode, text: text)
        return direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            TextField("Untitled", text: store.titleBinding(for: noteID))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .environment(\.layoutDirection, layoutDirection)

            Divider()

            // Recording / Player bar
            if recorder.isRecording {
                recordingBar
            } else if hasAudio {
                playerBar
                    .onAppear {
                        if let url = audioURL {
                            player.load(url: url)
                        }
                    }
            } else {
                // No audio yet — show record prompt
                readyToRecordBar
            }

            // Transcribing indicator
            if isTranscribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("جاري التفريغ...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Transcription text (editable)
            NoteTextEditor(
                text: store.textBinding(for: noteID),
                directionMode: note?.direction ?? .auto
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Recording Bar

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(recorder.isRecording ? 1 : 0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: recorder.isRecording)

            Text("جاري التسجيل...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Text(formatTime(recorder.elapsedTime))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: { stopAndTranscribe() }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Player Bar

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                if player.isPlaying { player.pause() } else { player.play() }
            }) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: player.duration > 0
                            ? geo.size.width * (player.currentTime / player.duration)
                            : 0, height: 4)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard player.duration > 0 else { return }
                    let fraction = location.x / geo.size.width
                    player.seek(to: player.duration * fraction)
                }
            }
            .frame(height: 28)

            Text(formatTime(player.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Ready to Record

    private var readyToRecordBar: some View {
        HStack {
            Spacer()
            Button(action: { startRecording() }) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 20))
                    Text("ابدأ التسجيل")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func startRecording() {
        guard let url = audioURL else { return }
        recorder.startRecording(to: url)
    }

    private func stopAndTranscribe() {
        guard let _ = recorder.stopRecording() else { return }
        guard let url = audioURL else { return }

        // Reload player with the new audio
        player.load(url: url)

        // Start transcription
        isTranscribing = true
        Task {
            do {
                let text = try await SpeechTranscriber.transcribe(audioURL: url)
                await MainActor.run {
                    store.update(id: noteID) { $0.text = text }
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    isTranscribing = false
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/VoiceNoteView.swift
git commit -m "feat: VoiceNoteView — recording, playback, transcription UI"
```

---

### Task 7: Wire into NoteView and TabBar

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`
- Modify: `Sources/Notaty/NotatyRootView.swift`

- [ ] **Step 1: Update NoteView to branch on note type**

Replace the entire contents of `Sources/Notaty/NoteView.swift`:

```swift
import SwiftUI
import AppKit

struct NoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    private var note: Note? {
        store.notes.first(where: { $0.id == noteID })
    }

    private var layoutDirection: LayoutDirection {
        let mode = note?.direction ?? .auto
        let text = note?.text ?? ""
        let direction = NoteTextEditor.resolveDirection(mode: mode, text: text)
        return direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var body: some View {
        if note?.type == .voice {
            VoiceNoteView(noteID: noteID)
        } else {
            VStack(spacing: 0) {
                TextField("Untitled", text: store.titleBinding(for: noteID))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .environment(\.layoutDirection, layoutDirection)

                Divider()

                NoteTextEditor(
                    text: store.textBinding(for: noteID),
                    directionMode: note?.direction ?? .auto
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```

- [ ] **Step 2: Add mic button to TabBar in NotatyRootView**

In `Sources/Notaty/NotatyRootView.swift`, in the `TabBar` struct, add a mic button after the plus button and before the camera button. Change:

```swift
            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")

            Button(action: { (NSApp.delegate as? AppDelegate)?.startOCRCapture() }) {
```

To:

```swift
            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")

            Button(action: { (NSApp.delegate as? AppDelegate)?.newVoiceNote() }) {
                Image(systemName: "mic")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New voice note (⇧⌘N)")

            Button(action: { (NSApp.delegate as? AppDelegate)?.startOCRCapture() }) {
```

- [ ] **Step 3: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Note: This will fail until Task 8 adds the `newVoiceNote()` method to AppDelegate. That's expected.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NoteView.swift Sources/Notaty/NotatyRootView.swift
git commit -m "feat: branch NoteView on type, add mic button to TabBar"
```

---

### Task 8: AppDelegate, menus, and entitlements

**Files:**
- Modify: `Sources/Notaty/AppDelegate.swift`
- Modify: `Sources/Notaty/NotatyMenuBuilder.swift`

- [ ] **Step 1: Add newVoiceNote() to AppDelegate**

In `Sources/Notaty/AppDelegate.swift`, add this method after the existing `newNote()` method:

```swift
@objc func newVoiceNote() {
    NotesStore.shared.addVoiceNote()
    guard let window = windowController.window else { return }
    if !window.isVisible {
        NSApp.activate(ignoringOtherApps: true)
        positionUnderStatusItem(window)
        window.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: Add "New Voice Note" to the File menu in installMainMenu()**

In `installMainMenu()`, after the `newNoteItem` block, add:

```swift
let newVoiceItem = NSMenuItem(
    title: "New Voice Note",
    action: #selector(newVoiceNote),
    keyEquivalent: "n"
)
newVoiceItem.keyEquivalentModifierMask = [.command, .shift]
newVoiceItem.target = self
fileMenu.addItem(newVoiceItem)
```

- [ ] **Step 3: Add "New Voice Note" to the right-click context menu**

In `showContextMenu()`, after the existing "New Note" item, add:

```swift
let voiceItem = NSMenuItem(title: "New Voice Note", action: #selector(newVoiceNote), keyEquivalent: "")
voiceItem.target = self
menu.addItem(voiceItem)
```

- [ ] **Step 4: Add "New Voice Note" to hamburger menu**

In `Sources/Notaty/NotatyMenuBuilder.swift`, in `presentHamburgerMenu(anchoredTo:)`, add after the settings item and separator:

```swift
let voiceNoteItem = NSMenuItem(
    title: "New Voice Note",
    action: #selector(AppDelegate.newVoiceNote),
    keyEquivalent: ""
)
menu.addItem(voiceNoteItem)

menu.addItem(NSMenuItem.separator())
```

Insert this before the existing `saveItem` block.

- [ ] **Step 5: Add entitlements file**

Create `Sources/Notaty/Notaty.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

Note: The Speech framework permission (`NSSpeechRecognitionUsageDescription`) is requested at runtime via `SFSpeechRecognizer.requestAuthorization()`. The microphone entitlement is required for AVAudioRecorder. For an SPM-based app without an Info.plist, macOS will show the standard permission dialogs automatically when the APIs are first used.

- [ ] **Step 6: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Full build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/Notaty/AppDelegate.swift Sources/Notaty/NotatyMenuBuilder.swift Sources/Notaty/Notaty.entitlements
git commit -m "feat: newVoiceNote action, menu items, mic entitlement"
```

---

### Task 9: Manual integration test

- [ ] **Step 1: Build and run**

```bash
swift build && open .build/debug/Notaty.app 2>/dev/null || .build/debug/Notaty
```

- [ ] **Step 2: Test voice note creation**

1. Click the mic button in the tab bar → new voice note tab appears with "ابدأ التسجيل" button
2. Click "ابدأ التسجيل" → red recording indicator with timer
3. Speak for a few seconds, click stop → "جاري التفريغ..." appears
4. Transcribed text appears in the editor below the player bar
5. Click play button → audio plays back with progress bar
6. Edit the transcription text → changes persist
7. Close and reopen → voice note is still there with audio playback

- [ ] **Step 3: Test menu items**

1. File → New Voice Note (⇧⌘N) → creates voice note
2. Right-click status bar icon → "New Voice Note" option works
3. Hamburger menu → "New Voice Note" option works

- [ ] **Step 4: Test deletion**

1. Delete a voice note → audio file is removed from `~/Library/Application Support/Notaty/audio/`
2. Regular text notes still work as before

- [ ] **Step 5: Commit final state**

```bash
git add -A
git commit -m "feat: voice notes — complete implementation with recording, transcription, playback"
```
