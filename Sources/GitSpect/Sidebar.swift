import SwiftUI

/// A tree: each added folder, its parent folders (orgs), then repos with their at-a-glance counts.
struct Sidebar: View {
    let roots: [RootNode]
    @Binding var selection: URL?
    @Binding var collapsed: Set<String>
    @Environment(ScanModel.self) private var model

    /// The tree flattened into visible rows. Nested DisclosureGroups in a List leave stale
    /// rows behind when collapsed, so expansion and indentation are handled here instead.
    private enum Row: Identifiable {
        case root(RootNode)
        case folder(RepoGroup)
        case repo(Repo, depth: Int)

        var id: String {
            switch self {
            case .root(let node): "root:" + node.root.path
            case .folder(let group): "folder:" + group.id
            case .repo(let repo, _): "repo:" + repo.url.path
            }
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                switch row {
                case .root(let node):
                    FolderRow(title: node.root.lastPathComponent, depth: 0,
                              isExpanded: isExpanded(node.root.path)) { toggle(node.root.path) }
                        .fontWeight(.semibold)
                        .help(node.root.path)
                        .contextMenu {
                            PathActions(path: node.root.path)
                            Divider()
                            Button("Remove Folder") { model.remove(root: node.root) }
                        }
                case .folder(let group):
                    FolderRow(title: group.path, depth: 1,
                              isExpanded: isExpanded(group.id)) { toggle(group.id) }
                case .repo(let repo, let depth):
                    SidebarRow(repo: repo)
                        .padding(.leading, FolderRow.indent(depth) + FolderRow.chevronWidth)
                        .tag(repo.url)
                }
            }
        }
        .listStyle(.sidebar)
        // Compact rows regardless of the system's sidebar icon size setting. Small rows shrink text
        // to 11pt, so folder and repo names set 13pt on their own text.
        .environment(\.sidebarRowSize, .small)
    }

    private var rows: [Row] {
        var rows: [Row] = []
        for node in roots {
            rows.append(.root(node))
            guard isExpanded(node.root.path) else { continue }
            for group in node.groups {
                if group.path.isEmpty {
                    rows += group.repos.map { .repo($0, depth: 1) }
                } else {
                    rows.append(.folder(group))
                    if isExpanded(group.id) { rows += group.repos.map { .repo($0, depth: 2) } }
                }
            }
        }
        return rows
    }

    private func isExpanded(_ id: String) -> Bool { !collapsed.contains(id) }

    private func toggle(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if collapsed.remove(id) == nil { collapsed.insert(id) }
        }
    }
}

/// A root or org folder: not selectable; a click anywhere on it opens or closes it.
private struct FolderRow: View {
    static let chevronWidth: CGFloat = 14
    static func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 14 }

    let title: String
    let depth: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: Self.chevronWidth)
            Label {
                // On the text itself, like repo names: the sidebar's label style overrides a font
                // set on the whole Label.
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "folder.fill")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.indent(depth))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .selectionDisabled()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
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
            Label {
                Text(repo.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                // Tinted when the repo has a remote; grey when it exists only on this Mac.
                if repo.isLocalOnly {
                    Image(systemName: "book.closed").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "book.closed")
                }
            }
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
        .help(repo.url.path + "\n" + (repo.remotes.first.map { "\($0.name): \($0.displayName)" } ?? "Local only: no remote"))
        .contextMenu {
            Button("Fetch") { Task { await model.fetch(repo) } }
                .disabled(model.running[repo.url] != nil || repo.isLocalOnly)
            if let web = repo.remotes.first?.webURL {
                Button("Open \(web.host ?? "Remote") Page") { NSWorkspace.shared.open(web) }
            }
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
