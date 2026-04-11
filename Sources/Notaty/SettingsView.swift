import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section("Window") {
                Picker("Default size", selection: $settings.defaultWindowSize) {
                    ForEach(WindowSizePreset.allCases) { preset in
                        Text("\(preset.label)  (\(Int(preset.size.width))×\(Int(preset.size.height)))")
                            .tag(preset)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 340)
    }
}
