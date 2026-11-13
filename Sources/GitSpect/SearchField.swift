import SwiftUI

/// The sidebar's filter: a magnifier, the text, and a clear button once there's something to clear.
/// ⌘F (Edit → Filter Repositories) puts the cursor in it; Escape empties it.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    /// Changes each time the cursor is asked for.
    var focusRequests = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textFaint)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Palette.textFaint))
                .textFieldStyle(.plain)
                .font(.dsBody)
                .foregroundStyle(Palette.text)
                .focused($isFocused)
                .onExitCommand {
                    if text.isEmpty { isFocused = false } else { text = "" }
                }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textFaint)
                        // A 24pt target around the 12pt glyph.
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -6)
                .help("Clear filter")
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Metric.control)
        .background(Palette.canvas, in: shape)
        // The border doubles as the focus ring.
        .overlay(shape.strokeBorder(isFocused ? Palette.accent : Palette.borderStrong, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { isFocused = true }
        .onChange(of: focusRequests) { isFocused = true }
    }
}
