import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    private let appVersion = "v0.5"
    private let accent = Color.accentColor

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
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
                .cornerRadius(10)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.9), accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "note.text")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
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
