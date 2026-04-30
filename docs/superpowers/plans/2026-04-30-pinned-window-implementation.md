# Notaty Pinned Window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Pin window" toggle (tab bar pin icon + Settings checkbox, both bound to one state) that, when on, keeps the main window stuck open by suppressing the existing dismiss-on-outside-click monitor.

**Architecture:** Single `pinned: Bool` on `Settings.shared` (UserDefaults-backed, default `false`). Two UI controls bind to it. AppDelegate observes the value via Combine; when `false`, the existing global mouse-down monitor is installed when the window is shown. When `true`, it's not installed (or removed if currently installed).

**Tech Stack:** Swift / SwiftUI / AppKit, Combine, NSEvent global monitor, UserDefaults.

**Spec:** `docs/superpowers/specs/2026-04-30-pinned-window-design.md`

**Scope:** No automated tests (Notaty has no test target). Manual acceptance criteria walkthrough in Task 5.

---

## File Structure

| Path | Change |
|---|---|
| `Sources/Notaty/Settings.swift` | Add `@Published var pinned: Bool` with UserDefaults persistence under key `"windowPinned"` |
| `Sources/Notaty/NotatyRootView.swift` | Insert pin Button in `TabBar` between paperclip and ＋, with `pin`/`pin.fill` SF Symbol switching on `Settings.shared.pinned` |
| `Sources/Notaty/SettingsView.swift` | Add the "Keep window on top" Toggle in the existing "Window" section card |
| `Sources/Notaty/AppDelegate.swift` | Observe `Settings.shared.$pinned`; gate `installDismissMonitors` and respond to runtime toggles |
| `CHANGELOG.md` | Add Unreleased entry |

Note: at the time this plan executes, `feature/floating-window` is branched off `main` (which does NOT include the attachments feature). The paperclip button referenced in the spec doesn't exist on this branch — the pin button goes between the **start of the trailing actions** and the existing **＋ new-note button**. There is no paperclip on this branch.

---

## Task 1: Add `pinned` to Settings

**Files:**
- Modify: `Sources/Notaty/Settings.swift`

- [ ] **Step 1: Add the `pinned` property**

Open `Sources/Notaty/Settings.swift`. Locate the existing `@Published var launchAtLogin: Bool { didSet { ... } }` block (around line 68–73). Add this immediately after it:

```swift
    @Published var pinned: Bool {
        didSet { UserDefaults.standard.set(pinned, forKey: Self.pinnedKey) }
    }
```

- [ ] **Step 2: Add the UserDefaults key constant**

Locate the existing key constants block (around line 105–110, starting with `private static let sizeKey = "defaultWindowSize"`). Add at the bottom of that block:

```swift
    private static let pinnedKey = "windowPinned"
```

- [ ] **Step 3: Initialize `pinned` in `private init()`**

Locate the existing `private init()` body. After the existing `transcribeLanguage` initialization (around line 126) and before the `if UserDefaults.standard.object(forKey: Self.launchKey) == nil { ... }` block, add:

```swift
        self.pinned = UserDefaults.standard.bool(forKey: Self.pinnedKey)
```

(Default value is `false` — `UserDefaults.bool(forKey:)` returns false for unset keys, which matches the spec's default-off requirement.)

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/Settings.swift
git commit -m "feat: add pinned setting to Settings.shared (UserDefaults-backed)"
```

---

## Task 2: Pin button in tab bar

**Files:**
- Modify: `Sources/Notaty/NotatyRootView.swift`

- [ ] **Step 1: Add the pin button before the existing `plus`**

Open `Sources/Notaty/NotatyRootView.swift`. Locate the `TabBar` body (around line 33). Find:

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

Replace with:

```swift
        HStack(spacing: 0) {
            TabStrip(store: store)
                .frame(maxWidth: .infinity)

            Button(action: { Settings.shared.pinned.toggle() }) {
                Image(systemName: settings.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(settings.pinned ? .accentColor : .secondary)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help(settings.pinned ? "Unpin window" : "Pin window on top")

            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("New note (⌘T)")
```

- [ ] **Step 2: Add the `settings` ObservedObject to TabBar**

`TabBar` already has `@ObservedObject var store: NotesStore`. Add a sibling property right below it:

```swift
    @ObservedObject private var settings = Settings.shared
```

This makes the pin Button's tooltip and SF Symbol auto-update when `Settings.shared.pinned` changes (whether via the pin Button itself or the Settings window).

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 4: Smoke test the visual state**

Run: `bash run-debug.sh`
Manual check:
- Tab bar shows a pin icon between the tab strip and the ＋ button
- Default state: outline `pin` icon, secondary (gray) color, tooltip "Pin window on top"
- Click the pin icon: switches to `pin.fill`, accentColor (blue), tooltip "Unpin window"
- Click again: switches back

If anything looks off (icon size mismatched with siblings, color wrong, tooltip not updating), STOP and report.

- [ ] **Step 5: Commit**

```bash
git add Sources/Notaty/NotatyRootView.swift
git commit -m "feat: pin button in tab bar bound to Settings.shared.pinned"
```

---

## Task 3: Settings window toggle

**Files:**
- Modify: `Sources/Notaty/SettingsView.swift`

- [ ] **Step 1: Add the toggle in the Window section card**

Open `Sources/Notaty/SettingsView.swift`. Find the existing "Window" section (around line 20–33):

```swift
                // ── Window ───────────────────────────────────────────────
                sectionHeader("Window")

                settingsCard {
                    rowLabel("Default size")
                    Picker("", selection: $settings.defaultWindowSize) {
                        ForEach(WindowSizePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
```

Replace the `settingsCard { ... }` block with:

```swift
                settingsCard {
                    rowLabel("Default size")
                    Picker("", selection: $settings.defaultWindowSize) {
                        ForEach(WindowSizePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)

                    Divider()
                        .padding(.vertical, 4)

                    Toggle(isOn: $settings.pinned) {
                        rowLabel("Keep window on top")
                    }
                    .toggleStyle(.switch)
                }
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compile success.

- [ ] **Step 3: Smoke test**

Run: `bash run-debug.sh`
- Open Settings (gear/settings menu item from hamburger or wherever Settings is reached in the running app)
- Window section now shows: Default size picker · divider · Keep window on top toggle
- Toggle "Keep window on top" → tab bar pin icon updates immediately to `pin.fill` accentColor
- Toggle pin icon in tab bar → Settings checkbox updates

Both controls must stay in sync. If they don't, the `@ObservedObject` wiring in TabBar from Task 2 isn't right — go back and verify.

- [ ] **Step 4: Commit**

```bash
git add Sources/Notaty/SettingsView.swift
git commit -m "feat: 'Keep window on top' toggle in Settings → Window section"
```

---

## Task 4: Wire AppDelegate to gate dismiss monitors on pinned

**Files:**
- Modify: `Sources/Notaty/AppDelegate.swift`

This is the load-bearing task: making `pinned == true` actually skip the dismiss-on-outside-click behavior, both at window-show time and when the toggle flips at runtime.

- [ ] **Step 1: Gate `installDismissMonitors` call in `showWindow`**

Open `Sources/Notaty/AppDelegate.swift`. Find the existing `showWindow` method, specifically the line:

```swift
        installDismissMonitors()
```

(around line 210, at the end of `showWindow`).

Replace with:

```swift
        // Only install the dismiss monitor when the user hasn't pinned the
        // window. When pinned, the window stays put until explicitly closed.
        if !Settings.shared.pinned {
            installDismissMonitors()
        }
```

- [ ] **Step 2: Add a Combine subscription that responds to runtime toggles**

In `AppDelegate`, find the existing instance properties block at the top of the class (around line 10–20, where `outsideClickMonitor`, `localEscMonitor`, etc. live). Add:

```swift
    private var pinnedCancellable: AnyCancellable?
```

Make sure `import Combine` is at the top of the file. (Check the existing imports — if `Combine` isn't imported, add it. Many AppKit-heavy files do not import it by default.)

- [ ] **Step 3: Subscribe in `applicationDidFinishLaunching`**

Find `applicationDidFinishLaunching` (around line 50–70, where the app's launch setup lives). At the END of the method (after all existing setup calls), add:

```swift
        // Respond to runtime toggles of the pinned setting:
        // - true → ensure the dismiss monitor is removed (window stays put)
        // - false → if the window is currently visible, reinstall the monitor
        pinnedCancellable = Settings.shared.$pinned
            .dropFirst()  // skip the initial value; showWindow handles first install
            .sink { [weak self] pinned in
                guard let self else { return }
                if pinned {
                    self.removeDismissMonitors()
                } else if let window = self.windowController.window, window.isVisible {
                    self.installDismissMonitors()
                }
            }
```

`dropFirst()` is important: `Settings.shared.$pinned` emits the current value immediately on subscription, but we don't want that emission to trigger an install/remove (the show-window flow handles the initial install). We only want the subscription to react to subsequent changes.

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: compile success. (If you see "Cannot find 'AnyCancellable'" — you forgot the `import Combine` from Step 2.)

- [ ] **Step 5: Smoke test (the critical one)**

Run: `bash run-debug.sh`

Manual check, in this exact order:

1. **Default state (`pinned == false`)**: open Notaty (click status icon). Window appears. Click anywhere outside the Notaty window → window hides. ✓ (current behavior preserved)
2. **Toggle pin ON**: open Notaty again. Click the pin icon in tab bar (becomes `pin.fill`). Click anywhere outside → **window stays visible**. ✓
3. **Esc still closes when pinned**: with pinned ON, press Esc while focused on the note window → window hides. ✓
4. **Close button still closes when pinned**: with pinned ON, click the red traffic light → window closes. ✓
5. **Toggle pin OFF while window visible**: open Notaty, pin it, then toggle pin OFF via the icon. Click outside → window hides immediately on the next outside click. ✓
6. **Persistence**: pin ON, quit Notaty, relaunch → window opens (or first show after status-icon click) → click outside → window stays. ✓ (pinned state survived restart)

If any of those fails, STOP and report. Don't try to fix it during this task — it's a bug in the wiring that needs diagnosis.

- [ ] **Step 6: Commit**

```bash
git add Sources/Notaty/AppDelegate.swift
git commit -m "feat: gate dismiss-on-outside-click monitor on Settings.shared.pinned"
```

---

## Task 5: Full acceptance criteria walkthrough

This task has no code; it's a manual verification pass against the spec's 10 acceptance criteria. If any fail, the relevant earlier task has a bug.

- [ ] **Step 1: Run `swift build -c release`**

Run: `swift build -c release`
Expected: clean build.

- [ ] **Step 2: Run `bash build.sh` to produce a production .app**

The build script may fail with "already exists" if a previous `dist/Notaty-1.0.app` is present. If so, delete it first:

```bash
rm -rf dist/Notaty-1.0.app && bash build.sh
```

Then launch:

```bash
open dist/Notaty-1.0.app
```

- [ ] **Step 3: Walk the spec's 10 acceptance criteria**

From `docs/superpowers/specs/2026-04-30-pinned-window-design.md` § Acceptance criteria:

1. **Default `pinned == false`**: window auto-hides on outside click — ✓ if Task 4 Step 5.1 passed
2. **`pinned == true`**: window remains visible after outside clicks — ✓ if Task 4 Step 5.2 passed
3. **Tab-bar pin icon updates** (glyph, color, tooltip) when toggled — ✓ if Task 2 Step 4 passed
4. **Settings checkbox updates tab-bar icon and vice versa** (always in sync) — ✓ if Task 3 Step 3 passed
5. **Esc still closes** when pinned — ✓ if Task 4 Step 5.3 passed
6. **Traffic-light close button** still closes when pinned — ✓ if Task 4 Step 5.4 passed
7. **Pinned persists** across app restarts — ✓ if Task 4 Step 5.6 passed
8. **Default value is `false`** — ✓ verify a fresh install (delete UserDefaults plist or use a clean machine) starts unpinned
9. **No crashes** on rapid toggles — flip the toggle 10× in quick succession; should never crash
10. **`swift build -c release` succeeds and `bash build.sh` produces a working `.app`** — ✓ Steps 1–2 above

If all 10 pass, this task is done. Mark off each one explicitly before moving on.

---

## Task 6: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Insert an Unreleased section at the top**

Open `CHANGELOG.md`. The first heading is `# Changelog` followed by `## v1.2.1`. Insert this between them:

```markdown
## Unreleased

- Pin window: keep Notaty's window on top until you close it. Toggle the new pin icon in the tab bar (between the tab strip and the new-note ＋), or check "Keep window on top" in Settings → Window. When pinned, the window no longer hides when you click outside it; Esc and the close button still dismiss as usual.

```

(Keep a blank line after `## Unreleased` and another between the bullet and the next `## v1.2.1` heading.)

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG note for pinned-window toggle"
```

---

## Self-review — coverage against the spec

| Spec section | Covered by |
|---|---|
| State (Settings.shared.pinned) | Task 1 |
| UI — pin icon in tab bar | Task 2 |
| UI — Settings checkbox | Task 3 |
| Behavior — gate dismiss monitor on pinned | Task 4 (Step 1: gate at show-time; Step 3: respond to runtime toggle) |
| Behavior — Esc & close button still dismiss | Verified in Task 4 Step 5.3 / 5.4 (no code change needed; existing handlers don't depend on pinned) |
| Edge case — toggle ON while visible | Task 4 Step 5 (verification) |
| Edge case — toggle OFF while visible | Task 4 Step 5 |
| Edge case — multiple rapid toggles | Task 5 Step 3.9 |
| Persistence | Task 1 (UserDefaults via didSet) + Task 4 Step 5.6 (verification) |
| Default value `false` | Task 1 (UserDefaults.bool defaults to false) + Task 5 Step 3.8 |
| Acceptance criteria 1–10 | Task 5 |
| CHANGELOG | Task 6 |

No spec section is uncovered. No placeholders in the plan.

---

**End of plan.**
