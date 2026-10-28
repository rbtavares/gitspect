import SwiftUI

/// The standard macOS settings window: one tab per area, each a grouped form.
struct SettingsView: View {
    var body: some View {
        TabView {
            FoldersSettings()
                .tabItem { Label("Folders", systemImage: "folder") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 500)
    }
}

private struct FoldersSettings: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        Form {
            Section {
                if model.roots.isEmpty {
                    Text("No folders added yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.roots, id: \.self) { root in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(root.lastPathComponent)
                            Text((root.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button { model.remove(root: root) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(root.lastPathComponent)")
                    }
                }
            } header: {
                Text("Scanned Folders")
            } footer: {
                HStack(alignment: .top) {
                    Text("Git repositories inside each folder appear in the sidebar, grouped by their parent folder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Folders…", action: model.chooseFoldersToAdd)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 280)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Theme.storageKey) private var theme = Theme.system

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("System follows the macOS appearance setting.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 160)
        .onChange(of: theme) { theme.apply() }
    }
}
