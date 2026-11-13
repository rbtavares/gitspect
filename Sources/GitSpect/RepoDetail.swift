import AppKit
import SwiftUI

/// The selected repo: branches (left) and worktrees (right), paired row by row.
struct RepoDetail: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Share of the width below the header taken by the graph pane; starts as an even split.
    @AppStorage("graphFraction") private var graphFraction = 0.5

    static let columnGap: CGFloat = 24
    /// Space either side of the rows; their highlights reach to it.
    static let inset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            errorBanner
            // The graph pane opens beside the list.
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    pairList
                        .frame(maxWidth: .infinity)
                    if let target = model.graphTarget, target.repo == repo.url {
                        GraphPane(target: target, fraction: $graphFraction, totalWidth: proxy.size.width)
                            // Slides in as the list shrinks to make room, so the headers stay joined.
                            .transition(.move(edge: .trailing))
                            .zIndex(1)
                    }
                }
                .clipped()
                .animation(reduceMotion ? nil : .snappy(duration: GraphPane.slideDuration), value: model.graphTarget == nil)
            }
        }
    }

    private var pairList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(repo.pairs) { pair in
                        PairRow(pair: pair, repo: repo)
                            .padding(.horizontal, Self.inset)
                    }
                } header: {
                    columnTitles
                        .padding(.bottom, 4)
                }
            }
            // Room for the floating selection bar.
            .padding(.bottom, 72)
        }
    }

    /// Errors from the last git command on this repo. The name, path and remote live in the top bar.
    @ViewBuilder private var errorBanner: some View {
        if let error = model.errors[repo.url] {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(error)
                    .font(.dsMonoSmall)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .foregroundStyle(Palette.danger)
            .help(error)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.danger.opacity(0.1))
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private var columnTitles: some View {
        HStack(spacing: 0) {
            ColumnTitle("Branches", count: repo.branches.count)
            Color.clear.frame(width: Self.columnGap)
            ColumnTitle("Worktrees", count: repo.worktrees.count)
        }
        .padding(.horizontal, Self.inset + PairRow.padding)
        // Matches the graph pane's header, so the two read as one bar when it's open.
        .frame(height: Metric.paneHeader)
        .background(Palette.canvas)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The selected repo's name, path and remote. Shown in the top bar.
struct RepoTitle: View {
    let repo: Repo

    var body: some View {
        // Name, then where it lives and where it's published, all on the bar's one line.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // The name and path take no clicks, so dragging them moves the window like the rest
            // of the bar. The sidebar row has the path's menu.
            Text(repo.name)
                .font(.dsTitle)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .layoutPriority(1)
                .allowsHitTesting(false)
            Text((repo.url.path as NSString).abbreviatingWithTildeInPath)
                .font(.dsMonoSmall)
                .foregroundStyle(Palette.textFaint)
                .lineLimit(1)
                .truncationMode(.head)
                .allowsHitTesting(false)
            remoteBadge
        }
    }

    /// Where the repo is published: a link to the remote's page, or a "local only" tag.
    @ViewBuilder private var remoteBadge: some View {
        if let remote = repo.remotes.first {
            let others = repo.remotes.dropFirst().map(\.name)
            let help = "\(remote.name): \(remote.url)" + (others.isEmpty ? "" : "\nAlso: " + others.joined(separator: ", "))
            let label = Text(remote.displayName)
                .font(.dsMonoSmall)
                .lineLimit(1)
                .truncationMode(.middle)
            if let web = remote.webURL {
                Button { NSWorkspace.shared.open(web) } label: { label }
                    .buttonStyle(LinkButtonStyle())
                    .help(help + "\nOpen in browser")
            } else {
                label
                    .foregroundStyle(Palette.textFaint)
                    .help(help)
            }
        } else {
            Tag("local only")
                .help("This repository has no remote, so it exists only on this Mac.")
        }
    }
}

/// Text that opens something: accent-coloured, underlined while pointed at.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? Palette.accent : Palette.textFaint)
                .underline(isHovered && isEnabled)
                .opacity(configuration.isPressed ? 0.7 : 1)
                // Taller than the text, so it's an easier target.
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

/// Fetches the selected repo; sits at the trailing end of the top bar.
struct RepoFetchButton: View {
    let repo: Repo
    @Environment(ScanModel.self) private var model

    var body: some View {
        let isFetching = model.running[repo.url] == .fetch
        Button {
            Task { await model.fetch(repo) }
        } label: {
            HStack(spacing: 6) {
                if isFetching {
                    Spinner(size: 10)
                } else {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                }
                Text(isFetching ? "Fetching" : "Fetch")
            }
        }
        .buttonStyle(.ds(.secondary))
        // Never squeezed: the path and remote beside it give way instead.
        .fixedSize()
        .disabled(model.running[repo.url] != nil || repo.isLocalOnly)
        .help(repo.isLocalOnly ? "No remote to fetch from" : "git fetch --all --prune")
    }
}

/// Styled like the other pane headers (Output, graph, commit): the name, then its count, quieter.
private struct ColumnTitle: View {
    let text: String
    let count: Int
    init(_ text: String, count: Int) { self.text = text; self.count = count }

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.dsLabel)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
            Text("\(count)")
                .font(.dsMonoSmall)
                .foregroundStyle(Palette.textFaint)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PairRow: View {
    let pair: CheckoutPair
    let repo: Repo
    @State private var isHovered = false
    @Environment(ScanModel.self) private var model

    static let padding: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            branchCell.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: RepoDetail.columnGap)
            worktreeCell.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Self.padding)
        .padding(.trailing, 2)
        .frame(height: Metric.row)
        .background {
            // A branch and its worktree are one line, selected as one.
            RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
                .fill(isSelected ? Palette.accent.opacity(isHovered ? Palette.tintHover : Palette.tint)
                      : isHovered ? Palette.hover : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { click() }
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var row: RowID { RowID(repo: repo.url, pair: pair.id) }

    /// What this row can delete; nil for the main checkout.
    private var rowItem: Selectable? { repo.rowItem(pair) }

    private var isSelected: Bool { model.selection.contains(row) }

    /// Faint text is only legible on the bare canvas; on a lit row it steps up to muted.
    private var quiet: Color { isSelected || isHovered ? Palette.textMuted : Palette.textFaint }

    /// A click selects the row and shows its graph; ⌘ adds or removes it, ⇧ extends a range.
    private func click() {
        let flags = NSEvent.modifierFlags
        model.select(row, mode: flags.contains(.shift) ? .extend : flags.contains(.command) ? .toggle : .only)
    }

    @ViewBuilder private var rowMenu: some View {
        if !isSelected {
            Button("Show Graph") { model.select(row, mode: .only) }
        }
        // Like Finder: a right-click on one of several selected rows acts on all of them; on a
        // row outside the selection, on that row alone.
        let selected = isSelected ? model.deletionItems(model.selection) : []
        if selected.count > 1 {
            Divider()
            Button("Delete \(selected.count) Selected…", role: .destructive) { model.requestDeletion(selected) }
        } else if let rowItem {
            Divider()
            // The dialog offers what applies: the branch, the worktree, or both.
            Button("Delete…", role: .destructive) { model.requestDeletion([rowItem]) }
        }
    }

    // MARK: Branch side

    // Containers stay unconditional so empty cells still hold their half of the row.
    private var branchCell: some View {
        HStack(spacing: 6) {
            if let branch = pair.branch {
                Text(branch)
                    .font(.dsMono)
                    // Branches checked out in a worktree stand out from the ones that aren't.
                    .foregroundStyle(pair.worktree == nil ? Palette.textMuted : Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(branch)
                if !repo.branches.contains(branch) {
                    Tag("no commits")
                }
                Spacer(minLength: 8)
                SyncStatus(repo: repo, branch: branch, quiet: quiet)
                // A row with a worktree has its delete button on the worktree side.
                DeleteSlot(item: pair.worktree == nil ? rowItem : nil, operation: .delete(branch: branch),
                           isVisible: isHovered)
            }
        }
        .frame(height: Metric.row)
        .contextMenu { rowMenu }
    }

    // MARK: Worktree side

    private var worktreeCell: some View {
        HStack(spacing: 6) {
            if let worktree = pair.worktree {
                Text(worktree.name)
                    .font(worktree.isMain ? .dsBodyMedium : .dsBody)
                    .foregroundStyle(worktree.isMissing ? Palette.textMuted : Palette.text)
                    .strikethrough(worktree.isMissing)
                    .lineLimit(1)
                    // The name keeps its room; the path gives way first.
                    .layoutPriority(1)
                if worktree.isMain {
                    Tag("main")
                }
                if let detached = worktree.detachedAt {
                    // The commit is in the tooltip: the tag stays short so the name keeps its room.
                    Tag("detached", color: Palette.caution)
                        .help("Detached at \(detached)")
                }
                if worktree.isMissing {
                    Tag("missing", color: Palette.danger)
                }
                Text(displayPath(worktree))
                    .font(.dsMonoSmall)
                    .foregroundStyle(quiet)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                Spacer(minLength: 4)
                DeleteSlot(item: rowItem, operation: .removeWorktree(path: worktree.path), isVisible: isHovered)
            }
        }
        .help(pair.worktree?.path ?? "")
        .frame(height: Metric.row)
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
    /// The colour for marks that aren't actions, from the row.
    let quiet: Color
    @Environment(ScanModel.self) private var model

    var body: some View {
        let status = model.statuses[repo.url]?[branch]
        let operation = model.running[repo.url]
        HStack(spacing: 4) {
            if operation == .pull(branch: branch) || operation == .push(branch: branch) {
                Spinner(size: 10)
            } else if let status {
                if status.isGone {
                    localLabel.help("Local only: \(status.upstreamName) was deleted on the remote")
                } else if status.ahead == 0 && status.behind == 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(quiet)
                        .help("Up to date with \(status.upstreamName)")
                        .accessibilityLabel("Up to date")
                } else {
                    let diverged = status.isDiverged
                    if status.behind > 0 {
                        SyncPill(symbol: "arrow.down", count: status.behind, color: diverged ? Palette.caution : Palette.accent) {
                            model.pull(repo, branch: branch)
                        }
                        .disabled(diverged || operation != nil)
                        .help(diverged ? divergedHelp(status) : "Pull \(status.behind) from \(status.upstreamName) (fast-forward)")
                    }
                    if status.ahead > 0 {
                        let pushable = status.canPush(branch)
                        SyncPill(symbol: "arrow.up", count: status.ahead, color: diverged || !pushable ? Palette.caution : Palette.positive) {
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
            .font(.dsCaption)
            .foregroundStyle(quiet)
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
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text("\(count)").font(.dsMonoSmallMedium)
        }
        .foregroundStyle(color)
    }
}

struct SyncPill: View {
    let symbol: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) { SyncCount(symbol: symbol, count: count, color: color) }
            .buttonStyle(PillButtonStyle(color: color))
            .accessibilityLabel("\(symbol == "arrow.down" ? "Pull" : "Push") \(count)")
    }
}

/// Feedback lands on press, not release.
struct PillButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, color: color)
    }

    private struct Face: View {
        let configuration: Configuration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    color.opacity(configuration.isPressed ? 0.26 : isHovered && isEnabled ? Palette.tintHover : Palette.tint),
                    in: RoundedRectangle(cornerRadius: Metric.radiusSmall, style: .continuous)
                )
                // The pill is 18pt tall; its target is the row's 24pt.
                .frame(height: Metric.controlSmall)
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .opacity(isEnabled ? 1 : 0.6)
                .onHover { isHovered = $0 }
        }
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
                    Spinner(size: 10)
                } else if isVisible {
                    IconButton(symbol: "trash", help: "Delete…", size: 11) { model.requestDeletion([item]) }
                        .disabled(model.running[item.repo] != nil)
                }
            }
        }
        .frame(width: Metric.controlSmall, height: Metric.controlSmall)
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
