import AppKit
import SwiftUI

/// AppKit's search field (magnifier, placeholder, clear button), placed like any other view.
/// SwiftUI's `.searchable` sidebar field positions itself and moves when the sidebar's content changes.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        // The clear button reports through the action rather than a text change.
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        // Follows SwiftUI's .controlSize, so it matches the buttons beside it (28pt at large).
        let size: NSControl.ControlSize = switch context.environment.controlSize {
        case .mini: .mini
        case .small: .small
        case .large, .extraLarge: .large
        default: .regular
        }
        if field.controlSize != size {
            field.controlSize = size
            field.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func changed(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }
    }
}
