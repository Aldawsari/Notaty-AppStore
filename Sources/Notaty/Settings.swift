import Foundation
import AppKit
import Combine
import ServiceManagement

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum WindowSizePreset: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var size: NSSize {
        switch self {
        case .small: return NSSize(width: 320, height: 220)
        case .medium: return NSSize(width: 420, height: 340)
        case .large: return NSSize(width: 560, height: 440)
        case .extraLarge: return NSSize(width: 720, height: 560)
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var defaultWindowSize: WindowSizePreset {
        didSet {
            UserDefaults.standard.set(defaultWindowSize.rawValue, forKey: Self.sizeKey)
        }
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
            NSApp.appearance = theme.nsAppearance
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Self.launchKey)
            updateLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var autoTranscribe: Bool {
        didSet { UserDefaults.standard.set(autoTranscribe, forKey: Self.autoTranscribeKey) }
    }

    @Published var transcribeLang1: String {
        didSet { UserDefaults.standard.set(transcribeLang1, forKey: Self.lang1Key) }
    }

    @Published var transcribeLang2: String {
        didSet { UserDefaults.standard.set(transcribeLang2, forKey: Self.lang2Key) }
    }

    static let supportedLanguages: [(id: String, label: String)] = [
        ("ar-SA", "Arabic"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("es-ES", "Spanish"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese"),
        ("tr-TR", "Turkish"),
        ("ru-RU", "Russian"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("zh-CN", "Chinese (Simplified)"),
        ("hi-IN", "Hindi"),
        ("ur-PK", "Urdu"),
    ]

    private static let sizeKey = "defaultWindowSize"
    private static let themeKey = "appTheme"
    private static let launchKey = "launchAtLogin"
    private static let autoTranscribeKey = "autoTranscribe"
    private static let lang1Key = "transcribeLang1"
    private static let lang2Key = "transcribeLang2"

    private init() {
        let rawSize = UserDefaults.standard.string(forKey: Self.sizeKey) ?? ""
        self.defaultWindowSize = WindowSizePreset(rawValue: rawSize) ?? .medium

        let rawTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        self.theme = AppTheme(rawValue: rawTheme) ?? .system

        self.autoTranscribe = UserDefaults.standard.object(forKey: Self.autoTranscribeKey) != nil
            ? UserDefaults.standard.bool(forKey: Self.autoTranscribeKey)
            : false
        self.transcribeLang1 = UserDefaults.standard.string(forKey: Self.lang1Key) ?? "ar-SA"
        self.transcribeLang2 = UserDefaults.standard.string(forKey: Self.lang2Key) ?? "en-US"

        // Default to ON if never set
        if UserDefaults.standard.object(forKey: Self.launchKey) == nil {
            self.launchAtLogin = true
            UserDefaults.standard.set(true, forKey: Self.launchKey)
            updateLaunchAtLogin(true)
        } else {
            self.launchAtLogin = UserDefaults.standard.bool(forKey: Self.launchKey)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at Login toggle failed: \(error)")
        }
    }
}
