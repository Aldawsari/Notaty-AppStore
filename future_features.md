# Notaty — Future Features

Backlog of feature ideas captured during development. Each entry has a brief description, scope estimate, and any context worth preserving.

---

## Recently Deleted (note recovery)

**Captured:** 2026-04-30, during the attachments + drop-to-attach build.

### Problem

Today, deleting a note permanently removes it from `notes.json`. The user gets a confirmation dialog ("Delete this note?") but once confirmed, the data is gone — no Trash recovery, no undo. Attachments themselves are now restorable from `~/.Trash/` (since 2026-04-30), but the note's title, body, direction, voice transcript, etc. are lost the moment the user clicks Delete.

### Goal

Match the macOS Notes-app pattern: deleted notes go to a "Recently Deleted" area for ~30 days. The user can restore them with one click, permanently delete them on demand, or let them auto-purge.

### Approach (recommended: full soft-delete)

1. **Data model:** add `deletedAt: Date?` to `Note`. Decoding stays backward-compatible (`decodeIfPresent ?? nil`).
2. **Delete becomes soft:** `NotesStore.delete(id:)` sets `deletedAt = Date()` instead of removing the entry. Attachment sidecar files are NOT moved to Trash yet — they stay in `attachmentsDir` so the note's chips still work after restore.
3. **Filter the main view:** the tab strip and `notes` accessors filter out notes where `deletedAt != nil`. Adds a `notes.activeNotes` computed property; existing call sites use it.
4. **Recently Deleted UI:** a new section reachable from the hamburger menu / Settings. Shows soft-deleted notes with title, deleted-at date, and two actions per row: **Restore** and **Delete Permanently**.
5. **Restore action:** clears `deletedAt`. Note returns to the main list.
6. **Permanently delete action:** the current hard-delete logic. Trashes attachment sidecar files. Removes from `notes.json`.
7. **Auto-purge:** on launch, sweep notes where `deletedAt > 30 days ago` and permanently delete them. The 30-day window is the macOS convention; could be a Settings preference.
8. **Empty Recently Deleted action:** bulk permanent-delete for everything in the trash list.

### Scope estimate

- ~6 tasks (data model + filter + UI + restore + purge + empty)
- ~150 LOC across `Note.swift`, `NotesStore.swift`, a new `RecentlyDeletedView.swift`, and `NotatyMenuBuilder.swift` (or hamburger menu)
- One brainstorm + plan + implement cycle (~half a day with subagent-driven execution)

### Quick alternative (rejected for v1, keep as fallback)

A `dump-to-Trash on delete` approach: when a note is deleted, write a `<title>.txt` or `.json` file to `~/.Trash/` containing the note's content. Recovery is manual (user digs the file out of Trash, opens it). Faster to implement (~30 min) but recovery UX is awful — user has to manually rebuild the note from the dump. Not recommended.

### Acceptance criteria sketch

1. Click × on a note tab → confirm dialog → confirm → note vanishes from tab strip but is preserved in `notes.json` with `deletedAt` set
2. Open Recently Deleted → see the deleted note → click Restore → note returns to tab strip
3. Open Recently Deleted → click Delete Permanently → confirm → note removed from `notes.json`, attachments trashed
4. Existing v1.2.1 notes load correctly (`deletedAt == nil` for all)
5. Auto-purge: notes with `deletedAt > 30 days` are permanently deleted on launch (logged to console for visibility during testing)
6. Empty Recently Deleted button removes all in one go after a single confirmation

### Risks / open questions

- **Where does the Recently Deleted UI live?** Options: a dedicated tab/window like Notes.app; a Settings panel; a hamburger menu submenu listing them. Settings panel is simplest.
- **Should restored notes return to their original tab position?** Probably yes — store `originalIndex: Int?` alongside `deletedAt`. On restore, insert at that index (or end if invalid).
- **Voice notes' audio files**: should they also stay in `audio/` until permanent delete? Yes, same logic as attachments.
- **What about export?** Export should default to active notes only. Maybe a Settings flag "Include Recently Deleted in export."

---
