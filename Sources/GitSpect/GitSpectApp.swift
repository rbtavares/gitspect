import AppKit
import CoreText
import SwiftUI

@main
struct GitSpectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Shared by the main window and Settings (which manages the scanned folders).
    @State private var model = ScanModel()
    @AppStorage("sidebarVisible") private var sidebarVisible = true

    init() {
        // Before any view asks for a font.
        Typeface.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("GitSpect") {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 400)
        }
        // GitSpect draws its own top bar; see WindowChrome.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // In the menu bar rather than on the sidebar's buttons, so the shortcuts work with
            // the sidebar hidden.
            CommandGroup(replacing: .newItem) {
                Button("Add Folders…") { model.chooseFoldersToAdd() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Rescan Folders") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.roots.isEmpty || model.isScanning)
            }
            CommandGroup(after: .textEditing) {
                Button("Filter Repositories") {
                    NotificationCenter.default.post(name: .focusFilter, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model.roots.isEmpty)
            }
            CommandGroup(replacing: .sidebar) {
                Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { sidebarVisible.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button(model.showsOutput ? "Hide Output" : "Show Output") {
                    model.setOutputVisible(!model.showsOutput)
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

extension Notification.Name {
    /// Edit → Filter Repositories: show the sidebar and put the cursor in its filter field.
    static let focusFilter = Notification.Name("GitSpect.focusFilter")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Theme.current.apply()
        #if DEBUG
        Snapshot.scheduleIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Typeface {
    /// Registers the fonts shipped in GitSpect.app (or, for a bare `swift run` from the repo,
    /// the ones in Assets/Fonts) for this process only.
    static func registerBundledFonts() {
        let folders = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/Fonts"),
        ]
        for folder in folders.compactMap({ $0 }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let fonts = files.filter { ["otf", "ttf"].contains($0.pathExtension.lowercased()) }
            guard !fonts.isEmpty else { continue }
            CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
            #if DEBUG
            if ProcessInfo.processInfo.environment["GITSPECT_SNAPSHOT"] != nil { print("fonts from", folder.path) }
            #endif
            return
        }
    }
}

#if DEBUG
/// Development aid: `GITSPECT_SNAPSHOT=<file.png>` writes a picture of the main window a moment
/// after launch and quits, so the interface can be reviewed without screen-recording access.
@MainActor enum Snapshot {
    static func scheduleIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["GITSPECT_SNAPSHOT"] else { return }
        let delay = environment["GITSPECT_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 4
        // "light" or "dark": that appearance with Increase Contrast, whatever the system is set to.
        if let contrast = environment["GITSPECT_STAGE_CONTRAST"] {
            NSApp.appearance = NSAppearance(named: contrast == "dark" ? .accessibilityHighContrastDarkAqua
                                                                      : .accessibilityHighContrastAqua)
        }
        if let keys = environment["GITSPECT_STAGE_KEYS"] {
            // "f:cmd;s:cmd+ctrl;esc": key equivalents pressed one second apart, before the picture.
            for (index, spec) in keys.split(separator: ";").enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay - 2.5 + Double(index) * 0.6) { press(String(spec)) }
            }
        }
        if let size = environment["GITSPECT_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.first?.setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        // "12": that many extra pictures, 60ms apart, leading up to the final one (name-0.png, …).
        let frames = environment["GITSPECT_SNAPSHOT_FRAMES"].flatMap(Int.init) ?? 0
        for frame in 0..<frames {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay - Double(frames - frame) * 0.06) {
                guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let url = URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-\(frame).png"))
                try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let settings = environment["GITSPECT_SNAPSHOT_WINDOW"] == "settings"
            DispatchQueue.main.async {
                let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
                guard let window = settings ? windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true }) : windows.first,
                      let view = window.contentView?.superview,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                if let probe = environment["GITSPECT_HITTEST"] {
                    // "x,y;x,y" from the window's top-left: which view would take a click there.
                    for pair in probe.split(separator: ";") {
                        let xy = pair.split(separator: ",").compactMap { Double($0) }
                        guard xy.count == 2 else { continue }
                        let point = NSPoint(x: xy[0], y: view.bounds.height - xy[1])
                        let hit = view.hitTest(point)
                        print("hit \(pair):", hit.map { String(describing: type(of: $0)).prefix(40) } ?? "nil",
                              "moves window:", hit?.mouseDownCanMoveWindow ?? false)
                    }
                }
                exit(0)
            }
        }
    }

    private static func press(_ spec: String) {
        let parts = spec.split(separator: ":")
        let key = parts.first.map(String.init) ?? ""
        var flags: NSEvent.ModifierFlags = []
        for name in parts.dropFirst().first?.split(separator: "+") ?? [] {
            switch name {
            case "cmd": flags.insert(.command)
            case "ctrl": flags.insert(.control)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        let characters = key == "esc" ? "\u{1B}" : key
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false,
                                           keyCode: key == "esc" ? 53 : 0) else { return }
        let handled = window.performKeyEquivalent(with: event) || NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        print("key \(spec):", handled ? "handled" : "ignored")
    }
}
#endif
