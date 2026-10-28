import AppKit
import SwiftUI

/// The selected repo: branches (left) and worktrees (right), paired row by row.
struct RepoDetail: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model

    static let columnGap: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    Section {
                        ForEach(repo.pairs) { PairRow(pair: $0, repo: repo) }
                    } header: {
                        columnTitles
                    }
                }
                .padding(.trailing, 12)
                // Room for the floating selection bar.
                .padding(.bottom, 64)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(repo.name)
                    .font(.system(size: 15, weight: .semibold))
                Text((repo.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                remoteBadge
                Spacer()
                fetchButton
            }
            if let error = model.errors[repo.url] {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .help(error)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contextMenu { PathActions(path: repo.url.path) }
    }

    /// Where the repo is published: a link to the remote's page, or a "Local only" tag.
    @ViewBuilder private var remoteBadge: some View {
        if let remote = repo.remotes.first {
            let label = Label(remote.displayName, systemImage: "network")
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
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

    @ViewBuilder private var fetchButton: some View {
        Button {
            Task { await model.fetch(repo) }
        } label: {
            if model.running[repo.url] == .fetch {
                ProgressView().controlSize(.mini)
            } else {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
        }
        .controlSize(.small)
        .disabled(model.running[repo.url] != nil || repo.isLocalOnly)
        .help(repo.isLocalOnly ? "No remote to fetch from" : "git fetch --all --prune")
    }

    private var columnTitles: some View {
        HStack(spacing: 0) {
            ColumnTitle("Branches \(repo.branches.count)")
            Color.clear.frame(width: Self.columnGap)
            ColumnTitle("Worktrees \(repo.worktrees.count)")
        }
        .padding(.leading, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.background)
    }
}

private struct ColumnTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.tertiary)
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
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.08) : .clear)
                .padding(.leading, 12)
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering } }
    }

    // MARK: Branch side

    /// Branches checked out in a worktree can't be deleted.
    private var branchItem: Selectable? {
        guard let branch = pair.branch, pair.worktree == nil, repo.branches.contains(branch) else { return nil }
        return .branch(repo: repo.url, name: branch)
    }

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
                DeleteSlot(item: branchItem, operation: .delete(branch: branch), isVisible: isHovered,
                           help: "Delete local branch \(branch)")
            }
        }
        .selectable(branchItem, isHovered: isHovered)
        .contextMenu {
            if let item = branchItem {
                Button("Delete Branch…", role: .destructive) { model.requestDeletion([item]) }
            }
        }
    }

    // MARK: Worktree side

    private var worktreeItem: Selectable? {
        guard let worktree = pair.worktree, !worktree.isMain else { return nil }
        return .worktree(repo: repo.url, path: worktree.path)
    }

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
                DeleteSlot(item: worktreeItem, operation: .removeWorktree(path: worktree.path), isVisible: isHovered,
                           help: "Remove worktree \(worktree.name)")
            }
        }
        .help(pair.worktree?.path ?? "")
        .selectable(worktreeItem, isHovered: isHovered)
        .contextMenu {
            if let worktree = pair.worktree {
                PathActions(path: worktree.path)
                if let item = worktreeItem {
                    Divider()
                    Button("Remove Worktree…", role: .destructive) { model.requestDeletion([item]) }
                }
            }
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

/// Click to select (⌘ toggles, ⇧ extends); selected cells get an accent fill.
private struct SelectableCell: ViewModifier {
    let item: Selectable?
    let isHovered: Bool
    @Environment(ScanModel.self) private var model

    func body(content: Content) -> some View {
        let isSelected = item.map(model.selection.contains) ?? false
        content
            .padding(.horizontal, 4)
            .frame(height: 20)
            .background(
                Color.accentColor.opacity(isSelected ? (isHovered ? 0.28 : 0.2) : 0),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard let item else { return }
                let flags = NSEvent.modifierFlags
                model.select(item, mode: flags.contains(.shift) ? .extend : flags.contains(.command) ? .toggle : .only)
            }
    }
}

private extension View {
    func selectable(_ item: Selectable?, isHovered: Bool) -> some View {
        modifier(SelectableCell(item: item, isHovered: isHovered))
    }
}

/// Fixed-width trash slot so neighbouring columns stay aligned whether or not the button shows.
private struct DeleteSlot: View {
    let item: Selectable?
    let operation: RepoOperation
    let isVisible: Bool
    let help: String
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
                    .help(help)
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
