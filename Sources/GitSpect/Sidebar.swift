import AppKit
import SwiftUI

/// A tree: each added folder, its parent folders (orgs), then repos with their at-a-glance counts.
struct Sidebar: View {
    let roots: [RootNode]
    @Binding var selection: URL?
    @Binding var collapsed: Set<String>
    /// Asks the window to put a question to the user.
    let confirm: (ConfirmRequest) -> Void
    @Environment(ScanModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tree flattened into visible rows, so expansion and indentation are handled here.
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
        // GitSpect's own rows rather than a system list: one highlight colour whatever has
        // keyboard focus, and one row height whatever the system's sidebar size setting.
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(rows) { row in
                    switch row {
                    case .root(let node):
                        FolderRow(title: node.root.lastPathComponent, depth: 0, isExpanded: isExpanded(node.root.path),
                                  isSelected: selection == node.root,
                                  toggle: { toggle(node.root.path) }, click: { clicked(node.root) })
                            .help(node.root.path)
                            .contextMenu {
                                PathActions(path: node.root.path)
                                Divider()
                                // Added folders are only taken out of GitSpect, never deleted.
                                Button("Remove from GitSpect") { model.remove(root: node.root) }
                            }
                    case .folder(let group):
                        FolderRow(title: group.path, depth: 1, isExpanded: isExpanded(group.id),
                                  isSelected: group.url != nil && selection == group.url,
                                  toggle: { toggle(group.id) }, click: { clicked(group.url) })
                            .contextMenu {
                                if let url = group.url {
                                    PathActions(path: url.path)
                                    Divider()
                                    Button("Move to Trash…", role: .destructive) { requestTrash(group) }
                                }
                            }
                    case .repo(let repo, let depth):
                        // Name directly under the parent folder's name, past its chevron.
                        SidebarRow(repo: repo, isSelected: selection == repo.url, depth: depth) { clicked(repo.url) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
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

    /// A click selects the row; clicking the selected row again deselects it.
    private func clicked(_ url: URL?) {
        guard let url else { return }
        selection = selection == url ? nil : url
    }

    private func requestTrash(_ group: RepoGroup) {
        confirm(ConfirmRequest(
            title: "Move “\(group.path)” to the Trash?",
            message: "It holds \(group.repos.count) repositor\(group.repos.count == 1 ? "y" : "ies"), including any uncommitted or unpushed work in them. You can put it back from the Trash.",
            actions: [.init(title: "Move to Trash") { moveToTrash(group) }]
        ))
    }

    private func moveToTrash(_ group: RepoGroup) {
        guard let url = group.url else { return }
        Task {
            do {
                _ = try await NSWorkspace.shared.recycle([url])
            } catch {
                NSAlert(error: error).runModal()
            }
            if selection == url { selection = nil }
            model.rescan()
        }
    }

    private func isExpanded(_ id: String) -> Bool { !collapsed.contains(id) }

    private func toggle(_ id: String) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            if collapsed.remove(id) == nil { collapsed.insert(id) }
        }
    }
}

/// The background every sidebar row shares: clear, lit on hover, solid when selected.
private struct RowBackground: View {
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
            .fill(isSelected ? Palette.selected : isHovered ? Palette.hover : .clear)
    }
}

/// A root or org folder. Selectable like a repo; only its chevron opens and closes it.
private struct FolderRow: View {
    static let chevronWidth: CGFloat = Metric.controlSmall
    static func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 12 }

    let title: String
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let toggle: () -> Void
    /// A click on the name (not the chevron).
    let click: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.textFaint)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: Self.chevronWidth, height: Metric.row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            Text(title)
                .font(.dsBodyMedium)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.indent(depth))
        .padding(.trailing, 8)
        .frame(height: Metric.row)
        .background(RowBackground(isSelected: isSelected, isHovered: isHovered))
        .contentShape(Rectangle())
        .onTapGesture(perform: click)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

struct SidebarRow: View {
    let repo: Repo
    let isSelected: Bool
    let depth: Int
    let click: () -> Void
    @Environment(ScanModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        let statuses = model.statuses[repo.url]?.values ?? [:].values
        let behind = statuses.reduce(0) { $0 + $1.behind }
        let ahead = statuses.reduce(0) { $0 + $1.ahead }

        HStack(spacing: 4) {
            Text(repo.name)
                .font(.dsBody)
                // Quieter than the folder names; full strength once selected or pointed at.
                .foregroundStyle(isSelected || isHovered ? Palette.text : Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            // While git runs on the repo, the spinner stands in for its counts.
            if model.running[repo.url] != nil {
                Spinner(size: 10).padding(.trailing, 4)
            } else {
                if model.errors[repo.url] != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.danger)
                        .help(model.errors[repo.url] ?? "")
                        .accessibilityLabel("Last command failed")
                }
                // Pull/push only take space when non-zero; each pulls or pushes every branch it can.
                if behind > 0 {
                    let branches = model.pullableBranches(in: repo).count
                    SyncPill(symbol: "arrow.down", count: behind, color: Palette.accent) { model.pullAll(in: repo) }
                        .disabled(branches == 0)
                        .help(branches == 0
                              ? "\(behind) commit\(behind == 1 ? "" : "s") behind, but every branch has diverged: needs a merge or rebase"
                              : "Pull \(behind) commit\(behind == 1 ? "" : "s") (fast-forward \(branches) branch\(branches == 1 ? "" : "es"))")
                }
                if ahead > 0 {
                    let branches = model.pushableBranches(in: repo).count
                    SyncPill(symbol: "arrow.up", count: ahead, color: Palette.positive) { model.pushAll(in: repo) }
                        .disabled(branches == 0)
                        .help(branches == 0
                              ? "\(ahead) commit\(ahead == 1 ? "" : "s") ahead, but no branch can be pushed as-is (diverged or a differently named upstream)"
                              : "Push \(ahead) commit\(ahead == 1 ? "" : "s") (\(branches) branch\(branches == 1 ? "" : "es"))")
                }
                // A repo with no remote exists only on this Mac.
                if repo.isLocalOnly {
                    Text("local")
                        .font(.dsCaption)
                        .foregroundStyle(isSelected || isHovered ? Palette.textMuted : Palette.textFaint)
                        .padding(.trailing, 2)
                }
            }
        }
        .padding(.leading, FolderRow.chevronWidth + FolderRow.indent(depth - 1))
        .padding(.trailing, 6)
        .frame(height: Metric.row)
        .background(RowBackground(isSelected: isSelected, isHovered: isHovered))
        .contentShape(Rectangle())
        .onTapGesture(perform: click)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
