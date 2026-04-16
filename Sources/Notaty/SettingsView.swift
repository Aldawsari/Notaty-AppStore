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
                }

                settingsCard {
                    EnhancedTranscriptionSection(settings: settings)
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

// MARK: - Enhanced Transcription Section

private struct EnhancedTranscriptionSection: View {
    @ObservedObject var settings: Settings
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var errorText = ""

    var body: some View {
        Toggle(isOn: $settings.enhancedTranscription) {
            Text("Enhanced Transcription")
                .font(.system(size: 13))
        }
        .toggleStyle(.switch)
        .disabled(isDownloading)
        .onChange(of: settings.enhancedTranscription) { enabled in
            if enabled && !settings.enhancedModelReady {
                downloadModel()
            }
        }

        Text("Uses a larger AI model (~600 MB download, one-time) for better accuracy, mixed-language support (e.g. Arabic + English in the same sentence), and more languages.")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if settings.enhancedTranscription {
            if isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("Downloading model...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            } else if settings.enhancedModelReady {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("Model ready")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }

        if !errorText.isEmpty {
            Text(errorText)
                .font(.system(size: 11))
                .foregroundColor(.red)
        }
    }

    private func downloadModel() {
        if SpeechTranscriber.checkEnhancedModelCached() {
            settings.enhancedModelReady = true
            return
        }

        isDownloading = true
        downloadProgress = 0
        errorText = ""

        Task {
            do {
                try await SpeechTranscriber.downloadEnhancedModel { progress in
                    Task { @MainActor in
                        downloadProgress = progress
                    }
                }
                await MainActor.run {
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    settings.enhancedTranscription = false
                    errorText = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
