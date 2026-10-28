import AppKit

/// The icon styles rendered by scripts/make-icon.swift. The bundle's own icon (Finder, app
/// switcher before launch) is always dark; the choice here swaps the Dock icon while running.
enum AppIcon: String, CaseIterable, Identifiable {
    case dark, light, blue

    static let storageKey = "appIcon"

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var image: NSImage? {
        Bundle.main.url(forResource: "AppIcon-\(rawValue)", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    static var current: AppIcon {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppIcon.init(rawValue:)) ?? .dark
    }

    @MainActor func apply() {
        // nil restores the bundle icon, which is the dark one.
        NSApp.applicationIconImage = self == .dark ? nil : image
    }
}
