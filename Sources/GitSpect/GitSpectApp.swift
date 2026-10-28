import AppKit
import SwiftUI

@main
struct GitSpectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Shared by the main window and Settings (which manages the scanned folders).
    @State private var model = ScanModel()

    var body: some Scene {
        WindowGroup("GitSpect") {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 400)
        }
        // Full-height toolbar without the title text: the selected repo is shown there instead.
        // (Removing the title from a default toolbar shrinks it to the compact height.)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // View menu, next to Show/Hide Sidebar, like Xcode's debug area.
            CommandGroup(after: .sidebar) {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Theme.current.apply()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
