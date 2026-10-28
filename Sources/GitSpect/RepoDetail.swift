import AppKit
import SwiftUI

/// The selected repo: branches (left) and worktrees (right), paired row by row.
struct RepoDetail: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Share of the width below the header taken by the graph pane; starts as an even split.
    @AppStorage("graphFraction") private var graphFraction = 0.5

    static let columnGap: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            errorBanner
            // The graph pane opens beside the list.
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    pairList
                        .frame(maxWidth: .infinity)
                        // Snap to the new width instead of animating it, so text doesn't reflow mid-motion.
                        .transaction { $0.animation = nil }
                    if let target = model.graphTarget, target.repo == repo.url {
                        GraphPane(target: target, fraction: $graphFraction, totalWidth: proxy.size.width)
                            // Slides over the list, which has already snapped to its new width.
                            .transition(.move(edge: .trailing))
                            .zIndex(1)
                    }
                }
                .clipped()
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.graphTarget == nil)
            }
        }
    }

    private var pairList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(repo.pairs) { PairRow(pair: $0, repo: repo).padding(.trailing, 12) }
                } header: {
                    columnTitles
                }
            }
            // Room for the floating selection bar.
            .padding(.bottom, 64)
        }
    }

    /// Errors from the last git command on this repo. The name, path and remote live in the toolbar.
    @ViewBuilder private var errorBanner: some View {
        if let error = model.errors[repo.url] {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(3)
                .textSelection(.enabled)
                .help(error)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var columnTitles: some View {
        HStack(spacing: 0) {
            ColumnTitle("Branches", count: repo.branches.count)
            Color.clear.frame(width: Self.columnGap)
            ColumnTitle("Worktrees", count: repo.worktrees.count)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        // Matches the graph pane's header, so the two read as one bar when it's open.
        .frame(height: GraphPane.headerHeight)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The selected repo's name, path and remote, with its Fetch button. Shown in the window toolbar.
struct RepoTitle: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model

    var body: some View {
        // Name over path and remote, like a window title and subtitle.
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 14) {
                    Text((repo.url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(repo.url.path)
                    remoteBadge
                }
            }
        }
        .padding(.horizontal, 8)
        .contextMenu { PathActions(path: repo.url.path) }
    }

    /// Where the repo is published: a link to the remote's page, or a "Local only" tag.
    @ViewBuilder private var remoteBadge: some View {
        if let remote = repo.remotes.first {
            // Toolbars reduce a Label to its icon, so icon and text are laid out by hand.
            let label = HStack(spacing: 4) {
                Image(systemName: "network")
                Text(remote.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 11))
            let others = repo.remotes.dropFirst().map(\.name)
            let help = "\(remote.name): \(remote.url)" + (others.isEmpty ? "" : "\nAlso: " + others.joined(separator: ", "))
            if let web = remote.webURL {
                Link(destination: web) { label }
                    .help(help + "\nOpen in browser")
            } else {
                label
                    .foregroundStyle(.secondary)
                    .help(help)
            }
        } else {
            Text("Local only")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .help("This repository has no remote, so it exists only on this Mac.")
        }
    }

}

/// Fetches the selected repo; sits at the trailing end of the toolbar.
struct RepoFetchButton: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model

    var body: some View {
        Button {
            Task { await model.fetch(repo) }
        } label: {
            if model.running[repo.url] == .fetch {
                Label("Fetching…", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Fetch", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
        }
        .disabled(model.running[repo.url] != nil || repo.isLocalOnly)
        .help(repo.isLocalOnly ? "No remote to fetch from" : "git fetch --all --prune")
    }
}

/// Styled like the other pane headers (Output, graph, commit): 11pt semibold, count in grey.
private struct ColumnTitle: View {
    let text: String
    let count: Int
    init(_ text: String, count: Int) { self.text = text; self.count = count }

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PairRow: View {
    let pair: CheckoutPair
    let repo: Repo
    @State private var isHovered = false
    @Environment(ScanModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            branchCell.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: RepoDetail.columnGap)
            worktreeCell.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 22)
        .padding(.leading, 20)
        .background {
            // A branch and its worktree are one line: selected rows are filled, and the outline
            // marks the row whose graph is open.
            let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
            shape
                .fill(isSelected ? Color.accentColor.opacity(isHovered ? 0.28 : 0.2)
                      : isHovered ? Color.secondary.opacity(0.08) : .clear)
                .overlay(shape.strokeBorder(Color.accentColor.opacity(isGraphed ? 0.8 : 0), lineWidth: 1))
                .padding(.leading, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { click() }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering } }
    }

    /// What deleting this row removes; nil for rows that can't be deleted (the main checkout).
    private var rowItem: Selectable? { repo.rowItem(pair) }

    private var isSelected: Bool { rowItem.map(model.selection.contains) ?? false }

    /// The row's branch: the branch itself, or the one its worktree has checked out.
    private var graphTarget: GraphTarget? {
        guard let branch = pair.branch, repo.branches.contains(branch) else { return nil }
        return GraphTarget(repo: repo.url, branch: branch)
    }

    private var isGraphed: Bool { graphTarget != nil && model.graphTarget == graphTarget }

    /// ⌘-click toggles the row in the bulk selection and ⇧-click extends it. A plain click shows or
    /// hides the row's graph and, like a list, clears the selection.
    private func click() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if let rowItem { model.select(rowItem, mode: flags.contains(.shift) ? .extend : .toggle) }
            return
        }
        model.clearSelection()
        if let graphTarget { model.toggleGraph(graphTarget) }
    }

    @ViewBuilder private var rowMenu: some View {
        if let target = graphTarget {
            Button(model.graphTarget == target ? "Hide Graph" : "Show Graph") { model.toggleGraph(target) }
        }
        if let rowItem {
            Divider()
            Button(model.deleteTitle(for: [rowItem]) + "…", role: .destructive) { model.requestDeletion([rowItem]) }
        }
    }

    // MARK: Branch side

    // Containers stay unconditional so empty cells still hold their half of the row.
    private var branchCell: some View {
        HStack(spacing: 5) {
            if let branch = pair.branch {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(pair.worktree == nil ? .tertiary : .secondary)
                Text(branch)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(pair.worktree == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(branch)
                if !repo.branches.contains(branch) {
                    Tag("no commits", color: .secondary)
                }
                Spacer(minLength: 8)
                SyncStatus(repo: repo, branch: branch)
                // A row with a worktree has its delete button on the worktree side.
                DeleteSlot(item: pair.worktree == nil ? rowItem : nil, operation: .delete(branch: branch),
                           isVisible: isHovered)
            }
        }
        .cellFrame()
        .contextMenu { rowMenu }
    }

    // MARK: Worktree side

    private var worktreeCell: some View {
        HStack(spacing: 6) {
            if let worktree = pair.worktree {
                Text(worktree.name)
                    .font(.system(size: 12, weight: worktree.isMain ? .medium : .regular))
                    .foregroundStyle(worktree.isMissing ? .secondary : .primary)
                    .strikethrough(worktree.isMissing)
                    .lineLimit(1)
                if worktree.isMain {
                    Tag("main", color: .secondary)
                }
                if let detached = worktree.detachedAt {
                    Tag("detached \(detached)", color: .orange)
                }
                if worktree.isMissing {
                    Tag("missing", color: .red)
                }
                Text(displayPath(worktree))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                Spacer(minLength: 4)
                DeleteSlot(item: rowItem, operation: .removeWorktree(path: worktree.path), isVisible: isHovered)
            }
        }
        .help(pair.worktree?.path ?? "")
        .cellFrame()
        .contextMenu {
            if let worktree = pair.worktree {
                PathActions(path: worktree.path)
            }
            rowMenu
        }
    }

    private func displayPath(_ worktree: Worktree) -> String {
        if worktree.isMain { return "" }
        let base = repo.url.path + "/"
        if worktree.path.hasPrefix(base) { return String(worktree.path.dropFirst(base.count)) }
        return (worktree.path as NSString).abbreviatingWithTildeInPath
    }
}

/// Ahead/behind for one branch; each count is a button that pulls or pushes.
private struct SyncStatus: View {
    let repo: Repo
    let branch: String
    @Environment(ScanModel.self) private var model

    var body: some View {
        let status = model.statuses[repo.url]?[branch]
        let operation = model.running[repo.url]
        HStack(spacing: 4) {
            if operation == .pull(branch: branch) || operation == .push(branch: branch) {
                ProgressView().controlSize(.mini)
            } else if let status {
                if status.isGone {
                    localLabel.help("Local only: \(status.upstreamName) was deleted on the remote")
                } else if status.ahead == 0 && status.behind == 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .help("Up to date with \(status.upstreamName)")
                } else {
                    let diverged = status.isDiverged
                    if status.behind > 0 {
                        SyncPill(symbol: "arrow.down", count: status.behind, color: diverged ? .orange : .blue) {
                            model.pull(repo, branch: branch)
                        }
                        .disabled(diverged || operation != nil)
                        .help(diverged ? divergedHelp(status) : "Pull \(status.behind) from \(status.upstreamName) (fast-forward)")
                    }
                    if status.ahead > 0 {
                        let pushable = status.canPush(branch)
                        SyncPill(symbol: "arrow.up", count: status.ahead, color: diverged || !pushable ? .orange : .green) {
                            model.push(repo, branch: branch)
                        }
                        .disabled(diverged || !pushable || operation != nil)
                        .help(diverged ? divergedHelp(status)
                              : pushable ? "Push \(status.ahead) to \(status.upstreamName)"
                              : "Upstream \(status.upstreamName) has a different name; push from the terminal")
                    }
                }
            } else if model.statuses[repo.url] != nil {
                localLabel.help("Local only: no upstream branch")
            }
        }
        .fixedSize()
    }

    private var localLabel: some View {
        Text("local")
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
    }

    private func divergedHelp(_ status: BranchStatus) -> String {
        "Diverged from \(status.upstreamName): needs a merge or rebase"
    }
}

struct SyncCount: View {
    let symbol: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text("\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
    }
}

private struct SyncPill: View {
    let symbol: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) { SyncCount(symbol: symbol, count: count, color: color) }
            .buttonStyle(PillButtonStyle(color: color))
    }
}

/// Feedback lands on press, not release.
private struct PillButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(
                color.opacity(configuration.isPressed ? 0.3 : isHovered && isEnabled ? 0.2 : 0.1),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.6)
            .onHover { isHovered = $0 }
    }
}

private extension View {
    /// The padding and height every cell shares.
    func cellFrame() -> some View {
        padding(.horizontal, 4).frame(height: 20)
    }
}

/// Fixed-width trash slot so neighbouring columns stay aligned whether or not the button shows.
private struct DeleteSlot: View {
    let item: Selectable?
    let operation: RepoOperation
    let isVisible: Bool
    @Environment(ScanModel.self) private var model

    var body: some View {
        ZStack {
            if let item {
                if model.running[item.repo] == operation {
                    ProgressView().controlSize(.mini)
                } else if isVisible {
                    Button { model.requestDeletion([item]) } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(model.running[item.repo] != nil)
                    .help(model.deleteTitle(for: [item]))
                }
            }
        }
        .frame(width: 16)
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .fixedSize()
    }
}

struct PathActions: View {
    let path: String

    var body: some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}
