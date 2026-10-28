import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @AppStorage("selectedRepoPath") private var selectedPath = ""
    @AppStorage("showsOutput") private var showsOutput = false
    @AppStorage("outputHeight") private var outputHeight = 200.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.roots.isEmpty {
                ContentUnavailableView {
                    Label("No Folders Added", systemImage: "folder")
                } description: {
                    Text("Add one or more folders that contain your git repositories.")
                } actions: {
                    Button("Add Folders…", action: addFolders)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
                } detail: {
                    // A plain stack rather than VSplitView: VSplitView ignores the toolbar's
                    // safe area (hiding the repo header) and the drawer's ideal height.
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            detail
                                .frame(maxHeight: .infinity)
                            if showsOutput {
                                OutputPanel(height: $outputHeight, maxHeight: proxy.size.height - 200) {
                                    showsOutput = false
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            model.deletionRequest.map(dialogTitle) ?? "",
            isPresented: Binding(get: { model.deletionRequest != nil }, set: { if !$0 { model.deletionRequest = nil } }),
            presenting: model.deletionRequest
        ) { request in
            let items = sorted(request.items)
            if request.force {
                Button("Force Delete", role: .destructive) {
                    runDeletion(items, force: true, alsoBranches: request.alsoBranches)
                }
            } else {
                // Only the choices that apply to what's selected.
                let branchRows = items.filter { !$0.isWorktree }
                let worktreeRows = items.filter(\.isWorktree)
                if !branchRows.isEmpty {
                    Button("Delete \(count(branchRows.count, "Branch", "Branches"))", role: .destructive) {
                        runDeletion(branchRows, force: false, alsoBranches: false)
                    }
                }
                if !worktreeRows.isEmpty {
                    Button("Delete \(count(worktreeRows.count, "Worktree", "Worktrees"))", role: .destructive) {
                        runDeletion(worktreeRows, force: false, alsoBranches: false)
                    }
                    let branches = branchRows.count + worktreeRows.filter(model.hasBranch).count
                    if branches > 0 {
                        Button("Delete \(count(branches, "Branch", "Branches")) and \(count(worktreeRows.count, "Worktree", "Worktrees"))",
                               role: .destructive) {
                            runDeletion(items, force: false, alsoBranches: true)
                        }
                    }
                }
            }
        } message: { request in
            Text(dialogMessage(request))
        }
        // Hidden from the toolbar by the window's style (RepoTitle shows instead); still used by the Window menu.
        .navigationTitle(selectedRepo?.name ?? "GitSpect")
        .onChange(of: selectedPath) {
            model.clearSelection()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let repo = selectedRepo { RepoTitle(repo: repo) }
            }
            // Flexible space: the app-wide actions sit at the far right, apart from the repo.
            // Flexible space: the repo's own Fetch sits at the far right.
            ToolbarItem { Spacer() }
            ToolbarItem {
                if let repo = selectedRepo { RepoFetchButton(repo: repo) }
            }
        }
    }

    /// Actions on every repo, under the sidebar's search field.
    private var bulkActions: some View {
        HStack(spacing: 6) {
            Button(action: model.fetchAll) {
                Label(model.fetchAllProgress.map { "Fetching \($0.done)/\($0.total)" } ?? "Fetch All",
                      systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.repos.isEmpty || model.fetchAllProgress != nil || model.pullAllProgress != nil)
            .help("git fetch --all --prune in every repo")
            pullAllButton
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var pullAllButton: some View {
        let pullable = model.pullableBranches
        let branches = pullable.reduce(0) { $0 + $1.branches.count }
        return Button(action: model.pullAll) {
            Label(model.pullAllProgress.map { "Pulling \($0.done)/\($0.total)" } ?? "Pull All",
                  systemImage: "arrow.down.to.line.circle")
                .frame(maxWidth: .infinity)
        }
        .disabled(branches == 0 || model.pullAllProgress != nil || model.fetchAllProgress != nil)
        .help(branches == 0
              ? "Nothing to pull. Fetch All first to check for new commits."
              : "Fast-forward \(branches) branch\(branches == 1 ? "" : "es") in \(pullable.count) repo\(pullable.count == 1 ? "" : "s") that \(branches == 1 ? "is" : "are") behind. Never merges or rebases.")
    }

    /// Folder controls live with the folder tree, Finder/Xcode style.
    private var sidebarBar: some View {
        HStack(spacing: 4) {
            Button(action: addFolders) { Image(systemName: "plus") }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Add folders to scan for repositories (⇧⌘O)")
            Spacer()
            if model.isScanning { ProgressView().controlSize(.mini) }
            Button(action: model.rescan) { Image(systemName: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.roots.isEmpty || model.isScanning)
                .help("Rescan folders (⌘R)")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var sidebar: some View {
        Group {
            // Folders without repos still show, so they can be removed from the tree.
            if tree.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Sidebar(
                    roots: tree,
                    selection: Binding(
                        get: { selectedPath.isEmpty ? nil : URL(fileURLWithPath: selectedPath) },
                        set: { selectedPath = $0?.path ?? "" }
                    ),
                    collapsed: $collapsed
                )
            }
        }
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { bulkActions }
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarBar }
        .toolbar {
            // In the sidebar's part of the toolbar, beside the window buttons. With the sidebar
            // collapsed it would sit next to the repo title, so it's left out then. macOS moves
            // toolbar items between the sidebar and main toolbar as the sidebar slides, and
            // animating them during that move flashes, so it only fades in once the sidebar is open.
            ToolbarItem {
                if columnVisibility != .detailOnly {
                    sidebarTitle.modifier(FadeInOnAppear(delay: 0.15, animated: !reduceMotion))
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Filter repos, branches, worktrees")
    }

    private var sidebarTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("GitSpect")
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .help(model.roots.map(\.path).joined(separator: "\n"))
    }

    @ViewBuilder private var detail: some View {
        if let repo = model.repos.first(where: { $0.url.path == selectedPath }) {
            RepoDetail(repo: repo)
                .overlay(alignment: .bottom) {
                    // Only once something deletable is selected (the main checkout isn't).
                    let deletable = model.deletionItems(model.selection)
                    if !deletable.isEmpty {
                        SelectionBar(summary: countPhrase(deletable).lowercased() + " selected",
                                     isBusy: !model.running.isEmpty) {
                            model.requestDeletion(deletable)
                        } clear: {
                            model.clearSelection()
                        }
                        .padding(.bottom, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0),
                           value: model.deletionItems(model.selection).isEmpty)
        } else {
            ContentUnavailableView("Select a Repository", systemImage: "sidebar.left",
                                   description: Text("Choose a repo in the sidebar to see its branches and worktrees."))
        }
    }

    // MARK: - Deletion dialog

    private func runDeletion(_ items: [Selectable], force: Bool, alsoBranches: Bool) {
        Task { await model.delete(items, force: force, alsoBranches: alsoBranches) }
    }

    private func dialogTitle(_ request: DeletionRequest) -> String {
        if request.force { return "\(request.items.count) item\(request.items.count == 1 ? " needs" : "s need") force" }
        return "Delete " + countPhrase(request.items).lowercased() + "?"
    }

    /// "2 Branches and 1 Worktree": rows that are just a branch, and worktree rows.
    private func countPhrase(_ items: [Selectable]) -> String {
        let worktrees = items.filter(\.isWorktree).count
        let branches = items.count - worktrees
        return [
            branches > 0 ? count(branches, "Branch", "Branches") : nil,
            worktrees > 0 ? count(worktrees, "Worktree", "Worktrees") : nil,
        ].compactMap { $0 }.joined(separator: " and ")
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    private func dialogMessage(_ request: DeletionRequest) -> String {
        var lines = sorted(request.items).map(describe)
        if lines.count > 10 { lines = Array(lines.prefix(10)) + ["…and \(request.items.count - 10) more"] }
        var notes: [String] = []
        if request.force {
            if request.items.contains(where: \.isWorktree) {
                notes.append("Worktrees with modified or untracked files: those changes will be lost.")
            }
            if request.items.contains(where: { !$0.isWorktree }) {
                notes.append("Branches with commits git can't find upstream or in the current branch. Squash-merged branches look like this; otherwise the commits will be lost.")
            }
        } else {
            notes.append("Local only: remotes are not touched.")
        }
        return (lines + [""] + notes).joined(separator: "\n")
    }

    private func describe(_ item: Selectable) -> String {
        switch item {
        case .branch(let repo, let name):
            return "\(repo.lastPathComponent): \(name)"
        case .worktree(let repo, let path):
            let name = URL(fileURLWithPath: path).lastPathComponent
            let branch = model.repos.first { $0.url == repo }?.worktrees.first { $0.path == path }?.branch
            return "\(repo.lastPathComponent): \(branch.map { "\($0) + " } ?? "")worktree \(name)"
        }
    }

    private func sorted(_ items: [Selectable]) -> [Selectable] {
        items.sorted { describe($0).localizedStandardCompare(describe($1)) == .orderedAscending }
    }

    private var tree: [RootNode] {
        guard !query.isEmpty else { return RootNode.tree(roots: model.roots, repos: model.repos) }
        // While filtering, folders with no matches are hidden.
        return RootNode.tree(roots: model.roots, repos: model.repos.filter { $0.matches(query) })
            .filter { !$0.groups.isEmpty }
    }

    /// "2 folders · 27 repos".
    private var subtitle: String {
        let folders = "\(model.roots.count) folder\(model.roots.count == 1 ? "" : "s")"
        return model.isScanning ? "\(folders) · scanning…" : "\(folders) · \(model.repos.count) repos"
    }

    private var selectedRepo: Repo? { model.repos.first { $0.url.path == selectedPath } }

    private func addFolders() { model.chooseFoldersToAdd() }
}

extension ScanModel {
    /// Asks for folders to scan, starting next to the last one added.
    func chooseFoldersToAdd() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if let last = roots.last { panel.directoryURL = last.deletingLastPathComponent() }
        if panel.runModal() == .OK {
            add(roots: panel.urls)
        }
    }
}

/// Floating action bar for the current selection.
private struct SelectionBar: View {
    let summary: String
    let isBusy: Bool
    let delete: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
            if isBusy { ProgressView().controlSize(.small) }
            Button("Clear", action: clear)
                .keyboardShortcut(.cancelAction)
            Button("Delete…", role: .destructive, action: delete)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(isBusy)
        }
        .controlSize(.small)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// Fades a view in when it appears, after `delay`.
private struct FadeInOnAppear: ViewModifier {
    let delay: Double
    let animated: Bool
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || !animated ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2).delay(delay)) { isVisible = true }
            }
    }
}
