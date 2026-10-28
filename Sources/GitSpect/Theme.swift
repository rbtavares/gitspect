import AppKit

/// Light/dark appearance for every GitSpect window; `system` follows macOS.
enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "theme"

    var id: Self { self }
    var title: String { rawValue.capitalized }

    static var current: Theme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Theme.init(rawValue:)) ?? .system
    }

    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
