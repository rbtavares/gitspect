import AppKit
import SwiftUI

/// Turns the window into a bare frame for GitSpect's own top bar: no title bar or toolbar is
/// drawn, the content runs to the top edge, and the window buttons are centred in the bar.
struct WindowChrome: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> ChromeView { ChromeView() }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.fullScreenChanged = { isFullScreen = $0 }
    }

    final class ChromeView: NSView {
        var fullScreenChanged: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(Palette.canvas)
            // The filter field would otherwise take the cursor, and its focus ring, at launch.
            DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }

            // AppKit puts the buttons back whenever it lays the title bar out again.
            let relayout: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification,
            ]
            for name in relayout {
                observe(name, in: window) { $0.placeWindowButtons() }
            }
            observe(NSWindow.willEnterFullScreenNotification, in: window) { $0.fullScreenChanged?(true) }
            observe(NSWindow.didExitFullScreenNotification, in: window) { $0.fullScreenChanged?(false) }
            // And whenever it resizes the title bar itself.
            if let container = window.standardWindowButton(.closeButton)?.superview?.superview {
                container.postsFrameChangedNotifications = true
                observe(NSView.frameDidChangeNotification, in: container) { $0.placeWindowButtons() }
            }
            for type in WindowButtons.types {
                guard let button = window.standardWindowButton(type) else { continue }
                button.postsFrameChangedNotifications = true
                observe(NSView.frameDidChangeNotification, in: button) { $0.placeWindowButtons() }
            }
            placeWindowButtons()
        }

        private func observe(_ name: Notification.Name, in object: AnyObject, _ action: @escaping @MainActor (ChromeView) -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self)
                }
            })
        }

        override func layout() {
            super.layout()
            placeWindowButtons()
        }

        private var isRecheckPending = false

        /// Makes the title bar area as tall as the top bar and centres the close, minimise and
        /// zoom buttons in it. In full screen the system owns them, so they're left alone.
        private func placeWindowButtons() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let container = close.superview?.superview else { return }
            var frame = container.frame
            frame.size.height = Metric.topBar
            frame.origin.y = window.frame.height - Metric.topBar
            if container.frame != frame { container.frame = frame }
            for (index, type) in WindowButtons.types.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let origin = NSPoint(x: WindowButtons.leading + CGFloat(index) * WindowButtons.spacing,
                                     y: ((Metric.topBar - button.frame.height) / 2).rounded())
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
            // AppKit may still be part-way through its own pass and move a button after this,
            // so look once more when it's done.
            guard !isRecheckPending else { return }
            isRecheckPending = true
            DispatchQueue.main.async { [weak self] in
                self?.isRecheckPending = false
                self?.settleWindowButtons()
            }
        }

        /// Places the buttons only if something moved them, so a settled layout stays quiet.
        private func settleWindowButtons() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let expected = ((Metric.topBar - (window.standardWindowButton(.closeButton)?.frame.height ?? 0)) / 2).rounded()
            let moved = WindowButtons.types.enumerated().contains { index, type in
                guard let button = window.standardWindowButton(type) else { return false }
                return button.frame.origin != NSPoint(x: WindowButtons.leading + CGFloat(index) * WindowButtons.spacing, y: expected)
            }
            if moved { placeWindowButtons() }
        }
    }
}

enum WindowButtons {
    static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    static let leading: CGFloat = 16
    static let spacing: CGFloat = 20
    /// Room to leave at the leading edge of whatever sits beside the buttons.
    static let width: CGFloat = leading + spacing * 2 + 14 + 12
}

/// An empty stretch of the top bar: drag it to move the window, double-click it to zoom or
/// minimise, whichever the system is set to.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            guard event.clickCount == 2 else {
                window.performDrag(with: event)
                return
            }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "None": break
            case "Minimize": window.performMiniaturize(nil)
            default: window.performZoom(nil)
            }
        }
    }
}
