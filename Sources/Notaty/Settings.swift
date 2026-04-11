import Foundation
import AppKit
import Combine

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

    private static let sizeKey = "defaultWindowSize"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.sizeKey) ?? ""
        self.defaultWindowSize = WindowSizePreset(rawValue: raw) ?? .medium
    }
}
