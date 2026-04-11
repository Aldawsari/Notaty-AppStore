import Foundation
import AppKit
import Combine

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

    private static let sizeKey = "defaultWindowSize"
    private static let themeKey = "appTheme"

    private init() {
        let rawSize = UserDefaults.standard.string(forKey: Self.sizeKey) ?? ""
        self.defaultWindowSize = WindowSizePreset(rawValue: rawSize) ?? .medium

        let rawTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        self.theme = AppTheme(rawValue: rawTheme) ?? .system
    }
}
