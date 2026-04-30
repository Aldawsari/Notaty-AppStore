# Notaty Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add file attachments to text notes — drop, paste, or click a paperclip; chips render between title and body; click previews via Quick Look; double-click opens; drag out copies to Finder.

**Architecture:** Sidecar pattern mirroring voice notes — metadata in `Note.attachments` (JSON), blobs as files at `~/Library/Application Support/Notaty/attachments/<UUID>.<ext>`. UI is SwiftUI; the paperclip slots into the existing custom tab strip in `NotatyRootView.swift`.

**Tech Stack:** Swift / SwiftUI / AppKit, NSOpenPanel, NSPasteboard, QLPreviewPanel, NSWorkspace, NSItemProvider, /usr/bin/ditto for zip integration.

**Spec:** `docs/superpowers/specs/2026-04-30-attachments-design.md`

**Scope reminders:**
- Text notes only (voice notes deferred — tracked in user memory)
- English-only (Notaty has no l10n today)
- No automated tests (Notaty has no test target today)
- Manual verification at each task; full smoke test before CHANGELOG

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `Sources/Notaty/Attachment.swift` | The `Attachment` struct (Codable model) |
| `Sources/Notaty/AttachmentChipView.swift` | The chip view: thumbnail + name + size + hover-× |
| `Sources/Notaty/AttachmentStripView.swift` | The wrapping strip that renders chips for one note |
| `Sources/Notaty/AttachmentImporter.swift` | Static helpers: open file picker, accept dropped/pasted URLs |
| `Sources/Notaty/AttachmentPreviewCoordinator.swift` | `QLPreviewPanelDataSource` wrapper for Quick Look |

**Modified files:**

| Path | What changes |
|---|---|
| `Sources/Notaty/Note.swift` | Add `attachments: [Attachment]` field, backward-compat decoding |
| `Sources/Notaty/NotesStore.swift` | Add `attachmentsDir`, `addAttachment`, `removeAttachment`, cascade delete, orphan sweep |
| `Sources/Notaty/NotatyRootView.swift` | Insert paperclip button in `TabBar` |
| `Sources/Notaty/NoteView.swift` | Insert `AttachmentStripView` + `.onDrop` on outer `VStack` |
| `Sources/Notaty/NoteTextEditor.swift` | Subclass `NSTextView` to intercept paste of file URLs |
| `Sources/Notaty/AppDelegate.swift` | Add "Attach File…" to the File menu (⌥⌘A), accept QLPreviewPanel control, run orphan sweep on launch |
| `Sources/Notaty/NotatyActions.swift` | Add `attachToSelectedNote()`; extend `exportAllNotes` / `importNotes` for attachments |
| `CHANGELOG.md` | Add Unreleased section with feature note |

---

## Phase 1 · Storage foundation

### Task 1: Create the `Attachment` struct

**Files:**
- Create: `Sources/Notaty/Attachment.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String
    var storedName: String
    var byteSize: Int64
    var addedAt: Date

    init(id: UUID = UUID(), originalName: String, storedName: String, byteSize: Int64, addedAt: Date = Date()) {
        self.id = id
        self.originalName = originalName
        self.storedName = storedName
        self.byteSize = byteSize
        self.addedAt = addedAt
    }

    /// File extension without the dot, lowercased, derived from `originalName`.
    var fileExtension: String {
        (originalName as NSString).pathExtension.lowercased()
    }

    /// True if `fileExtension` is one of the image types we render thumbnails for.
    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp"].contains(fileExtension)
    }

    /// 3-character display label for non-image type icons (e.g. "PDF", "DOC").
    var typeLabel: String {
        let ext = fileExtension
        if ext.isEmpty { return "FILE" }
        return String(ext.prefix(4)).uppercased()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/Attachment.swift
git commit -m "feat: Attachment struct (Codable model)"
```

---

### Task 2: Add `attachments` field to `Note` with backward-compatible decoding

**Files:**
- Modify: `Sources/Notaty/Note.swift`

- [ ] **Step 1: Replace the file contents**

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
    var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        title: String = "",
        text: String = "",
        direction: NoteDirection = .auto,
        type: NoteType = .text,
        audioFilename: String? = nil,
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.direction = direction
        self.type = type
        self.audioFilename = audioFilename
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, direction, type, audioFilename, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.text = try c.decode(String.self, forKey: .text)
        self.direction = try c.decodeIfPresent(NoteDirection.self, forKey: .direction) ?? .auto
        self.type = try c.decodeIfPresent(NoteType.self, forKey: .type) ?? .text
        self.audioFilename = try c.decodeIfPresent(String.self, forKey: .audioFilename)
        self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Smoke-test backward compatibility manually**

Build & launch the debug app:
```
bash run-debug.sh
```
Open it; verify your existing notes load and display correctly (the `attachments` field should be empty arrays for old notes; nothing visible should change yet).

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/Note.swift
git commit -m "feat: add attachments field to Note with backward-compat decoding"
```

---

### Task 3: Add `attachmentsDir` and `addAttachment` to `NotesStore`

**Files:**
- Modify: `Sources/Notaty/NotesStore.swift`

- [ ] **Step 1: Add the directory URL alongside `audioDir`**

Locate this block (around line 27):
```swift
    static let audioDir: URL = {
        appSupportDir.appendingPathComponent("audio", isDirectory: true)
    }()
```

Add immediately after:
```swift
    static let attachmentsDir: URL = {
        appSupportDir.appendingPathComponent("attachments", isDirectory: true)
    }()
```

- [ ] **Step 2: Add the `ensureAttachmentsDir` helper**

Locate `func ensureAudioDir()` near the bottom of the file. Add immediately after it:

```swift
    func ensureAttachmentsDir() {
        try? FileManager.default.createDirectory(
            at: Self.attachmentsDir,
            withIntermediateDirectories: true
        )
    }
```

- [ ] **Step 3: Call `ensureAttachmentsDir` from `init`**

In the `private init()`, just after `ensureAppSupportDir()`, add:
```swift
        ensureAttachmentsDir()
```

- [ ] **Step 4: Add the `attachmentURL(for:)` static helper**

Locate `static func audioURL(for note: Note) -> URL?`. Add immediately after:

```swift
    static func attachmentURL(for attachment: Attachment) -> URL {
        attachmentsDir.appendingPathComponent(attachment.storedName)
    }
```

- [ ] **Step 5: Add the `addAttachments` method**

Add this method to `NotesStore` (near the existing `update` / `delete` methods):

```swift
    /// Copy each source URL into `attachmentsDir` under a UUID-based name and
    /// append a corresponding `Attachment` to the note's array. Returns the
    /// number of files successfully attached. Files that fail to copy are
    /// silently skipped (the caller handles the error UI per file).
    @discardableResult
    func addAttachments(to noteID: UUID, from sourceURLs: [URL]) -> Int {
        guard !sourceURLs.isEmpty, indexByID[noteID] != nil else { return 0 }
        ensureAttachmentsDir()

        var added: [Attachment] = []
        for source in sourceURLs {
            let originalName = source.lastPathComponent
            let ext = source.pathExtension
            let storedName = ext.isEmpty
                ? UUID().uuidString
                : "\(UUID().uuidString).\(ext)"
            let dest = Self.attachmentsDir.appendingPathComponent(storedName)

            do {
                try FileManager.default.copyItem(at: source, to: dest)
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                added.append(Attachment(
                    originalName: originalName,
                    storedName: storedName,
                    byteSize: size
                ))
            } catch {
                NSLog("Notaty: failed to attach \(originalName): \(error)")
                continue
            }
        }

        guard !added.isEmpty else { return 0 }
        update(id: noteID) { $0.attachments.append(contentsOf: added) }
        return added.count
    }
```

- [ ] **Step 6: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 7: Commit**

```bash
git add Sources/Notaty/NotesStore.swift
git commit -m "feat: NotesStore.addAttachments with sidecar file storage"
```

---

### Task 4: Add `removeAttachment` and cascade delete

**Files:**
- Modify: `Sources/Notaty/NotesStore.swift`

- [ ] **Step 1: Add `removeAttachment` next to `addAttachments`**

```swift
    /// Remove a single attachment from a note: deletes the sidecar file from
    /// disk, then drops the metadata from the note's array.
    func removeAttachment(_ attachmentID: UUID, from noteID: UUID) {
        guard let note = self.note(for: noteID),
              let target = note.attachments.first(where: { $0.id == attachmentID })
        else { return }

        let url = Self.attachmentURL(for: target)
        try? FileManager.default.removeItem(at: url)

        update(id: noteID) {
            $0.attachments.removeAll { $0.id == attachmentID }
        }
    }
```

- [ ] **Step 2: Cascade attachment deletion when a note is deleted**

Find the existing `delete(id:)` method:
```swift
    func delete(id: UUID) {
        guard let index = indexByID[id] else { return }
        let note = notes[index]
        if note.type == .voice, let filename = note.audioFilename {
            let audioURL = Self.audioDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: audioURL)
        }
        notes.remove(at: index)
        ...
    }
```

Replace the existing voice-only cleanup block with:
```swift
        // Cascade: remove the audio sidecar (voice notes) and all attachment
        // sidecars (text notes can have any number).
        if note.type == .voice, let filename = note.audioFilename {
            let audioURL = Self.audioDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: audioURL)
        }
        for attachment in note.attachments {
            let url = Self.attachmentURL(for: attachment)
            try? FileManager.default.removeItem(at: url)
        }
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NotesStore.swift
git commit -m "feat: NotesStore.removeAttachment + cascade delete on note deletion"
```

---

### Task 5: Add orphan-file sweep on launch

**Files:**
- Modify: `Sources/Notaty/NotesStore.swift`
- Modify: `Sources/Notaty/AppDelegate.swift`

- [ ] **Step 1: Add `cleanupOrphanedAttachmentFiles` to `NotesStore`**

```swift
    /// Sweep `attachmentsDir` and remove any file not referenced by any note's
    /// `attachments` array. Called once on launch.
    func cleanupOrphanedAttachmentFiles() {
        let referenced = Set(notes.flatMap { $0.attachments.map(\.storedName) })
        let dir = Self.attachmentsDir
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }

        for entry in entries where !referenced.contains(entry.lastPathComponent) {
            try? FileManager.default.removeItem(at: entry)
        }
    }
```

- [ ] **Step 2: Call it from `applicationDidFinishLaunching`**

Open `Sources/Notaty/AppDelegate.swift` and find `applicationDidFinishLaunching`. After the existing setup calls (window, store loading, etc.), add:

```swift
        // Run once on launch: drop any attachment file no longer referenced
        // by a note's metadata.
        NotesStore.shared.cleanupOrphanedAttachmentFiles()
```

- [ ] **Step 3: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`
Manually verify: app launches, no crash, no console errors related to `attachments/`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NotesStore.swift Sources/Notaty/AppDelegate.swift
git commit -m "feat: orphan attachment sweep on launch"
```

---

## Phase 2 · UI rendering

### Task 6: Create `AttachmentChipView` (type-icon thumbnails first; image thumbnails in Task 7)

**Files:**
- Create: `Sources/Notaty/AttachmentChipView.swift`

- [ ] **Step 1: Create the file with the chip layout**

```swift
import SwiftUI
import AppKit

struct AttachmentChipView: View {
    let attachment: Attachment
    let onRemove: () -> Void
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.originalName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formattedSize)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(2)
                }
                .buttonStyle(.plain)
                .help("Remove attachment")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .gesture(
            // Single click → preview, double click → open. SwiftUI's
            // .onTapGesture(count: 2) does not fire single-click, so we use
            // count: 1 with a delay ramp implemented in the wrapper below.
            TapGesture(count: 2).onEnded { onDoubleClick() }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                // Defer slightly so a quick double-tap doesn't fire single first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    if !isDoubleTapPending() { onSingleClick() }
                }
            }
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if attachment.isImage {
            // Image thumbnail loading is implemented in Task 7. Until then,
            // fall through to the type-icon thumbnail.
            typeIcon
        } else {
            typeIcon
        }
    }

    private var typeIcon: some View {
        ZStack {
            Rectangle()
                .fill(typeColor)
            Text(attachment.typeLabel)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        }
    }

    private var typeColor: Color {
        switch attachment.fileExtension {
        case "pdf":               return Color(red: 185/255, green: 28/255, blue: 28/255)
        case "doc", "docx", "rtf": return Color(red: 30/255,  green: 64/255, blue: 175/255)
        case "zip", "tar", "gz":  return Color(red: 22/255,  green: 101/255, blue: 52/255)
        case "m4a", "mp3", "wav", "aiff": return Color(red: 124/255, green: 58/255, blue: 237/255)
        case "mp4", "mov":        return Color(red: 234/255, green: 88/255, blue: 12/255)
        default:                  return Color(NSColor.systemGray)
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file)
    }

    /// Heuristic — track an ad-hoc "double tap pending" flag via static state
    /// so the count:1 closure can suppress single-click when count:2 is en route.
    private static var lastTapAt: Date?
    private func isDoubleTapPending() -> Bool {
        let now = Date()
        defer { Self.lastTapAt = now }
        if let last = Self.lastTapAt, now.timeIntervalSince(last) < 0.05 {
            return true
        }
        return false
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success. (No UI integration yet — this just verifies the view compiles.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AttachmentChipView.swift
git commit -m "feat: AttachmentChipView with type-icon thumbnails"
```

---

### Task 7: Image thumbnails (replace the placeholder in `AttachmentChipView`)

**Files:**
- Modify: `Sources/Notaty/AttachmentChipView.swift`

- [ ] **Step 1: Replace the `thumbnail` view with a real image loader**

Locate this block in `AttachmentChipView.swift`:
```swift
    @ViewBuilder
    private var thumbnail: some View {
        if attachment.isImage {
            // Image thumbnail loading is implemented in Task 7. Until then,
            // fall through to the type-icon thumbnail.
            typeIcon
        } else {
            typeIcon
        }
    }
```

Replace with:
```swift
    @ViewBuilder
    private var thumbnail: some View {
        if attachment.isImage, let nsImage = imageThumbnail {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
        } else {
            typeIcon
        }
    }

    /// Decode a small thumbnail from the on-disk file. We bypass NSImage's
    /// default behavior of loading the full image by using ImageIO to ask
    /// for a thumbnail of the right pixel size. Returns nil for non-image
    /// files or decode failures.
    private var imageThumbnail: NSImage? {
        let url = NotesStore.attachmentURL(for: attachment)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 56,  // 28pt @2x
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 28, height: 28))
    }
```

- [ ] **Step 2: Add the ImageIO import at the top of the file**

Replace the existing imports:
```swift
import SwiftUI
import AppKit
```
with:
```swift
import SwiftUI
import AppKit
import ImageIO
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/AttachmentChipView.swift
git commit -m "feat: real image thumbnails via ImageIO"
```

---

### Task 8: Create `AttachmentStripView`

**Files:**
- Create: `Sources/Notaty/AttachmentStripView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct AttachmentStripView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared

    /// Coordinator owned by the strip; passed down to chips so Quick Look has
    /// a single retained data source for the panel.
    @StateObject private var preview = AttachmentPreviewCoordinator()

    private var attachments: [Attachment] {
        store.note(for: noteID)?.attachments ?? []
    }

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            stripContent
        }
    }

    private var stripContent: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentChipView(
                    attachment: attachment,
                    onRemove: { store.removeAttachment(attachment.id, from: noteID) },
                    onSingleClick: { preview.show(attachments: attachments, startAt: attachment.id) },
                    onDoubleClick: { NSWorkspace.shared.open(NotesStore.attachmentURL(for: attachment)) }
                )
                .onDrag {
                    let url = NotesStore.attachmentURL(for: attachment)
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                }
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

/// Wraps children left-to-right, breaking to a new line when the next child
/// would overflow. SwiftUI has no built-in for this in macOS 13.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: proposal.width ?? x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 2: Create the placeholder coordinator (real implementation in Task 11)**

Create `Sources/Notaty/AttachmentPreviewCoordinator.swift`:

```swift
import AppKit
import QuickLookUI

/// Holds the array currently being previewed and serves it to QLPreviewPanel.
/// Implemented as a class because QLPreviewPanel data source is an Obj-C protocol.
final class AttachmentPreviewCoordinator: NSObject, ObservableObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var items: [Attachment] = []
    private var startID: UUID?

    func show(attachments: [Attachment], startAt id: UUID) {
        self.items = attachments
        self.startID = id

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url = NotesStore.attachmentURL(for: items[index])
        return url as NSURL
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compile success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/AttachmentStripView.swift Sources/Notaty/AttachmentPreviewCoordinator.swift
git commit -m "feat: AttachmentStripView with FlowLayout + Quick Look coordinator stub"
```

---

### Task 9: Insert `AttachmentStripView` into `NoteView`

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`

- [ ] **Step 1: Replace the file's `body`**

Open `Sources/Notaty/NoteView.swift`. Find:
```swift
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
```

Replace with:
```swift
            VStack(spacing: 0) {
                TextField("Untitled", text: store.titleBinding(for: noteID))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .environment(\.layoutDirection, layoutDirection)

                Divider()

                AttachmentStripView(noteID: noteID)

                NoteTextEditor(
                    text: store.textBinding(for: noteID),
                    directionMode: note?.direction ?? .auto
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
```

- [ ] **Step 2: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- App launches; existing notes display unchanged (strip is hidden — `attachments == []`)
- No layout regression on the empty state

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/NoteView.swift
git commit -m "feat: render AttachmentStripView inside NoteView"
```

---

## Phase 3 · Entry points

### Task 10: Create `AttachmentImporter` helper

**Files:**
- Create: `Sources/Notaty/AttachmentImporter.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit
import UniformTypeIdentifiers

/// Stateless helpers that resolve "user wants to attach X" into actual
/// `addAttachments` calls on `NotesStore`. The helpers themselves don't own
/// any state; they take a target note ID and return the count attached.
enum AttachmentImporter {

    /// Open a file picker, multi-select enabled, all types allowed. Attaches
    /// the chosen files to the target note. No-op if the user cancels.
    @MainActor
    static func openPicker(targetNoteID noteID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach Files"
        panel.title = "Attach Files"

        guard panel.runModal() == .OK else { return }
        attach(urls: panel.urls, to: noteID)
    }

    /// Inspect an `NSPasteboard` for file URLs. Returns true and attaches them
    /// if any are present; returns false otherwise so the caller can fall
    /// through to default text-paste behavior.
    @MainActor
    @discardableResult
    static func attachFromPasteboard(_ pasteboard: NSPasteboard, to noteID: UUID) -> Bool {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return false
        }
        attach(urls: urls, to: noteID)
        return true
    }

    /// Common backend: warn on large files, then call NotesStore.
    @MainActor
    static func attach(urls: [URL], to noteID: UUID) {
        guard !urls.isEmpty else { return }

        // Soft warning at >50MB per file (one-time, dismissible).
        let largeFiles = urls.filter { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return size > 50 * 1024 * 1024
        }
        if !largeFiles.isEmpty {
            showLargeFileWarning()
        }

        let added = NotesStore.shared.addAttachments(to: noteID, from: urls)
        let failed = urls.count - added
        if failed > 0 {
            showCopyError(count: failed)
        }
    }

    @MainActor
    private static func showLargeFileWarning() {
        let key = "didShowLargeAttachmentWarning"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Large attachment"
        alert.informativeText = "Large attachments make note backups slower."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private static func showCopyError(count: Int) {
        let alert = NSAlert()
        alert.messageText = "Could not attach file"
        alert.informativeText = count == 1
            ? "A file could not be copied. Make sure Notaty has permission and that disk space is available."
            : "\(count) files could not be copied. Make sure Notaty has permission and that disk space is available."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/AttachmentImporter.swift
git commit -m "feat: AttachmentImporter helper (picker, pasteboard, large-file warning)"
```

---

### Task 11: Wire up Quick Look (real coordinator + responder forwarding)

**Files:**
- Modify: `Sources/Notaty/AttachmentPreviewCoordinator.swift`
- Modify: `Sources/Notaty/AppDelegate.swift`

- [ ] **Step 1: Replace the coordinator with a working data source + delegate**

Open `Sources/Notaty/AttachmentPreviewCoordinator.swift`. Replace the contents:

```swift
import AppKit
import QuickLookUI

/// Holds the attachments currently being previewed and vends them to
/// QLPreviewPanel. Conforms to QLPreviewPanelDataSource + delegate.
///
/// QLPreviewPanel is an app-singleton; the responder chain decides which
/// object answers `acceptsPreviewPanelControl(_:)`. We have AppDelegate
/// answer "yes" and route the panel to this coordinator.
final class AttachmentPreviewCoordinator: NSObject, ObservableObject {
    static let shared = AttachmentPreviewCoordinator()

    private(set) var items: [Attachment] = []
    private var startID: UUID?

    func show(attachments: [Attachment], startAt id: UUID) {
        self.items = attachments
        self.startID = id

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()

        if let i = items.firstIndex(where: { $0.id == id }) {
            panel.currentPreviewItemIndex = i
        }
    }
}

extension AttachmentPreviewCoordinator: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url = NotesStore.attachmentURL(for: items[index])
        return url as NSURL
    }
}
```

- [ ] **Step 2: Make `AttachmentStripView` use the shared coordinator**

Open `Sources/Notaty/AttachmentStripView.swift`. Find:

```swift
    @StateObject private var preview = AttachmentPreviewCoordinator()
```

Replace with:

```swift
    private let preview = AttachmentPreviewCoordinator.shared
```

- [ ] **Step 3: Have AppDelegate accept QLPreviewPanel control**

Open `Sources/Notaty/AppDelegate.swift`. Add `import QuickLookUI` at the top of the file (the existing imports are `import AppKit` and `import Sparkle`).

Then append this extension at the bottom of the file (outside the `final class AppDelegate { ... }` block):

```swift
extension AppDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = AttachmentPreviewCoordinator.shared
        panel.delegate = AttachmentPreviewCoordinator.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
```

- [ ] **Step 4: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- Attach a file via the picker isn't wired yet — defer the click test to Task 13. For now, verify the build succeeds and the coordinator compiles.

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/AttachmentPreviewCoordinator.swift Sources/Notaty/AttachmentStripView.swift Sources/Notaty/AppDelegate.swift
git commit -m "feat: Quick Look wiring via shared coordinator + responder chain"
```

---

### Task 12: Add the paperclip button to the tab bar

**Files:**
- Modify: `Sources/Notaty/NotatyRootView.swift`

- [ ] **Step 1: Insert the paperclip button before the existing `plus`**

Open `Sources/Notaty/NotatyRootView.swift`. Locate the `TabBar` body (around line 33):

```swift
        HStack(spacing: 0) {
            TabStrip(store: store)
                .frame(maxWidth: .infinity)

            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")
```

Replace the plus block with:

```swift
        HStack(spacing: 0) {
            TabStrip(store: store)
                .frame(maxWidth: .infinity)

            Button(action: attachToActiveNote) {
                Image(systemName: "paperclip")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("Attach file (⌥⌘A)")
            .disabled(activeNoteIsTextNote == false)

            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")
```

- [ ] **Step 2: Add the helper computed properties + action to `TabBar`**

In the `TabBar` struct (right after `var body: some View {`), add these helpers above the `body` declaration (or below, your call — same struct):

```swift
    private var activeNoteIsTextNote: Bool {
        guard let id = store.selectedID,
              let note = store.notes.first(where: { $0.id == id })
        else { return false }
        return note.type == .text
    }

    private func attachToActiveNote() {
        guard let id = store.selectedID else { return }
        AttachmentImporter.openPicker(targetNoteID: id)
    }
```

- [ ] **Step 3: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- Tab bar shows the new paperclip 📎 left of the existing +
- Click paperclip → file picker opens, multi-select enabled
- Choose 1-3 files → strip appears with chips
- Open the chosen note again, restart the app — chips persist

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NotatyRootView.swift
git commit -m "feat: paperclip button in tab bar opens NSOpenPanel"
```

---

### Task 13: Drag-drop on the note window

**Files:**
- Modify: `Sources/Notaty/NoteView.swift`

- [ ] **Step 1: Add `.onDrop` to the outer `VStack`**

Open `Sources/Notaty/NoteView.swift`. Find the existing `VStack(spacing: 0)`. Add a modifier at the very end:

```swift
            VStack(spacing: 0) {
                // ...existing children unchanged...
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
```

- [ ] **Step 2: Add the `handleDrop` method to `NoteView`**

Add this method on `NoteView` (after the existing computed properties):

```swift
    @MainActor
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [noteID] in
            AttachmentImporter.attach(urls: urls, to: noteID)
        }
        return true
    }
```

- [ ] **Step 3: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- Drag a single file from Finder onto the note window — chip appears in the strip
- Drag 3 files at once — all three chips appear

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NoteView.swift
git commit -m "feat: drag-drop file URLs anywhere on the note window"
```

---

### Task 14: Paste handler (intercept file URLs in `NoteTextEditor`)

**Files:**
- Modify: `Sources/Notaty/NoteTextEditor.swift`

- [ ] **Step 1: Add an `NSTextView` subclass that intercepts paste**

At the bottom of `Sources/Notaty/NoteTextEditor.swift`, add:

```swift
/// NSTextView subclass that lets file-URL pastes flow to the attachment
/// importer instead of being inserted as text. Plain-text pastes fall
/// through to super and behave exactly as before.
final class NotatyTextView: NSTextView {

    /// Set externally — the note ID this view is editing.
    var attachmentTargetNoteID: UUID?

    override func paste(_ sender: Any?) {
        if let id = attachmentTargetNoteID,
           AttachmentImporter.attachFromPasteboard(NSPasteboard.general, to: id) {
            return
        }
        super.paste(sender)
    }
}
```

- [ ] **Step 2: Use `NotatyTextView` instead of `NSTextView`**

Find this in `makeNSView`:
```swift
        let scrollView = NSTextView.scrollableTextView()
        ...
        let textView = scrollView.documentView as! NSTextView
```

Replace with:
```swift
        // Build a scrollable text view backed by NotatyTextView (so paste
        // can intercept file-URL pastes and divert them to attachments).
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textView = NotatyTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
```

- [ ] **Step 3: Pass the noteID through to the text view**

Add a `noteID: UUID?` parameter to `NoteTextEditor`:

```swift
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let directionMode: NoteDirection
    var noteID: UUID? = nil
    // ...
```

In `makeNSView`, set the target after the view is built:
```swift
        textView.attachmentTargetNoteID = noteID
```

In `updateNSView`, keep it in sync (in case `noteID` changes):
```swift
        if let nty = textView as? NotatyTextView {
            nty.attachmentTargetNoteID = noteID
        }
```

- [ ] **Step 4: Pass `noteID` from `NoteView`**

Open `Sources/Notaty/NoteView.swift`. Find:
```swift
                NoteTextEditor(
                    text: store.textBinding(for: noteID),
                    directionMode: note?.direction ?? .auto
                )
```

Replace with:
```swift
                NoteTextEditor(
                    text: store.textBinding(for: noteID),
                    directionMode: note?.direction ?? .auto,
                    noteID: noteID
                )
```

- [ ] **Step 5: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- Copy a text snippet from any app, ⌘V into a note — text inserts as before (regression test)
- In Finder, ⌘C on a file, then ⌘V in a Notaty note — chip appears, no text inserted
- Mixed: copy text, paste — text. Copy file, paste — attachment. No interference.

- [ ] **Step 6: Commit**

```bash
git add Sources/Notaty/NoteTextEditor.swift Sources/Notaty/NoteView.swift
git commit -m "feat: paste a file URL becomes an attachment, text paste unchanged"
```

---

### Task 15: Keyboard shortcut ⌥⌘A in the File menu

**Files:**
- Modify: `Sources/Notaty/NotatyActions.swift`
- Modify: `Sources/Notaty/AppDelegate.swift`

Notaty's app-wide keyboard shortcuts live in `NSApp.mainMenu`, built in `AppDelegate.setupMainMenu()` (around lines 53–151). The hamburger menu in `NotatyMenuBuilder` is separate and only opens on click — keyboard shortcuts must go in the main menu to work app-wide.

- [ ] **Step 1: Add `attachToSelectedNote` to `NotatyActions`**

Open `Sources/Notaty/NotatyActions.swift`. Add this static method to the `NotatyActions` enum:

```swift
    @MainActor
    static func attachToSelectedNote() {
        guard let id = NotesStore.shared.selectedID else {
            NSSound.beep()
            return
        }
        AttachmentImporter.openPicker(targetNoteID: id)
    }
```

- [ ] **Step 2: Add `@objc func attachFile()` to AppDelegate**

Open `Sources/Notaty/AppDelegate.swift`. Find `@objc func saveAs()` (or the next existing `@objc func` near the top of the methods block). Add immediately after:

```swift
    @objc func attachFile() {
        NotatyActions.attachToSelectedNote()
    }
```

- [ ] **Step 3: Insert "Attach File…" into the File menu**

Open `Sources/Notaty/AppDelegate.swift`. Find this block in `setupMainMenu()`:

```swift
        let saveAsItem = NSMenuItem(
            title: "Save As…",
            action: #selector(saveAs),
            keyEquivalent: "s"
        )
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = self
        fileMenu.addItem(saveAsItem)
        fileMenuItem.submenu = fileMenu
```

Add this between `fileMenu.addItem(saveAsItem)` and `fileMenuItem.submenu = fileMenu`:

```swift

        fileMenu.addItem(NSMenuItem.separator())

        let attachItem = NSMenuItem(
            title: "Attach File…",
            action: #selector(attachFile),
            keyEquivalent: "a"
        )
        attachItem.keyEquivalentModifierMask = [.command, .option]
        attachItem.target = self
        fileMenu.addItem(attachItem)
```

- [ ] **Step 4: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- File menu in the menu bar shows "Attach File… ⌥⌘A"
- Press ⌥⌘A with a text note active → file picker opens
- Press ⌥⌘A with no note selected → beeps, no crash

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/NotatyActions.swift Sources/Notaty/AppDelegate.swift
git commit -m "feat: ⌥⌘A keyboard shortcut for Attach File"
```

---

## Phase 4 · Export integration

### Task 16: Extend `exportAllNotes` to include attachments

**Files:**
- Modify: `Sources/Notaty/NotatyActions.swift`

- [ ] **Step 1: Replace `exportAllNotes`**

Open `Sources/Notaty/NotatyActions.swift`. Find `static func exportAllNotes()`. Replace its body to also write a `_manifest.json` with the full structured note data, plus copy each attachment into a sibling subfolder:

```swift
    static func exportAllNotes() {
        let notes = NotesStore.shared.notes
        guard !notes.isEmpty else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "zip")!]
        panel.nameFieldStringValue = "Notaty-Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Human-readable .txt files (preserved for backward compat —
            // users who unzip with Finder still see readable text).
            for (index, note) in notes.enumerated() {
                let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeName = (trimmed.isEmpty ? "Untitled" : trimmed)
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let fileName = "\(index + 1) - \(safeName).txt"
                let fileURL = tempDir.appendingPathComponent(fileName)
                try note.text.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            // Manifest with full structured data — this is what Notaty itself
            // reads on import to round-trip attachments. Older Notaty versions
            // (pre-attachments) ignore the manifest and just import the .txt.
            let manifestURL = tempDir.appendingPathComponent("_manifest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(notes).write(to: manifestURL, options: .atomic)

            // Copy each attachment file into the export tree, preserving
            // the storedName (so the manifest's references resolve).
            let attachmentsExportDir = tempDir.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachmentsExportDir, withIntermediateDirectories: true)
            for note in notes {
                for attachment in note.attachments {
                    let src = NotesStore.attachmentURL(for: attachment)
                    let dest = attachmentsExportDir.appendingPathComponent(attachment.storedName)
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
            }

            // Zip with ditto.
            let zipProcess = Process()
            zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zipProcess.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, url.path]
            try zipProcess.run()
            zipProcess.waitUntilExit()

            try? FileManager.default.removeItem(at: tempDir)

            if zipProcess.terminationStatus != 0 {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not create zip file."
                alert.alertStyle = .warning
                alert.runModal()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
```

- [ ] **Step 2: Build & smoke test**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- Attach a couple of files to a note
- Trigger Export from the menu, save the zip somewhere, unzip it manually in Finder
- Verify the unzipped folder contains: numbered `.txt` files, `_manifest.json`, `attachments/` subfolder with the copied files

- [ ] **Step 3: Commit**

```bash
git add Sources/Notaty/NotatyActions.swift
git commit -m "feat: export includes _manifest.json + attachments/ alongside .txt"
```

---

### Task 17: Extend `importFromZip` to restore attachments

**Files:**
- Modify: `Sources/Notaty/NotatyActions.swift`

- [ ] **Step 1: Replace `importFromZip`**

Open `Sources/Notaty/NotatyActions.swift`. Replace `private static func importFromZip(_ url: URL)` with:

```swift
    private static func importFromZip(_ url: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", url.path, tempDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = "Could not extract zip file."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }

            // Prefer the manifest if present (round-trips attachments).
            // Fall back to .txt-only for old/foreign zips.
            if let importedFromManifest = importFromManifestIfAvailable(in: tempDir) {
                if importedFromManifest > 0 {
                    NotesStore.shared.selectedID = NotesStore.shared.notes.last?.id
                }
                try? FileManager.default.removeItem(at: tempDir)
                return
            }

            // Legacy .txt-only path (pre-attachments exports).
            let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
            var imported = 0

            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension.lowercased() == "txt" else { continue }
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                var title = fileURL.deletingPathExtension().lastPathComponent
                if let range = title.range(of: #"^\d+\s*-\s*"#, options: .regularExpression) {
                    title = String(title[range.upperBound...])
                }

                let store = NotesStore.shared
                let note = store.addNote()
                store.update(id: note.id) {
                    $0.title = title.isEmpty ? "Untitled" : title
                    $0.text = text
                }
                imported += 1
            }

            if imported > 0 {
                NotesStore.shared.selectedID = NotesStore.shared.notes.last?.id
            }

            try? FileManager.default.removeItem(at: tempDir)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Returns the number of notes imported, or `nil` if no manifest was found.
    /// When found, copies each attachment file into Notaty's attachments dir
    /// and pushes the full Note structures (with attachments[]) into the store.
    private static func importFromManifestIfAvailable(in tempDir: URL) -> Int? {
        let manifestURL = tempDir.appendingPathComponent("_manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let importedNotes = try? JSONDecoder().decode([Note].self, from: data)
        else {
            return nil
        }

        // Restore attachment files into Notaty's attachments dir.
        NotesStore.shared.ensureAttachmentsDir()
        let exportAttachmentsDir = tempDir.appendingPathComponent("attachments")

        for note in importedNotes {
            for attachment in note.attachments {
                let src = exportAttachmentsDir.appendingPathComponent(attachment.storedName)
                let dest = NotesStore.attachmentURL(for: attachment)
                if FileManager.default.fileExists(atPath: src.path),
                   !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
            }
        }

        // Append (don't replace) — same semantics as the .txt path.
        let store = NotesStore.shared
        for note in importedNotes {
            store.notes.append(note)
        }
        // Force the index rebuild + persistence by triggering a published change
        // (mutating notes via `append` directly bypasses indexByID; the store's
        // existing helpers do this on add/delete. For import, call `addNote`
        // dance is wrong because we want to preserve the original IDs. So we
        // do it manually:)
        store.rebuildIndexAfterImport()  // see Step 2

        return importedNotes.count
    }
```

- [ ] **Step 2: Add a helper on `NotesStore` to rebuild + persist after import**

Open `Sources/Notaty/NotesStore.swift`. The existing `rebuildIndex` is `private`. Add a public wrapper near the bottom:

```swift
    /// Used by the importer after directly mutating `notes` to re-establish
    /// the ID→index map. Triggers persistence via the existing $notes sink.
    func rebuildIndexAfterImport() {
        rebuildIndex()
        // Touch `notes` so the debounced save sink fires.
        let snapshot = notes
        notes = snapshot
    }
```

- [ ] **Step 3: Build & smoke test (full round-trip)**

Run: `swift build`
Then: `bash run-debug.sh`

Manual check:
- Attach 2 files to a note
- Export → save zip
- Delete the note (× on the tab) — this should also delete the attachment files (cascade was added in Task 4)
- Import the zip → the note returns with both chips, files openable

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/NotatyActions.swift Sources/Notaty/NotesStore.swift
git commit -m "feat: import restores attachments via _manifest.json + sidecar files"
```

---

## Phase 5 · Wrap-up

### Task 18: Full acceptance-criteria smoke test

- [ ] **Step 1: Run through every item in the spec's acceptance-criteria list (12 items)**

Spec: `docs/superpowers/specs/2026-04-30-attachments-design.md` § Acceptance criteria.

Verification:
1. Empty note unchanged from v1.2.1 — open a fresh note, confirm no strip
2. Paperclip → multi-select → both attach — verified
3. Drag PNG from Finder → chip with thumbnail — verified
4. ⌘V file from Finder → chip — verified
5. Single click → Quick Look; double click → default app — verified
6. Hover chip → × shows; click × → file deleted from disk; check `~/Library/Application Support/Notaty/attachments/` to confirm
7. Drag chip to Finder → file copies — verified
8. Delete note with attachments → all sidecar files gone — verified by `ls` of the dir
9. Quit and relaunch → chips render, files open — verified
10. Existing v1.2.1 notes load without crashing — verified by checking real existing notes
11. Zip export/import round-trips attachments — verified in Task 17
12. `swift build -c release` succeeds and produced binary works

If any item fails, write a follow-up task to fix it; don't commit a green mark you didn't earn.

- [ ] **Step 2: Run the full release build**

Run: `swift build -c release`
Expected: clean build, no warnings beyond the existing ones.

- [ ] **Step 3: Build the production .app and smoke-test once more**

Run: `bash build.sh`
Then: `open Notaty.app`

Verify the same 12 acceptance criteria once on the production-quality build (different bundle ID than debug, fresh UserDefaults state — confirms first-launch behavior).

---

### Task 19: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Insert an `Unreleased` section at the top**

Open `CHANGELOG.md`. Replace the first heading line (`# Changelog\n\n## v1.2.1`) with:

```markdown
# Changelog

## Unreleased

- File attachments on text notes: drop, paste, or click the new paperclip in the tab bar. Chips show between title and body; click previews via Quick Look, double-click opens in the default app, drag a chip to Finder to copy out. Attachments survive launches and round-trip through zip export/import.

## v1.2.1
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG note for attachments feature (Unreleased)"
```

- [ ] **Step 3: Hand off to the user**

Report:
- All 19 tasks committed
- 12 acceptance criteria verified manually
- `swift build -c release` clean
- Production `bash build.sh` produces a working .app
- CHANGELOG `Unreleased` section reflects the user-visible feature line

The user controls version bumps (per durable preference). When they say "ship as v1.3", a follow-up task will:
- Replace `## Unreleased` with `## v1.3`
- Bump build.sh and any other version sites
- Tag and push, letting `check-and-deploy.sh` ship via OTA

---

## Self-review — coverage against the spec

| Spec section | Covered by |
|---|---|
| Data model — `Attachment` struct | Task 1 |
| Data model — `Note.attachments` field, backward-compat | Task 2 |
| Storage — `attachmentsDir` + ensure | Task 3 |
| Storage — addAttachment | Task 3 |
| Storage — removeAttachment | Task 4 |
| Storage — cascade delete | Task 4 |
| Storage — orphan sweep | Task 5 |
| UI — `AttachmentChipView` | Task 6 |
| UI — image thumbnails (ImageIO) | Task 7 |
| UI — `AttachmentStripView` (FlowLayout, conditional render) | Task 8 |
| UI — strip integrated into `NoteView` | Task 9 |
| Helper — `AttachmentImporter` (picker + paste + warnings) | Task 10 |
| Interaction — Quick Look on single-click | Task 11 (coordinator) + Task 8 (binding) |
| Interaction — Open on double-click | Task 8 |
| Interaction — Drag chip out (NSItemProvider) | Task 8 |
| Interaction — Hover × remove | Task 6 |
| Entry — paperclip in tab bar + NSOpenPanel | Task 12 |
| Entry — drag-drop on note window | Task 13 |
| Entry — paste (file URLs intercepted, text falls through) | Task 14 |
| Entry — keyboard shortcut ⌥⌘A | Task 15 |
| Soft 50 MB warning toast | Task 10 (`showLargeFileWarning`) |
| Export integration | Task 16 |
| Import integration | Task 17 |
| Acceptance criteria | Task 18 |
| CHANGELOG entry | Task 19 |

Spec sections explicitly excluded by user choice (A/A): localization (no l10n), automated tests (no test target). Both are tracked as separate future projects in the spec's "Out of scope, follow-ups" section.

---

**End of plan.**
