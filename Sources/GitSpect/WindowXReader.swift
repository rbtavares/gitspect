import AppKit
import SwiftUI

/// Reports where a view's left edge sits in its window, whenever the window or a split view
/// (the sidebar) changes size. Toolbar items live in a separate view hierarchy from the content,
/// so this is how the two are lined up.
struct WindowXReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastX: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            let onNotification: @Sendable (Notification) -> Void = { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            observers = [
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: onNotification),
                center.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: .main,
                                   using: onNotification),
            ]
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard window != nil else { return }
            let x = convert(bounds, to: nil).minX
            guard x != lastX else { return }
            lastX = x
            // Not during a SwiftUI update: the callback changes state.
            DispatchQueue.main.async { [weak self] in self?.onChange?(x) }
        }
    }
}
