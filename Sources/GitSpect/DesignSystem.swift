import AppKit
import SwiftUI

// GitSpect's own look: every colour, size and control the views use is defined here, so nothing
// in the window is drawn by AppKit's stock controls. Menus, tooltips, the open panel and the
// window buttons stay the system's.

// MARK: - Colour

/// Semantic colours. Each resolves for light, dark and their Increase Contrast variants, so the
/// theme setting (which sets `NSApp.appearance`) and the accessibility setting both apply.
///
/// Contrast, computed as WCAG 2.x ratios: `text`, `textMuted` and the four signal colours pass
/// 4.5:1 on every surface, on a selected row, and on their own tint. The one state below that is
/// a count being hovered inside an already selected row (4.1:1 at worst). `textFaint` passes on
/// `sidebar` and `canvas` only, so it is never used on a hovered or selected row.
enum Palette {
    // Surfaces, from furthest back to nearest. The sidebar is the dimmest so the content leads.
    static let sidebar = dynamic(light: 0xF5F5F7, dark: 0x141518)
    static let canvas = dynamic(light: 0xFFFFFF, dark: 0x1A1B1F)
    static let raised = dynamic(light: 0xF0F0F3, dark: 0x212328)
    static let hover = dynamic(light: 0xEBEBEF, dark: 0x26282E)
    static let selected = dynamic(light: 0xE2E3E8, dark: 0x2D3037)
    /// Floating surfaces: dialogs and the selection bar.
    static let overlay = dynamic(light: 0xFFFFFF, dark: 0x25272C)
    static let scrim = dynamic(light: 0x17181B, dark: 0x000000).opacity(0.35)

    static let border = dynamic(light: 0xE7E7EB, dark: 0x282A30, lightContrast: 0x9A9CA5, darkContrast: 0x6C707A)
    static let borderStrong = dynamic(light: 0xD2D3D9, dark: 0x3A3D45, lightContrast: 0x6E717A, darkContrast: 0x9A9EA8)

    static let text = dynamic(light: 0x17181B, dark: 0xEDEEF0, lightContrast: 0x000000, darkContrast: 0xFFFFFF)
    static let textMuted = dynamic(light: 0x565961, dark: 0xA9ACB4, lightContrast: 0x2E3036, darkContrast: 0xD6D8DD)
    static let textFaint = dynamic(light: 0x676A73, dark: 0x8C9099, lightContrast: 0x45484F, darkContrast: 0xB9BCC4)

    /// Selection, links and the one primary action. Also "behind": commits to pull.
    static let accent = dynamic(light: 0x0A4DB8, dark: 0x6AADFF, lightContrast: 0x033785, darkContrast: 0x9CC9FF)
    /// Fill behind white text.
    static let accentFill = dynamic(light: 0x0B5FDB, dark: 0x2A6FDB)
    /// "Ahead": commits to push, and success.
    static let positive = dynamic(light: 0x0A6234, dark: 0x4CC38A, lightContrast: 0x064724, darkContrast: 0x7DDCAD)
    /// Diverged, detached, untrusted: needs a look, nothing lost.
    static let caution = dynamic(light: 0x7A4700, dark: 0xE8A33D, lightContrast: 0x6F4100, darkContrast: 0xF5C06F)
    /// Errors and anything that deletes.
    static let danger = dynamic(light: 0xA81E1B, dark: 0xF78A85, lightContrast: 0x7D0F0D, darkContrast: 0xFFAFAC)
    static let dangerFill = dynamic(light: 0xC62B27, dark: 0xC9423D)

    /// How strongly a colour washes the background behind its own text (tags, counts, selected
    /// rows). Kept low so the text still passes 4.5:1 on top of it.
    static let tint = 0.12
    static let tintHover = 0.18

    /// Commit graph lanes: distinct hues at similar weight, so no lane shouts over the others.
    static let lanes: [Color] = [
        dynamic(light: 0x0B5FDB, dark: 0x5BA4FF),
        dynamic(light: 0x0E7A43, dark: 0x4CC38A),
        dynamic(light: 0xB25E00, dark: 0xE8A33D),
        dynamic(light: 0x7A45D6, dark: 0xA98BFA),
        dynamic(light: 0xC2317C, dark: 0xF07DB4),
        dynamic(light: 0x0B7C86, dark: 0x4FC3CF),
        dynamic(light: 0xC62B27, dark: 0xF26D68),
        dynamic(light: 0x5B6270, dark: 0x9AA1AE),
    ]

    private static func dynamic(light: UInt32, dark: UInt32, lightContrast: UInt32? = nil,
                                darkContrast: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            let hex = switch match {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: lightContrast ?? light
            case .accessibilityHighContrastDarkAqua: darkContrast ?? dark
            default: light
            }
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Metrics

/// Sizes on a 4pt grid. Everything clickable is at least 24pt in one direction (WCAG 2.2's
/// minimum target size), even where the drawn shape is smaller.
enum Metric {
    /// The strip along the top of the window, level with the window buttons.
    static let topBar: CGFloat = 44
    /// Headers of panes: column titles, graph, commit, output.
    static let paneHeader: CGFloat = 32
    /// Rows in the sidebar and the branch list.
    static let row: CGFloat = 28
    static let control: CGFloat = 28
    static let controlSmall: CGFloat = 24

    static let radiusSmall: CGFloat = 4
    static let radius: CGFloat = 6
    static let radiusLarge: CGFloat = 10

    /// Hover and press feedback: fast enough to feel immediate.
    static let quick = 0.1
    /// Panes and bars moving in and out.
    static let slide = 0.22
}

// MARK: - Type

/// Geist for the interface and Geist Mono for everything git says (branches, hashes, paths,
/// output). The fonts ship inside GitSpect.app; a bare `swift run` falls back to the system's.
enum Typeface {
    private static let hasGeist = NSFont(name: "Geist-Regular", size: 12) != nil
    private static let hasGeistMono = NSFont(name: "GeistMono-Regular", size: 12) != nil

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard hasGeist else { return .system(size: size, weight: weight) }
        return .custom("Geist-" + name(weight), fixedSize: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard hasGeistMono, let font = NSFont(name: "GeistMono-" + name(weight), size: size) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        // Without ligatures and contextual alternates: Geist Mono otherwise redraws runs like
        // " --" and "->", so `git fetch --all` loses its spaces and streaming output shifts
        // sideways as characters arrive. Git's text is shown exactly as git wrote it.
        let features = ["liga", "calt", "dlig"].map { tag in
            [NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): tag,
             NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): 0] as [NSFontDescriptor.FeatureKey: Any]
        }
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: features])
        return Font(NSFont(descriptor: descriptor, size: size) ?? font)
    }

    private static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Medium"
        case .semibold, .bold, .heavy, .black: "SemiBold"
        default: "Regular"
        }
    }
}

extension Font {
    /// Window and dialog titles.
    static let dsTitle = Typeface.ui(13, .semibold)
    /// Names in lists, button labels, body copy.
    static let dsBody = Typeface.ui(13)
    static let dsBodyMedium = Typeface.ui(13, .medium)
    /// Pane headers and secondary copy.
    static let dsLabel = Typeface.ui(12, .medium)
    static let dsSmall = Typeface.ui(12)
    /// Paths, timestamps, hints.
    static let dsCaption = Typeface.ui(11)
    static let dsCaptionMedium = Typeface.ui(11, .medium)
    /// Branch names and other git identifiers.
    static let dsMono = Typeface.mono(12)
    static let dsMonoSmall = Typeface.mono(11)
    static let dsMonoSmallMedium = Typeface.mono(11, .medium)
}

// MARK: - Controls

/// A one-pixel rule. Structure is kept quiet: felt more than seen.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Palette.border
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

/// GitSpect's buttons. `primary` is the one filled action in a view; `secondary` has an outline;
/// `ghost` is bare until hovered; `danger` deletes.
struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }

    var kind = Kind.secondary
    var small = false
    /// Stretches to the width offered.
    var fills = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, small: small, fills: fills)
    }

    private struct Face: View {
        let configuration: Configuration
        let kind: Kind
        let small: Bool
        let fills: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            configuration.label
                .font(small ? .dsLabel : .dsBodyMedium)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, small ? 8 : 12)
                .frame(maxWidth: fills ? .infinity : nil)
                .frame(height: small ? Metric.controlSmall : Metric.control)
                .background(background, in: shape)
                .overlay { if kind == .secondary { shape.strokeBorder(Palette.borderStrong, lineWidth: 1) } }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: Metric.quick), value: isHovered)
                .animation(.easeOut(duration: Metric.quick), value: configuration.isPressed)
        }

        private var active: Bool { isEnabled && (isHovered || configuration.isPressed) }

        private var foreground: Color {
            switch kind {
            case .primary, .danger: .white
            case .secondary, .ghost: Palette.text
            }
        }

        private var background: Color {
            let pressed = configuration.isPressed && isEnabled
            switch kind {
            case .primary: return Palette.accentFill.opacity(pressed ? 0.8 : active ? 0.9 : 1)
            case .danger: return Palette.dangerFill.opacity(pressed ? 0.8 : active ? 0.9 : 1)
            case .secondary: return pressed ? Palette.selected : active ? Palette.hover : Palette.raised.opacity(0.6)
            case .ghost: return pressed ? Palette.selected : active ? Palette.hover : .clear
            }
        }
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    static var ds: DSButtonStyle { DSButtonStyle() }
    static func ds(_ kind: DSButtonStyle.Kind, small: Bool = false, fills: Bool = false) -> DSButtonStyle {
        DSButtonStyle(kind: kind, small: small, fills: fills)
    }
}

/// A bare icon in a 24pt target that lights up on hover.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
        }
        .buttonStyle(IconButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconFace(configuration: configuration)
    }

    private struct IconFace: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            configuration.label
                .foregroundStyle(isHovered && isEnabled ? Palette.text : Palette.textMuted)
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .background(configuration.isPressed ? Palette.selected : isHovered && isEnabled ? Palette.hover : .clear,
                            in: shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: Metric.quick), value: isHovered)
        }
    }
}

/// A small spinning arc: something is running.
struct Spinner: View {
    var size: CGFloat = 12
    @State private var isSpinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 1)
            .stroke(Palette.textMuted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 0.8).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
            .accessibilityLabel("Working")
    }
}

/// A short tinted label on a row: "main", "detached", "missing".
struct Tag: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color = Palette.textMuted) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.dsMonoSmallMedium)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color.opacity(Palette.tint), in: RoundedRectangle(cornerRadius: Metric.radiusSmall, style: .continuous))
            .fixedSize()
    }
}

/// The bar at the top of a pane: a title, then whatever the pane adds.
struct PaneHeader<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: Metric.paneHeader)
            .background(Palette.canvas)
            .overlay(alignment: .bottom) { Hairline() }
    }
}

/// One key of a shortcut.
struct Keycap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.dsCaptionMedium)
            .foregroundStyle(Palette.textMuted)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 2)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Metric.radiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusSmall, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
    }
}

/// What a pane shows when it has nothing: what's missing and what to do about it.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.textFaint)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title)
                    .font(Typeface.ui(15, .semibold))
                    .foregroundStyle(Palette.text)
                Text(message)
                    .font(.dsBody)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 340)
            }
            actions
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A choice between a few options, as one control.
struct SegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button(option.title) { selection = option.value }
                    .buttonStyle(Segment(isOn: isOn))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Metric.radius + 2, style: .continuous))
    }

    private struct Segment: ButtonStyle {
        let isOn: Bool

        func makeBody(configuration: Configuration) -> some View {
            let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            configuration.label
                .font(.dsLabel)
                .foregroundStyle(isOn ? Palette.text : Palette.textMuted)
                .padding(.horizontal, 14)
                .frame(height: Metric.controlSmall)
                .background(isOn ? Palette.overlay : .clear, in: shape)
                .overlay { if isOn { shape.strokeBorder(Palette.borderStrong, lineWidth: 1) } }
                .contentShape(shape)
        }
    }
}

/// A question that needs an answer before anything else happens, over a dimmed window.
/// Escape and a click outside both cancel; nothing destructive is the default.
struct ConfirmRequest {
    struct Action: Identifiable {
        var id: String { title }
        let title: String
        var isDestructive = true
        let run: () -> Void
    }

    let title: String
    let message: String
    let actions: [Action]
}

struct ConfirmDialog: View {
    let request: ConfirmRequest
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Palette.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.title)
                        .font(Typeface.ui(15, .semibold))
                        .foregroundStyle(Palette.text)
                    ScrollView {
                        Text(request.message)
                            .font(.dsSmall)
                            .foregroundStyle(Palette.textMuted)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 240)
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(request.actions) { action in
                        Button(action.title) {
                            dismiss()
                            action.run()
                        }
                        .buttonStyle(.ds(action.isDestructive ? .danger : .primary, fills: true))
                    }
                    Button("Cancel", action: dismiss)
                        .buttonStyle(.ds(.secondary, fills: true))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(Palette.overlay, in: RoundedRectangle(cornerRadius: Metric.radiusLarge + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.radiusLarge + 2, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
            .accessibilityAddTraits(.isModal)
        }
    }
}
