import SwiftUI
import AppKit
import Sparkle

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    let updater: SPUUpdater?

    private let appVersion = "v1.1"
    private let accent = Color.accentColor

    init(updater: SPUUpdater? = nil) {
        self.updater = updater
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

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

                // ── General ─────────────────────────────────────────────
                sectionHeader("General")

                settingsCard {
                    Toggle(isOn: $settings.launchAtLogin) {
                        rowLabel("Launch at Login")
                    }
                    .toggleStyle(.switch)
                }

                // ── Appearance ───────────────────────────────────────────
                sectionHeader("Appearance")

                settingsCard {
                    rowLabel("Theme")
                    Picker("", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }

                // ── Voice Notes ──────────────────────────────────────────
                sectionHeader("Voice Notes")

                settingsCard {
                    Toggle(isOn: $settings.autoTranscribe) {
                        rowLabel("Auto-transcribe after recording")
                    }
                    .toggleStyle(.switch)

                    Divider()

                    rowLabel("Transcription Languages")
                    Text("The app tries both languages and picks the best match.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Picker("Language 1", selection: $settings.transcribeLang1) {
                            ForEach(Settings.supportedLanguages, id: \.id) { lang in
                                Text(lang.label).tag(lang.id)
                            }
                        }
                        .labelsHidden()

                        Picker("Language 2", selection: $settings.transcribeLang2) {
                            ForEach(Settings.supportedLanguages, id: \.id) { lang in
                                Text(lang.label).tag(lang.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // ── Data ─────────────────────────────────────────────────
                sectionHeader("Data")

                settingsCard {
                    Button {
                        NotatyActions.exportAllNotes()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.doc")
                            Text("Export All Notes")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(accent)

                    Divider()

                    Button {
                        NotatyActions.importNotes()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Import Notes")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(accent)
                }

                // ── About ────────────────────────────────────────────────
                sectionHeader("About")

                settingsCard {
                    HStack(spacing: 14) {
                        appIcon

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Notaty")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(appVersion)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Text("Developed by Abdullah Aldawsari")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Link("Aldawsari.com", destination: URL(string: "https://Aldawsari.com")!)
                                .font(.system(size: 12))
                                .foregroundColor(accent)
                            Text("© 2026")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)

                    if let updater {
                        Button {
                            NSApp.activate(ignoringOtherApps: true); updater.checkForUpdates()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Check for Updates")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(16)
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var appIcon: some View {
        let icon = loadedAppIcon()
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 44, height: 44)
            .cornerRadius(10)
    }

    private func loadedAppIcon() -> NSImage {
        // Prefer the icns shipped in Contents/Resources; fall back to the
        // Finder icon for the bundle path.
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.primary)
    }
}
