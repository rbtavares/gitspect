import AppKit
import SwiftUI

/// The whole window: sidebar, top bar, the selected repo and the output drawer, all GitSpect's own.
struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var isFullScreen = false
    /// A question from the sidebar (moving a folder to the Trash).
    @State private var confirmRequest: ConfirmRequest?
    @State private var sidebarDragStart: Double?
    /// Counts ⌘F presses; the filter field takes the cursor each time it changes.
    @State private var filterFocusRequests = 0
    @AppStorage("selectedRepoPath") private var selectedPath = ""
    @AppStorage("outputHeight") private var outputHeight = 200.0
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 280.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sidebarWidths: ClosedRange<Double> = 220...440
    /// Room the sidebar always leaves for the repo, however wide it was dragged.
    private static let minMainWidth: Double = 400

    /// The width the sidebar was dragged to, less whatever a narrow window can't spare.
    private func sidebarWidth(in windowWidth: CGFloat) -> CGFloat {
        let fits = max(Self.sidebarWidths.lowerBound, Double(windowWidth) - Self.minMainWidth)
        return min(sidebarWidth.clamped(to: Self.sidebarWidths), fits)
    }

    var body: some View {
        ZStack {
            Palette.canvas
            if model.roots.isEmpty {
                welcome
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        if sidebarVisible {
                            sidebar
                                .frame(width: sidebarWidth(in: proxy.size.width))
                                .transition(.move(edge: .leading))
                        }
                        main
                    }
                    .animation(reduceMotion ? nil : .snappy(duration: Metric.slide), value: sidebarVisible)
                }
            }
            if let request = activeConfirm {
                ConfirmDialog(request: request) {
                    confirmRequest = nil
                    model.deletionRequest = nil
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: activeConfirm == nil)
        .ignoresSafeArea()
        .background(WindowChrome(isFullScreen: $isFullScreen))
        .foregroundStyle(Palette.text)
        .font(.dsBody)
        // The caret and text selection.
        .tint(Palette.accent)
        .onReceive(NotificationCenter.default.publisher(for: .focusFilter)) { _ in
            sidebarVisible = true
            // After the sidebar is back, if it was hidden.
            DispatchQueue.main.async { filterFocusRequests += 1 }
        }
        // Not drawn (the top bar shows the repo instead); still names the window in the Window menu.
        .navigationTitle(selectedRepo?.name ?? "GitSpect")
        .onChange(of: selectedPath) {
            model.clearSelection()
        }
        #if DEBUG
        .task { await stageForSnapshot() }
        #endif
    }

    #if DEBUG
    @Environment(\.openSettings) private var openSettings

    /// Development aid for Snapshot: puts the window in a state a click would, so it can be pictured.
    private func stageForSnapshot() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITSPECT_SNAPSHOT"] != nil else { return }
        try? await Task.sleep(for: .seconds(2))
        if environment["GITSPECT_SNAPSHOT_WINDOW"] == "settings" { openSettings() }
        if environment["GITSPECT_STAGE_OUTPUT"] != nil { model.setOutputVisible(true) }
        if environment["GITSPECT_STAGE_FETCH_ALL"] != nil { model.fetchAll() }
        guard let repo = selectedRepo else { return }
        if let branch = environment["GITSPECT_STAGE_BRANCH"], let pair = repo.pairs.first(where: { $0.branch == branch }) {
            model.select(RowID(repo: repo.url, pair: pair.id), mode: .only)
        }
        if environment["GITSPECT_STAGE_DELETE"] != nil {
            model.requestDeletion(repo.pairs.compactMap(repo.rowItem))
        }
        if environment["GITSPECT_STAGE_SELECT_ALL"] != nil {
            for pair in repo.pairs { model.select(RowID(repo: repo.url, pair: pair.id), mode: .toggle) }
        }
    }
    #endif

    // MARK: - Layout

    private var welcome: some View {
        EmptyState(symbol: "folder.badge.plus", title: "Add your code folders",
                   message: "GitSpect finds the git repositories inside them and keeps their branches and worktrees in view.") {
            Button("Add Folders…", action: addFolders)
                .buttonStyle(.ds(.primary))
        }
        .background(alignment: .top) { WindowDragArea().frame(height: Metric.topBar) }
    }

    private var main: some View {
        VStack(spacing: 0) {
            topBar
            // A plain stack rather than a split view, so the drawer keeps the height it's given.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.showsOutput {
                        OutputPanel(height: $outputHeight, maxHeight: proxy.size.height - 200) {
                            model.setOutputVisible(false)
                        }
                    }
                }
            }
        }
        .background(Palette.canvas)
    }

    /// Level with the window buttons: what's selected on the left, what you can do to it on the right.
    private var topBar: some View {
        HStack(spacing: 8) {
            if !sidebarVisible {
                // The window buttons sit here once the sidebar is gone (not in full screen).
                if !isFullScreen { Color.clear.frame(width: WindowButtons.width - 16) }
                sidebarToggle
            }
            if let repo = selectedRepo {
                RepoTitle(repo: repo)
            } else {
                Text(selectedFolder?.url.lastPathComponent ?? "Overview")
                    .font(.dsTitle)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            IconButton(symbol: "terminal", help: model.showsOutput ? "Hide output (⇧⌘Y)" : "Show output (⇧⌘Y)") {
                model.setOutputVisible(!model.showsOutput)
            }
            if let repo = selectedRepo { RepoFetchButton(repo: repo) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: Metric.topBar)
        .background { WindowDragArea() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var sidebarToggle: some View {
        IconButton(symbol: "sidebar.leading", help: sidebarVisible ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)", size: 13) {
            sidebarVisible.toggle()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Beside the window buttons.
            HStack {
                Spacer()
                sidebarToggle
            }
            .padding(.trailing, 10)
            .frame(height: Metric.topBar)
            .background { WindowDragArea() }

            VStack(spacing: 8) {
                SearchField(text: $query, prompt: "Filter repos, branches, worktrees", focusRequests: filterFocusRequests)
                bulkActions
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // Folders without repos still show, so they can be removed from the tree.
            if tree.isEmpty && !query.isEmpty {
                VStack(spacing: 4) {
                    Text("No matches")
                        .font(.dsBodyMedium)
                    Text("Nothing is named “\(query)”.")
                        .font(.dsSmall)
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Sidebar(
                    roots: tree,
                    selection: Binding(
                        get: { selectedPath.isEmpty ? nil : URL(fileURLWithPath: selectedPath) },
                        set: { selectedPath = $0?.path ?? "" }
                    ),
                    collapsed: $collapsed,
                    confirm: { confirmRequest = $0 }
                )
            }
            sidebarFooter
        }
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) { sidebarEdge }
    }

    /// The sidebar's right edge: a hairline with a wider strip around it to drag.
    private var sidebarEdge: some View {
        Hairline(vertical: true)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let start = sidebarDragStart ?? sidebarWidth.clamped(to: Self.sidebarWidths)
                                sidebarDragStart = start
                                sidebarWidth = (start + value.translation.width).clamped(to: Self.sidebarWidths)
                            }
                            .onEnded { _ in sidebarDragStart = nil }
                    )
            }
    }

    /// Actions on every repo, under the search field.
    private var bulkActions: some View {
        HStack(spacing: 8) {
            Button(action: model.fetchAll) {
                Text(model.fetchAllProgress.map { "Fetching \($0.done)/\($0.total)" } ?? "Fetch All")
                    .monospacedDigit()
            }
            .disabled(model.repos.isEmpty || model.fetchAllProgress != nil || model.pullAllProgress != nil)
            .help("git fetch --all --prune in every repo")
            pullAllButton
        }
        .buttonStyle(.ds(.secondary, small: true, fills: true))
    }

    private var pullAllButton: some View {
        let pullable = model.pullableBranches
        let branches = pullable.reduce(0) { $0 + $1.branches.count }
        return Button(action: model.pullAll) {
            Text(model.pullAllProgress.map { "Pulling \($0.done)/\($0.total)" } ?? "Pull All")
                .monospacedDigit()
        }
        .disabled(branches == 0 || model.pullAllProgress != nil || model.fetchAllProgress != nil)
        .help(branches == 0
              ? "Nothing to pull. Fetch All first to check for new commits."
              : "Fast-forward \(branches) branch\(branches == 1 ? "" : "es") in \(pullable.count) repo\(pullable.count == 1 ? "" : "s") that \(branches == 1 ? "is" : "are") behind. Never merges or rebases.")
    }

    /// Folder controls live with the folder tree.
    private var sidebarFooter: some View {
        HStack(spacing: 2) {
            Button(action: addFolders) { Image(systemName: "plus").font(.system(size: 12, weight: .medium)) }
                .help("Add folders to scan for repositories (⇧⌘O)")
                .accessibilityLabel("Add folders")
            Button(action: model.rescan) { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
                .disabled(model.roots.isEmpty || model.isScanning)
                .help("Rescan folders (⌘R)")
                .accessibilityLabel("Rescan folders")
            if model.isScanning { Spinner(size: 10).padding(.leading, 6) }
            Spacer(minLength: 8)
            Text(summary)
                .font(.dsCaption)
                .monospacedDigit()
                .foregroundStyle(Palette.textFaint)
                .lineLimit(1)
                .help(model.roots.map(\.path).joined(separator: "\n"))
            SettingsLink { Image(systemName: "gearshape").font(.system(size: 12, weight: .medium)) }
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
                .padding(.leading, 6)
        }
        .buttonStyle(IconButtonStyle())
        .padding(.horizontal, 10)
        .frame(height: 40)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let repo = selectedRepo {
            RepoDetail(repo: repo)
                .overlay(alignment: .bottom) {
                    // Only once something deletable is selected (the main checkout isn't). Steps
                    // aside for a dialog, which takes Escape instead.
                    let deletable = model.deletionItems(model.selection)
                    if !deletable.isEmpty && activeConfirm == nil {
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
        } else if let folder = selectedFolder {
            EmptyState(symbol: "folder", title: folder.url.lastPathComponent,
                       message: "\(folder.repoCount) repositor\(folder.repoCount == 1 ? "y" : "ies") in \((folder.url.path as NSString).abbreviatingWithTildeInPath)") {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                    .buttonStyle(.ds)
            }
        } else {
            Overview()
        }
    }

    /// A folder selected in the sidebar: an added folder, or a parent folder of repos inside one.
    private var selectedFolder: (url: URL, repoCount: Int)? {
        for node in RootNode.tree(roots: model.roots, repos: model.repos) {
            if node.root.path == selectedPath {
                return (node.root, node.groups.reduce(0) { $0 + $1.repos.count })
            }
            if let group = node.groups.first(where: { $0.url?.path == selectedPath }), let url = group.url {
                return (url, group.repos.count)
            }
        }
        return nil
    }

    // MARK: - Deletion dialog

    /// The sidebar's question, or the pending deletion.
    private var activeConfirm: ConfirmRequest? {
        confirmRequest ?? model.deletionRequest.map(deletionConfirm)
    }

    private func deletionConfirm(_ request: DeletionRequest) -> ConfirmRequest {
        let items = sorted(request.items)
        var actions: [ConfirmRequest.Action] = []
        if request.force {
            actions.append(.init(title: "Force Delete") {
                runDeletion(items, force: true, alsoBranches: request.alsoBranches)
            })
        } else {
            // Only the choices that apply to what's selected.
            let branchRows = items.filter { !$0.isWorktree }
            let worktreeRows = items.filter(\.isWorktree)
            if !branchRows.isEmpty {
                actions.append(.init(title: "Delete \(count(branchRows.count, "Branch", "Branches"))") {
                    runDeletion(branchRows, force: false, alsoBranches: false)
                })
            }
            if !worktreeRows.isEmpty {
                actions.append(.init(title: "Delete \(count(worktreeRows.count, "Worktree", "Worktrees"))") {
                    runDeletion(worktreeRows, force: false, alsoBranches: false)
                })
                let branches = branchRows.count + worktreeRows.filter(model.hasBranch).count
                if branches > 0 {
                    actions.append(.init(title: "Delete \(count(branches, "Branch", "Branches")) and \(count(worktreeRows.count, "Worktree", "Worktrees"))") {
                        runDeletion(items, force: false, alsoBranches: true)
                    })
                }
            }
        }
        return ConfirmRequest(title: dialogTitle(request), message: dialogMessage(request), actions: actions)
    }

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

    /// "42 repos in 2 folders".
    private var summary: String {
        if model.isScanning { return "Scanning…" }
        return "\(model.repos.count) repo\(model.repos.count == 1 ? "" : "s") in \(model.roots.count) folder\(model.roots.count == 1 ? "" : "s")"
    }

    private var selectedRepo: Repo? { model.repos.first { $0.url.path == selectedPath } }

    private func addFolders() { model.chooseFoldersToAdd() }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
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
        HStack(spacing: 8) {
            Text(summary)
                .font(.dsLabel)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 4)
            if isBusy { Spinner() }
            Button("Clear", action: clear)
                .buttonStyle(.ds(.secondary, small: true))
                .fixedSize()
                .keyboardShortcut(.cancelAction)
            Button("Delete…", action: delete)
                .buttonStyle(.ds(.danger, small: true))
                .fixedSize()
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(isBusy)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Palette.overlay, in: RoundedRectangle(cornerRadius: Metric.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.radiusLarge, style: .continuous).strokeBorder(Palette.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }
}
