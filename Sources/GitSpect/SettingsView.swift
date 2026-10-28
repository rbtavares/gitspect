import SwiftUI

struct SettingsView: View {
    @AppStorage(AppIcon.storageKey) private var icon = AppIcon.dark

    var body: some View {
        Form {
            LabeledContent("App icon") {
                HStack(spacing: 12) {
                    ForEach(AppIcon.allCases) { option in
                        IconOption(icon: option, isSelected: option == icon) { icon = option }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: icon) { icon.apply() }
    }
}

private struct IconOption: View {
    let icon: AppIcon
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                if let image = icon.image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                }
                Text(icon.title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
