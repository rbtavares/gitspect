import AppKit

/// The icon styles rendered by scripts/make-icon.swift. The bundle's built-in icon is the dark one;
/// choosing another swaps the Dock icon while running and sets it as the app's custom icon, so the
/// Dock (when quit), Finder and Spotlight show it too.
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
        let custom = self == .dark ? nil : image
        NSApp.applicationIconImage = custom
        // Like pasting an icon in Finder's Get Info. It adds an "Icon\r" file to the bundle, which
        // code signing ignores, so the signature stays valid. Fails quietly where the app can't
        // write to its bundle.
        NSWorkspace.shared.setIcon(custom, forFile: Bundle.main.bundleURL.path, options: [])
    }
}
