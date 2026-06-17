# Notaty App Store Submission

## App Identity

- App name: Notaty Menu Bar Notes
- Platform: macOS
- Bundle ID: com.aldawsari.NotatyAppstore
- SKU: com.aldawsari.NotatyAppstore
- Version: 0.1
- Minimum macOS: 13.0
- Category: Productivity
- App Store Connect app ID: 6775782063
- App Store version ID: db1f4de3-39ee-43fb-be81-2dd116d113a9
- Valid build ID / delivery UUID: b4602cc1-6e2a-44d0-bc1d-7da072899919

## Build

Use `scripts/package-appstore.sh 0.1` after installing the required signing
certificates:

- Apple Distribution certificate for the app bundle.
- 3rd Party Mac Developer Installer certificate for the upload package.

The output package is `dist/Notaty-0.1.pkg`.

Validated and uploaded successfully with no errors on 2026-06-02. App Store
Connect reports the build as `VALID` and `APP_STORE_ELIGIBLE`.

## Draft Metadata

Subtitle:

Quick notes from the menu bar

Description:

Notaty is a lightweight macOS menu bar app for quick notes. It keeps a compact
floating notes window one click away, supports multiple notes with fast tab
switching, and saves automatically as you type.

Use Notaty to capture short ideas, meeting notes, links, Arabic or English text,
and text recognized from screen selections. The app supports right-to-left text
direction detection, manual writing direction controls, light and dark themes,
launch at login, and simple text export.

Keywords:

notes,notepad,menu bar,quick notes,arabic,rtl,ocr,text

Support URL:

https://Aldawsari.com

Privacy Policy URL:

Required before submission. Add the final URL in App Store Connect.

Review Notes:

Notaty is a menu bar app. After launching, use the menu bar note icon to open
the notes window. The camera button starts screen-region OCR and may require
macOS Screen Recording permission.

## Privacy

Expected answer: Data Not Collected.

Confirm before submission:

- No analytics or telemetry.
- No crash reporting SDK.
- No user accounts.
- No cloud sync.
- Notes are stored locally.
- OCR is performed using Apple Vision APIs on device.

## Screenshots

Required for Mac apps. Prepare at least three 16:10 screenshots in one of these
sizes:

- 1280 x 800
- 1440 x 900
- 2560 x 1600
- 2880 x 1800

Recommended set:

- Main notes window with multiple tabs.
- Settings window showing theme/window controls.
- OCR flow or a note containing recognized text.
