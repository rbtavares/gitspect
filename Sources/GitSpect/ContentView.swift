import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var query = ""
    @State private var collapsed: Set<String> = []
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
                NavigationSplitView {
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
            Button(request.force ? "Force Delete" : model.deleteTitle(for: items), role: .destructive) {
                runDeletion(items, force: request.force)
            }
        } message: { request in
            Text(dialogMessage(request))
        }
        .toolbarRepoTitle(selectedRepo?.name ?? "GitSpect")
        .onChange(of: selectedPath) {
            model.clearSelection()
            model.closeGraph()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let repo = selectedRepo { RepoTitle(repo: repo) }
            }
            // Flexible space: the app-wide actions sit at the far right, apart from the repo.
            ToolbarItem { Spacer() }
            ToolbarItemGroup {
                Button(action: model.fetchAll) {
                    if let progress = model.fetchAllProgress {
                        Label("Fetching \(progress.done)/\(progress.total)", systemImage: "arrow.down.circle")
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label("Fetch All", systemImage: "arrow.down.circle")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .disabled(model.repos.isEmpty || model.fetchAllProgress != nil || model.pullAllProgress != nil)
                .help("git fetch --all --prune in every repo")
                pullAllButton
            }
        }
    }

    private var pullAllButton: some View {
        let pullable = model.pullableBranches
        let branches = pullable.reduce(0) { $0 + $1.branches.count }
        return Button(action: model.pullAll) {
            if let progress = model.pullAllProgress {
                Label("Pulling \(progress.done)/\(progress.total)", systemImage: "arrow.down.to.line.circle")
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Pull All", systemImage: "arrow.down.to.line.circle")
                    .labelStyle(.titleAndIcon)
            }
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
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarBar }
        .toolbar {
            // In the sidebar's part of the toolbar, beside the window buttons.
            ToolbarItem {
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
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Filter repos, branches, worktrees")
    }

    @ViewBuilder private var detail: some View {
        if let repo = model.repos.first(where: { $0.url.path == selectedPath }) {
            RepoDetail(repo: repo)
                .overlay(alignment: .bottom) {
                    if !model.selection.isEmpty {
                        SelectionBar(summary: countPhrase(Array(model.selection)) + " selected",
                                     isBusy: !model.running.isEmpty) {
                            model.requestDeletion(Array(model.selection))
                        } clear: {
                            model.clearSelection()
                        }
                        .padding(.bottom, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: model.selection.isEmpty)
        } else {
            ContentUnavailableView("Select a Repository", systemImage: "sidebar.left",
                                   description: Text("Choose a repo in the sidebar to see its branches and worktrees."))
        }
    }

    // MARK: - Deletion dialog

    private func runDeletion(_ items: [Selectable], force: Bool) {
        Task { await model.delete(items, force: force) }
    }

    private func dialogTitle(_ request: DeletionRequest) -> String {
        if request.force { return "\(request.items.count) item\(request.items.count == 1 ? " needs" : "s need") force" }
        return "Delete " + countPhrase(request.items) + "?"
    }

    /// "2 branches and 1 worktree".
    private func countPhrase(_ items: [Selectable]) -> String {
        let (branches, worktrees) = model.deletionCounts(items)
        return [
            branches > 0 ? "\(branches) branch\(branches == 1 ? "" : "es")" : nil,
            worktrees > 0 ? "\(worktrees) worktree\(worktrees == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }.joined(separator: " and ")
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

private extension View {
    /// The toolbar shows the selected repo (`RepoTitle`) in place of a title. On macOS 15+ the window
    /// keeps its title for the Window menu; macOS 14 can't hide it from the toolbar, so it's left empty.
    @ViewBuilder func toolbarRepoTitle(_ title: String) -> some View {
        if #available(macOS 15, *) {
            navigationTitle(title).toolbar(removing: .title)
        } else {
            navigationTitle("")
        }
    }
}
