# Notaty — File Attachments (Design Spec)

**Date:** 2026-04-30
**Status:** Approved for implementation
**Scope:** Text notes only. Voice notes are explicitly out of scope for this release; tracked as a follow-up.

---

## Problem

A note in Notaty can hold a title and body of plain text. Users frequently need to keep a file alongside a note — a screenshot, a PDF the note is *about*, a contract draft, a voice memo from somewhere else. Today the only path is to leave Notaty, store the file in a separate Finder folder, and lose the contextual link.

## Goal

Add file attachment support to text notes with the same low-friction feel as email attachments: drop, paste, or click a paperclip; the file rides along with the note from now on. Attachments survive across launches, sync paths (UserDefaults + `notes.json` backup), and zip export/import.

## Out of scope

- **Voice notes do NOT get attachments in this release.** `VoiceNoteView` has a distinct UI (recorder + transcription chat-bubble layout); extending the strip there is a separate task. Tracked as a follow-up; user explicitly asked to be reminded.
- **Inline images in body text.** Notaty's body is plain text; this spec does not migrate to rich text or `NSAttributedString`.
- **No editing of attachments inside Notaty.** Attached files are immutable from Notaty's point of view; user opens them externally to edit.
- **No cloud sync.** Attachments live with the local notes store; iCloud sync is not in this spec.

---

## UX

### Empty note

When a note has zero attachments, the UI shows nothing extra — title field above the body editor, no strip, no drop hint.

### Attaching files

Three equally first-class entry points:

1. **📎 Paperclip button in the tab bar**, immediately left of the existing new-note "+" button. Tooltip: localized "Attach file" / "إرفاق ملف". Click opens an `NSOpenPanel` configured for multi-select, all file types allowed.
2. **Paste** (`⌘V`): when the system pasteboard contains one or more file URLs, paste attaches them. Pasting plain text behaves exactly as before — no regression. Multi-file paste attaches all of them.
3. **Drag-drop**: dropping files anywhere on the note window attaches them. The drop target is the entire note view (`onDrop(of: [.fileURL], isTargeted: ...)`), so the drop zone is forgiving.

A **keyboard shortcut** `⌥⌘A` (Option-Cmd-A) opens the file picker; matches the paperclip click behavior.

### The attachment strip

The strip appears between the title field and the body editor **only when `attachments.count > 0`**. It auto-hides when the last attachment is removed.

Layout: a `LazyHStack`-equivalent that **wraps to multiple rows** (`flexible flow layout`). No horizontal scrolling — easier to scan, fits Notaty's narrow window.

### The chip

Each attachment renders as a chip with these elements, in order:

- A **28×28 thumbnail** on the left:
  - For images (jpg/jpeg/png/gif/heic/webp/tiff/bmp): the actual decoded thumbnail
  - For other files: a colored square with a 3-character type label rendered in white (PDF, DOC, ZIP, M4A, MP3, etc.) — color keyed off type group
- **Filename** (medium weight, single line, truncates with ellipsis at the natural chip width)
- **Size** in human format ("1.2 MB", "340 KB", "28 KB")
- A **× remove button** that appears on hover only

The chip is rendered with a 1px hairline border, light shadow, 8px corner radius. Visual style matches Notaty's existing redesign tokens.

### Click behavior

- **Single click** on a chip → `QLPreviewPanel.shared` is shown with the attachment as its only data item. ESC dismisses; Spacebar in the strip toggles preview off. Most-native macOS behavior.
- **Double click** on a chip → `NSWorkspace.shared.open(attachmentURL)` — opens in the default app for the file type. Same as double-clicking in Finder.

### Drag attachment out

Each chip is a drag source. The drag pasteboard exposes the file URL (`NSItemProvider` with `kUTTypeFileURL`). Dragging a chip to Finder copies the file there; dragging to a Mail compose window attaches it there. Free with the right `onDrag` modifier; ~5 lines of code.

### Soft size warning

When attaching a file > 50 MB, show a one-time, dismissible toast: localized "Large attachment — note backups will be slower." This is a heads-up, not a block; the file still attaches.

---

## Data model

```swift
struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var originalName: String   // "screenshot.png" — what the user sees
    var storedName: String     // "<UUID>.png" — actual filename on disk
    var byteSize: Int64
    var addedAt: Date
}
```

`Note` gains:

```swift
struct Note: Identifiable, Codable, Equatable {
    // ... existing fields ...
    var attachments: [Attachment]
}
```

### Backward compatibility

The existing `Note.init(from: Decoder)` already pattern uses `decodeIfPresent` for new fields. Apply the same pattern:

```swift
self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
```

Existing notes load with `attachments == []`. Saving them back writes the new field. No migration step required.

---

## Storage

A new sibling directory of `audio/`:

```
~/Library/Application Support/Notaty/
├── notes.json
├── audio/
│   └── <UUID>.m4a   ← existing voice notes
└── attachments/
    └── <UUID>.<ext>  ← new
```

`NotesStore` gains:

```swift
static let attachmentsDir: URL  // applicationSupportDirectory/Notaty/attachments/
func ensureAttachmentsDir()      // mkdir -p, mirror of ensureAudioDir
static func attachmentURL(for: Attachment) -> URL
```

### Operations

- **Add**: copy the source file into `attachmentsDir/<UUID>.<ext>`, build the `Attachment` struct, push onto `note.attachments`, save store. Use `Data(contentsOf:)` + `.write(to:)` (atomic). On copy failure (out of space, permission), surface a localized error and do NOT mutate the note.
- **Remove**: pop from `note.attachments`, delete the file at `attachmentURL(for:)`, save store.
- **Note delete**: when a text note is deleted, sweep its `attachments` array and remove every sidecar file — same pattern as voice-note deletion.
- **Orphan sweep on launch**: scan `attachmentsDir`, compare against the union of all `Attachment.storedName` across all notes; delete anything orphaned. Same as the existing audio cleanup if there is one; if there isn't one, add it.

### Why files-on-disk and not base64 in JSON

The existing `notes.json` is read into memory eagerly on launch. Embedding even a single 5MB attachment as base64 inflates the JSON to ~6.7MB and makes load + decode noticeably slower; multiple 50MB attachments become unworkable. Sidecar files keep `notes.json` proportional to *metadata* size only.

---

## UI components

### `AttachmentChipView`
- Inputs: `attachment: Attachment`, callbacks `onRemove`, `onPreview`, `onOpen`
- Outputs: a chip view as described above
- Handles its own hover state for the × button visibility
- Applies localized RTL via `.environment(\.layoutDirection, …)` consistent with the rest of Notaty
- Provides drag-out via `.onDrag { NSItemProvider(contentsOf: attachmentURL) }`

### `AttachmentStripView`
- Inputs: `noteID: UUID`
- Reads `note.attachments` from `NotesStore`
- Renders `attachments` in a wrapping flow layout, padding & background to match the redesign tokens
- Returns `EmptyView()` when `attachments.isEmpty`

### `NoteView` (modification)
- Insert `AttachmentStripView(noteID:)` between the title field's `Divider()` and `NoteTextEditor`
- Add `.onDrop(of: [.fileURL], delegate: NoteDropDelegate(noteID))` on the outer `VStack`

### Paperclip in tab bar
- Notaty's tab bar is a custom SwiftUI strip in `NotatyRootView.swift` (`TabBar` struct, lines 30–71). Trailing buttons today: `plus` (new note) → optional `mic` (new voice note) → `camera.viewfinder` (OCR) → `HamburgerButton`.
- Insert a new `Button` between the `TabStrip` and the existing `plus` button — paperclip becomes the leftmost note-action button. SF Symbol: `paperclip`. Same `frame(width: 24, height: 22)` and `.buttonStyle(.plain)` as the others. Tooltip via `.help(…)` localized.
- Action: open `NSOpenPanel` configured for multi-select; on success, call `notesStore.addAttachments(to: activeNoteID, from: pickedURLs)`.
- Disable (greyed out) when there is no active text note (no selection, or active note is a voice note).

### Paste handling
- Override paste in `NoteTextEditor` (or its enclosing responder) to inspect `NSPasteboard.general` for items conforming to `kUTTypeFileURL`
- If any are present, attach them and return `true` (consume the event)
- Otherwise, fall through to default text-paste behavior — **non-negotiable** to preserve existing UX

---

## Interactions matrix

| Action | Result |
|---|---|
| Click 📎 in tab bar / press ⌥⌘A | NSOpenPanel multi-select → attach to active note |
| Drop file(s) on note window | Attach to active note |
| ⌘V with file URL on pasteboard | Attach to active note |
| ⌘V with text on pasteboard | Existing text paste, unchanged |
| Single-click chip | Quick Look preview |
| Double-click chip | Open in default app |
| Hover chip → click × | Remove attachment (file deleted from disk) |
| Drag chip to Finder/email | Copy file out via NSItemProvider |
| Delete note containing attachments | All sidecar files removed |

---

## Localization

New strings (EN + AR):

| Key | EN | AR |
|---|---|---|
| `attach.tooltip` | Attach file | إرفاق ملف |
| `attach.menu` | Attach File… | إرفاق ملف… |
| `attach.warning.large.title` | Large attachment | ملف كبير |
| `attach.warning.large.body` | Large attachments make note backups slower. | الملفات الكبيرة تبطئ النسخ الاحتياطي للملاحظات. |
| `attach.error.copy.title` | Could not attach file | تعذّر إرفاق الملف |
| `attach.error.copy.body` | %@ could not be copied. Make sure Notaty has permission and that disk space is available. | تعذّر نسخ %@. تأكّد من أن لدى Notaty الإذن وأن هناك مساحة قرص كافية. |

Add to `Localizable.xcstrings`. The build pipeline already compiles xcstrings into lproj at build time per the existing `build.sh`.

---

## Tests

Following the existing test target pattern:

### `AttachmentStoreTests`
- Add an attachment from a tmp source URL → file appears in `attachmentsDir`, metadata in note
- Remove an attachment → file deleted from disk, metadata gone
- Add three, remove the middle one → remaining two intact
- Delete a note with two attachments → both sidecar files deleted

### `NoteCodingTests`
- Decode a v1.2.1 `notes.json` that has no `attachments` field → decodes successfully, `attachments == []`
- Round-trip: encode, decode, equality holds
- Decode a note with three attachments → metadata preserved exactly

### `AttachmentOrphanSweepTests`
- Drop an unreferenced file in `attachmentsDir`, run sweep → file removed
- Files referenced by any note → preserved

### `AttachmentImportExportTests`
- Export zip with notes containing attachments → zip contains `attachments/<UUID>.<ext>` paths
- Import the same zip on a fresh state → notes + attachments restored exactly

---

## Acceptance criteria

The feature is "done" when all of these are observable in a debug build:

1. With zero attachments, the note UI is visually identical to v1.2.1.
2. Clicking 📎 in the tab bar opens a file picker; selecting two files adds both to the active note as chips in a strip.
3. Dragging a PNG file from Finder onto the note window adds it as a chip with a real thumbnail.
4. Copying a file in Finder and pressing ⌘V in a note attaches it.
5. Single-clicking a chip opens Quick Look. Double-clicking opens the file in its default app.
6. Hovering a chip reveals an ×; clicking × removes the attachment and deletes the disk file.
7. Dragging a chip to Finder copies the file out.
8. Deleting a note with attachments removes the sidecar files from disk.
9. Quitting and relaunching Notaty restores all attachments — chips render, files openable.
10. Existing v1.2.1 notes (no `attachments` field) load without crashing or losing data.
11. Existing zip export / import flow round-trips attachments cleanly.
12. Arabic localization renders correctly: paperclip tooltip in Arabic, RTL layout intact, large-file warning translated.

---

## Risks

- **Quick Look on a multi-app sandbox** — `QLPreviewPanel` requires the app to vend the data. We need to retain a `[Attachment]` data source that conforms to `QLPreviewPanelDataSource`. Not hard, but easy to get wrong (forgetting to wire the responder chain returns a no-op preview). Smoke-test early.
- **Tab bar paperclip placement** — Notaty's tab UI may be native NSWindow tabs *or* a custom SwiftUI tab strip; the integration point differs. Resolve this on the first day of implementation by reading `NotatyMenuBuilder` / `NotatyRootView` / window controller.
- **Paste hijacking** — overriding paste in the text editor risks breaking the existing text-paste flow. Tests must cover plain-text paste regression.
- **Disk-full** during attach — the user can fill their disk with a single drop. Surface the error clearly; never half-write a partial file. Use atomic writes.
- **Filename collisions** are eliminated by using UUIDs for storedName, but the `originalName` is what we render to users; don't dedupe-rename it for display.

---

## Out of scope, follow-ups

- Voice-note attachments (option B from the design brainstorm) — user asked to be reminded.
- Inline image rendering in body — would require a rich text body, separate spec.
- Attachment search — not in this release. Consider once the feature is in users' hands.
- Per-attachment annotations / captions — same.
