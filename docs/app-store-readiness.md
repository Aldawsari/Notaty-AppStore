# Notaty App Store Readiness

Last checked: June 17, 2026

## Review history

- **2026-06-?? — Rejected.** "The app sets itself to auto-launch at startup
  without user consent." Cause: `Settings.swift` defaulted `launchAtLogin` to
  `true` and called `SMAppService.mainApp.register()` on first launch. Fixed in
  build `0.1.1` — launch-at-login now defaults off and registers only on
  explicit user toggle.
- **2026-06-17 — Fix committed and pushed.** Commit `a1fe48d` on `main`
  (pushed to `origin`, `github.com/Aldawsari/Notaty-AppStore`). Verified the
  app no longer registers a login item on a fresh launch.
- **2026-06-17 — Build 0.1.1 uploaded** (Delivery UUID
  `6b6fd529-e532-41d6-bfcc-cf38ba505d59`). Apple returned warning ITMS-90889:
  bundle missing a provisioning profile (not TestFlight-eligible; App Store
  review unaffected).
- **2026-06-17 — Build 0.1.2 uploaded** (Delivery UUID
  `040f422b-41c3-497f-b639-872973228b97`). Embedded a Mac App Store
  provisioning profile (`MAC_APP_STORE`, cert `49G7UGP79B`, bundle
  `S44HWZ9ZH3`) and added `application-identifier` / `team-identifier`
  entitlements. Validation passed with no errors and no warnings — ITMS-90889
  resolved. Use build 0.1.2 for the submission.

## Current App Store Connect state

- App: `Notaty Menu Bar Notes`
- App ID: `6775782063`
- Version: `0.1` (resubmitting with build `0.1.2`)
- Version state: `PREPARE_FOR_SUBMISSION`
- Version ID: `db1f4de3-39ee-43fb-be81-2dd116d113a9`
- Previous build ID: `b4602cc1-6e2a-44d0-bc1d-7da072899919` (rejected, 0.1)
- Uploaded builds: `0.1.1` (warning ITMS-90889), `0.1.2` (clean — use this)

## Resubmission steps (build 0.1.2)

1. Build 0.1.2 uploaded — wait for processing to finish (status `VALID`).
2. Attach the `0.1.2` build to the version.
3. In App Review notes, state: "Launch at Login is now off by default; the app
   no longer registers a login item without explicit user consent."
4. Submit for review.

## Metadata already present

- Description
- Keywords
- Marketing URL
- Support URL
- Copyright

## Assets prepared locally

Mac App Store screenshots were generated locally at:

- `docs/app-store-screenshots/01-main-notes.png`
- `docs/app-store-screenshots/02-settings.png`
- `docs/app-store-screenshots/03-ocr-note.png`

All three files are `2880x1800`, which is a valid 16:10 Mac App Store screenshot size.

## Remaining submission blockers

- Upload the screenshot set to App Store Connect
- Set the app privacy answers in App Store Connect
- Add the published privacy policy URL to App Store Connect:
  `https://lab.aldawsari.com/AppleAppStore/notaty/privacy/`
- Fill App Review contact/details if still empty
- Submit version `0.1` for review

## Notes

`appStoreReviewDetail` returned `null` during the June 9, 2026 check, so review details should be verified before submission.
