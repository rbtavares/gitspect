import SwiftUI

/// Orgs as collapsible sections, each repo with its at-a-glance counts.
struct Sidebar: View {
    let groups: [RepoGroup]
    let rootName: String
    @Binding var selection: URL?
    @Binding var collapsed: Set<String>

    var body: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section(isExpanded: expansion(group.id)) {
                    ForEach(group.repos) { SidebarRow(repo: $0).tag($0.url) }
                } header: {
                    Text(group.id.isEmpty ? rootName : group.id)
                }
            }
        }
        .listStyle(.sidebar)
        // Compact rows regardless of the system's sidebar icon size setting.
        .environment(\.sidebarRowSize, .small)
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { if $0 { collapsed.remove(id) } else { collapsed.insert(id) } }
        )
    }
}

struct SidebarRow: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model

    var body: some View {
        let statuses = model.statuses[repo.url]?.values ?? [:].values
        let behind = statuses.reduce(0) { $0 + $1.behind }
        let ahead = statuses.reduce(0) { $0 + $1.ahead }

        HStack(spacing: 6) {
            Text(repo.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if model.running[repo.url] != nil {
                ProgressView().controlSize(.mini)
            } else if model.errors[repo.url] != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .help(model.errors[repo.url] ?? "")
            }
            // Pull/push only take space when non-zero.
            Metric(symbol: "arrow.down", count: behind, color: .blue)
                .help("\(behind) commit\(behind == 1 ? "" : "s") to pull")
            Metric(symbol: "arrow.up", count: ahead, color: .green)
                .help("\(ahead) commit\(ahead == 1 ? "" : "s") to push")
        }
        // Sets repos visually under their org header.
        .padding(.leading, 8)
        .help(repo.url.path)
        .contextMenu {
            Button("Fetch") { Task { await model.fetch(repo) } }
                .disabled(model.running[repo.url] != nil)
            Divider()
            PathActions(path: repo.url.path)
        }
    }
}

/// An icon and count, hidden at zero.
private struct Metric: View {
    let symbol: String
    let count: Int
    let color: Color

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text("\(count)").font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(color)
            .fixedSize()
        }
    }
}
