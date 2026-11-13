import SwiftUI

/// Settings on one page: the folders to scan, then how GitSpect looks.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model
    @AppStorage(Theme.storageKey) private var theme = Theme.system

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Scanned folders",
                    note: "Git repositories inside each folder appear in the sidebar, grouped by their parent folder.") {
                VStack(spacing: 0) {
                    if model.roots.isEmpty {
                        Text("No folders added yet.")
                            .font(.dsBody)
                            .foregroundStyle(Palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                    }
                    ForEach(Array(model.roots.enumerated()), id: \.element) { index, root in
                        if index > 0 { Hairline() }
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(root.lastPathComponent)
                                    .font(.dsBodyMedium)
                                    .foregroundStyle(Palette.text)
                                Text((root.path as NSString).abbreviatingWithTildeInPath)
                                    .font(.dsMonoSmall)
                                    .foregroundStyle(Palette.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Remove") { model.remove(root: root) }
                                .buttonStyle(.ds(.ghost, small: true))
                                .help("Stop scanning \(root.lastPathComponent). Nothing is deleted.")
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 8)
                        .frame(height: 48)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Metric.radiusLarge, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1))
                Button("Add Folders…", action: model.chooseFoldersToAdd)
                    .buttonStyle(.ds)
            }

            section("Appearance", note: "System follows the macOS appearance setting.") {
                SegmentedControl(options: Theme.allCases.map { ($0, $0.title) }, selection: $theme)
            }
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
        .frame(minHeight: 320, alignment: .top)
        .background(Palette.canvas)
        .onChange(of: theme) { theme.apply() }
    }

    private func section(_ title: String, note: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dsTitle)
                    .foregroundStyle(Palette.text)
                Text(note)
                    .font(.dsSmall)
                    .foregroundStyle(Palette.textMuted)
            }
            content()
        }
    }
}
