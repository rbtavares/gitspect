import Foundation
import Observation

enum RepoOperation: Hashable, Sendable {
    case fetch
    case pull(branch: String)
    case push(branch: String)
    case delete(branch: String)
    case removeWorktree(path: String)
}

/// What a row can delete: a local branch on its own, or a linked worktree (and, when asked, the
/// branch it has checked out).
enum Selectable: Hashable, Sendable {
    case branch(repo: URL, name: String)
    case worktree(repo: URL, path: String)

    var repo: URL {
        switch self {
        case .branch(let repo, _), .worktree(let repo, _): repo
        }
    }

    var isWorktree: Bool {
        if case .worktree = self { true } else { false }
    }
}

enum DeleteOutcome: Sendable {
    case deleted
    /// Git wants force: an unmerged branch, or a worktree with modified or untracked files.
    case refused
    case failed
}

/// One command shown in the output drawer.
struct LogEntry: Identifiable {
    enum Status { case running, succeeded, failed }

    let id = UUID()
    let repo: String
    let command: String
    let startedAt = Date()
    var finishedAt: Date?
    var status = Status.running
    var output = ""
}

/// Items awaiting the user's confirmation before deletion.
struct DeletionRequest: Identifiable {
    let id = UUID()
    let items: [Selectable]
    /// A retry of items git refused; confirming passes `--force` / `-D`.
    let force: Bool
    /// For a retry: also delete the branches of removed worktrees, as first asked.
    var alsoBranches = false
}

/// A line in the repo view: a branch, a worktree, or a worktree with its branch.
struct RowID: Hashable, Sendable {
    let repo: URL
    /// `CheckoutPair.id`.
    let pair: String
}

@Observable
@MainActor
final class ScanModel {
    private static let rootsKey = "rootPaths"
    /// Single-folder setting from before multiple folders were supported.
    private static let legacyRootKey = "rootPath"
    private static let concurrency = 12
    private static let networkTimeout: Duration = .seconds(120)
    private static let localTimeout: Duration = .seconds(60)
    private static let logLimit = 200

    private(set) var roots: [URL] = []
    private(set) var repos: [Repo] = []
    private(set) var isScanning = false
    private(set) var statuses: [URL: [String: BranchStatus]] = [:]
    private(set) var running: [URL: RepoOperation] = [:]
    private(set) var errors: [URL: String] = [:]
    private(set) var fetchAllProgress: (done: Int, total: Int)?
    private(set) var pullAllProgress: (done: Int, total: Int)?
    /// Selected rows. The row being looked at (graph open) is one of them.
    private(set) var selection: Set<RowID> = []
    private var selectionAnchor: RowID?
    /// The branch shown in the graph pane, if it's open, and the row it was opened from.
    private(set) var graphTarget: GraphTarget?
    private var graphRow: RowID?
    var deletionRequest: DeletionRequest?
    private(set) var log: [LogEntry] = []
    /// The output drawer starts hidden each launch and opens with the first command that runs,
    /// unless it has been closed this session.
    private(set) var showsOutput = false
    private var outputDismissed = false
    private var scanTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: Self.rootsKey)
            ?? defaults.string(forKey: Self.legacyRootKey).map { [$0] }
            ?? []
        roots = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if !roots.isEmpty { rescan() }
    }

    /// Adds folders to scan; folders already added are ignored.
    func add(roots added: [URL]) {
        let known = Set(roots.map(\.standardizedFileURL))
        roots += added.filter { !known.contains($0.standardizedFileURL) }
        saveRoots()
        rescan()
    }

    func remove(root: URL) {
        roots.removeAll { $0 == root }
        saveRoots()
        rescan()
    }

    private func saveRoots() {
        UserDefaults.standard.set(roots.map(\.path), forKey: Self.rootsKey)
    }

    func rescan() {
        scanTask?.cancel()
        clearSelection()
        guard !roots.isEmpty else {
            repos = []
            isScanning = false
            return
        }
        isScanning = true
        let roots = roots
        scanTask = Task {
            // Walk every folder in parallel, keeping results in the order the folders were added.
            let found = await withTaskGroup(of: (Int, [Repo]).self) { group in
                for (index, root) in roots.enumerated() {
                    group.addTask(priority: .userInitiated) { (index, RepoScanner.scan(root: root)) }
                }
                var results = [[Repo]](repeating: [], count: roots.count)
                for await (index, repos) in group { results[index] = repos }
                return results.flatMap { $0 }
            }
            guard !Task.isCancelled else { return }
            // A repo under two overlapping folders is listed once, under the first.
            var seen = Set<URL>()
            repos = found.filter { seen.insert($0.url).inserted }
            isScanning = false
            await forEach(repos) { await self.refreshStatus($0.url) }
        }
    }

    // MARK: - Remote operations

    func fetch(_ repo: Repo) async {
        await perform(.fetch, on: repo.url) {
            _ = try await runLogged(["fetch", "--all", "--prune"], in: repo.url, repo: repo, timeout: Self.networkTimeout)
        }
    }

    func fetchAll() {
        // Not alongside Pull All: a repo busy with one skips the other's command.
        guard fetchAllProgress == nil, pullAllProgress == nil else { return }
        let targets = repos.filter { !$0.isLocalOnly }
        fetchAllProgress = (0, targets.count)
        Task {
            await forEach(targets) { repo in
                await self.fetch(repo)
                self.fetchAllProgress?.done += 1
            }
            fetchAllProgress = nil
        }
    }

    /// Fast-forward only: never merges or rebases.
    func pull(_ repo: Repo, branch: String) {
        Task { await pullBranch(repo, branch: branch) }
    }

    private func pullBranch(_ repo: Repo, branch: String) async {
        guard let status = statuses[repo.url]?[branch] else { return }
        await perform(.pull(branch: branch), on: repo.url) {
            if let worktree = repo.worktrees.first(where: { $0.branch == branch && !$0.isMissing }) {
                _ = try await runLogged(
                    ["pull", "--ff-only"], in: URL(fileURLWithPath: worktree.path), repo: repo, timeout: Self.networkTimeout
                )
            } else {
                // Not checked out anywhere: fast-forward the ref to the already-fetched upstream.
                _ = try await runLogged(["fetch", ".", "\(status.upstreamRef):refs/heads/\(branch)"], in: repo.url, repo: repo)
            }
        }
    }

    /// Branches behind their upstream that can be fast-forwarded (not diverged), by repo.
    var pullableBranches: [(repo: Repo, branches: [String])] {
        repos.compactMap { repo in
            let branches = pullableBranches(in: repo)
            return branches.isEmpty ? nil : (repo, branches)
        }
    }

    func pullableBranches(in repo: Repo) -> [String] {
        (statuses[repo.url] ?? [:])
            .filter { $0.value.behind > 0 && $0.value.ahead == 0 && !$0.value.isGone }
            .keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Fast-forwards every pullable branch. Repos run in parallel; one repo's branches run in turn,
    /// since git can't safely run two commands on a repo at once.
    func pullAll() {
        guard pullAllProgress == nil, fetchAllProgress == nil else { return }
        let targets = pullableBranches
        pullAllProgress = (0, targets.reduce(0) { $0 + $1.branches.count })
        Task {
            await forEach(targets) { target in
                for branch in target.branches {
                    await self.pullBranch(target.repo, branch: branch)
                    self.pullAllProgress?.done += 1
                }
            }
            pullAllProgress = nil
        }
    }

    /// Plain push to the configured upstream; rejected by git if it isn't a fast-forward.
    func push(_ repo: Repo, branch: String) {
        Task { await pushBranch(repo, branch: branch) }
    }

    private func pushBranch(_ repo: Repo, branch: String) async {
        guard let status = statuses[repo.url]?[branch], status.canPush(branch) else { return }
        await perform(.push(branch: branch), on: repo.url) {
            _ = try await runLogged(
                ["push", status.remote, "refs/heads/\(branch):\(status.remoteRef)"], in: repo.url, repo: repo,
                timeout: Self.networkTimeout
            )
        }
    }

    /// Branches in `repo` that are ahead and can be pushed as-is: not diverged, and to an upstream
    /// branch of the same name.
    func pushableBranches(in repo: Repo) -> [String] {
        (statuses[repo.url] ?? [:])
            .filter { $0.value.ahead > 0 && $0.value.behind == 0 && !$0.value.isGone && $0.value.canPush($0.key) }
            .keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Fast-forwards every pullable branch in one repo, one at a time.
    func pullAll(in repo: Repo) {
        let branches = pullableBranches(in: repo)
        Task { for branch in branches { await pullBranch(repo, branch: branch) } }
    }

    /// Pushes every pushable branch in one repo, one at a time.
    func pushAll(in repo: Repo) {
        let branches = pushableBranches(in: repo)
        Task { for branch in branches { await pushBranch(repo, branch: branch) } }
    }

    // MARK: - Deletion

    func requestDeletion(_ items: [Selectable]) {
        deletionRequest = DeletionRequest(items: items, force: false)
    }

    /// Repos are processed in parallel; git can't safely run two commands on one repo at once,
    /// so each repo's items run in order. Items git refuses without force (dirty worktrees,
    /// unmerged branches) come back as a new request for the user to confirm.
    ///
    /// `alsoBranches` also deletes the branch each removed worktree had checked out.
    func delete(_ items: [Selectable], force: Bool, alsoBranches: Bool) async {
        let byRepo = Array(Dictionary(grouping: items, by: \.repo).values)
        let refused = await forEach(byRepo) { items in
            await self.deleteInRepo(items, force: force, alsoBranches: alsoBranches)
        }.flatMap { $0 }
        pruneSelection()

        if !refused.isEmpty {
            deletionRequest = DeletionRequest(items: refused, force: true, alsoBranches: alsoBranches)
        }
    }

    /// The deletable items among `rows`, in display order. The main checkout has none.
    func deletionItems(_ rows: Set<RowID>) -> [Selectable] {
        repos.flatMap { repo in
            repo.pairs.compactMap { rows.contains(RowID(repo: repo.url, pair: $0.id)) ? repo.rowItem($0) : nil }
        }
    }

    /// Whether a worktree item has a branch checked out (detached worktrees don't).
    func hasBranch(_ item: Selectable) -> Bool {
        guard case .worktree(let repoURL, let path) = item else { return true }
        return repo(repoURL)?.worktrees.first { $0.path == path }?.branch != nil
    }

    /// Items from a single repo. Worktrees go first so their branches become deletable.
    /// Returns the items git refused without force.
    private func deleteInRepo(_ items: [Selectable], force: Bool, alsoBranches: Bool) async -> [Selectable] {
        var refused: [Selectable] = []
        var branches: [(item: Selectable, force: Bool)] = []

        for item in items {
            switch item {
            case .worktree(let repoURL, let path):
                guard let repo = repo(repoURL) else { continue }
                let branch = repo.worktrees.first { $0.path == path }?.branch
                switch await removeWorktree(repo, path: path, force: force) {
                case .deleted:
                    // Never forced on the first try: an unmerged branch comes back to confirm.
                    if alsoBranches, let branch { branches.append((.branch(repo: repoURL, name: branch), false)) }
                case .refused: refused.append(item)
                case .failed: break
                }
            case .branch:
                branches.append((item, force))
            }
        }

        for (item, force) in branches {
            guard case .branch(let repoURL, let name) = item, let repo = repo(repoURL) else { continue }
            switch await deleteBranch(repo, branch: name, force: force) {
            case .deleted:
                if graphTarget == GraphTarget(repo: repoURL, branch: name) { graphTarget = nil }
            case .refused: refused.append(item)
            case .failed: break
            }
        }
        return refused
    }

    /// Deletes the local branch only; `force` uses `-D` for unmerged branches.
    private func deleteBranch(_ repo: Repo, branch: String, force: Bool) async -> DeleteOutcome {
        var outcome = DeleteOutcome.failed
        await perform(.delete(branch: branch), on: repo.url) {
            do {
                _ = try await runLogged(["branch", force ? "-D" : "-d", branch], in: repo.url, repo: repo)
                outcome = .deleted
            } catch let error as GitError where !force && error.message.contains("not fully merged") {
                outcome = .refused
            }
        }
        if outcome == .deleted { reload(repo) }
        return outcome
    }

    /// `git worktree remove`; without `force` git refuses worktrees with modified or untracked files.
    /// Locked worktrees are never overridden.
    private func removeWorktree(_ repo: Repo, path: String, force: Bool) async -> DeleteOutcome {
        var outcome = DeleteOutcome.failed
        await perform(.removeWorktree(path: path), on: repo.url) {
            do {
                _ = try await runLogged(["worktree", "remove"] + (force ? ["--force"] : []) + [path], in: repo.url, repo: repo)
                outcome = .deleted
            } catch let error as GitError where !force && error.message.contains("use --force") {
                outcome = .refused
            }
        }
        if outcome == .deleted { reload(repo) }
        return outcome
    }

    // MARK: - Selection

    enum SelectMode { case only, toggle, extend }

    /// List-style: a click selects just that row (clicking the only selected row again clears it),
    /// ⌘ toggles a row, ⇧ extends a range from the last clicked row within one repo.
    /// The graph shows the clicked row while it's selected.
    func select(_ row: RowID, mode: SelectMode) {
        switch mode {
        case .only:
            if selection == [row] { return clearSelection() }
            selection = [row]
            selectionAnchor = row
        case .toggle:
            if selection.remove(row) == nil {
                selection.insert(row)
                selectionAnchor = row
            }
        case .extend:
            guard let anchor = selectionAnchor, anchor.repo == row.repo, let repo = repo(row.repo)
            else { return select(row, mode: .toggle) }
            let ordered = repo.pairs.map { RowID(repo: repo.url, pair: $0.id) }
            guard let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: row)
            else { return select(row, mode: .toggle) }
            selection.formUnion(ordered[min(from, to)...max(from, to)])
        }

        if selection.contains(row) {
            showGraph(for: row)
        } else if let graphRow, !selection.contains(graphRow) {
            // The row on show was deselected: show another selected one, if any.
            if let next = repo(row.repo)?.pairs.map({ RowID(repo: row.repo, pair: $0.id) }).first(where: selection.contains) {
                showGraph(for: next)
            } else {
                closeGraph()
            }
        }
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
        closeGraph()
    }

    /// Drops rows that no longer exist, e.g. after deleting them.
    private func pruneSelection() {
        let rows = Set(repos.flatMap { repo in repo.pairs.map { RowID(repo: repo.url, pair: $0.id) } })
        selection.formIntersection(rows)
        if let graphRow, !rows.contains(graphRow) { self.graphRow = nil }
        if let anchor = selectionAnchor, !rows.contains(anchor) { selectionAnchor = nil }
    }

    // MARK: - Graph

    /// The graph of a row's branch (its own, or the one its worktree has checked out).
    /// Rows without a branch with commits, like a detached worktree, close the graph.
    private func showGraph(for row: RowID) {
        guard let repo = repo(row.repo), let branch = repo.pairs.first(where: { $0.id == row.pair })?.branch,
              repo.branches.contains(branch)
        else { return closeGraph() }
        graphTarget = GraphTarget(repo: repo.url, branch: branch)
        graphRow = row
    }

    func closeGraph() {
        graphTarget = nil
        graphRow = nil
    }

    // MARK: - Output log

    /// Show or hide the output drawer. Hiding it keeps it closed for the rest of the session.
    func setOutputVisible(_ visible: Bool) {
        showsOutput = visible
        if !visible { outputDismissed = true }
    }

    func clearLog() {
        log.removeAll { $0.status != .running }
    }

    /// Runs git and records the command and its live output in the drawer.
    private func runLogged(
        _ args: [String], in dir: URL, repo: Repo, timeout: Duration = localTimeout
    ) async throws -> String {
        let entry = LogEntry(repo: repo.name, command: "git " + args.joined(separator: " "))
        let id = entry.id
        log.append(entry)
        if !showsOutput && !outputDismissed { showsOutput = true }
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }

        do {
            let output = try await Git.run(args, in: dir, timeout: timeout) { chunk in
                Task { @MainActor in self.appendLog(chunk, to: id) }
            }
            finishLog(id, status: .succeeded)
            return output
        } catch {
            // Git's stderr is already in the log; add only errors that never reached the pipes.
            if (error as? GitError)?.fromStderr != true {
                appendLog(error.localizedDescription + "\n", to: id)
            }
            finishLog(id, status: .failed)
            throw error
        }
    }

    private func appendLog(_ chunk: String, to id: UUID) {
        guard let index = log.firstIndex(where: { $0.id == id }) else { return }
        log[index].output += chunk
    }

    private func finishLog(_ id: UUID, status: LogEntry.Status) {
        guard let index = log.firstIndex(where: { $0.id == id }) else { return }
        log[index].status = status
        log[index].finishedAt = Date()
    }

    // MARK: - Helpers

    /// Re-reads one repo from disk after a change to its branches.
    private func repo(_ url: URL) -> Repo? { repos.first { $0.url == url } }

    private func reload(_ repo: Repo) {
        guard let index = repos.firstIndex(where: { $0.id == repo.id }),
              let updated = RepoScanner.repo(at: repo.url, root: repo.root)
        else { return }
        repos[index] = updated
    }

    private func perform(_ operation: RepoOperation, on repo: URL, _ body: () async throws -> Void) async {
        guard running[repo] == nil else { return }
        running[repo] = operation
        errors[repo] = nil
        do {
            try await body()
        } catch {
            errors[repo] = error.localizedDescription
        }
        await refreshStatus(repo)
        running[repo] = nil
    }

    private func refreshStatus(_ repo: URL) async {
        statuses[repo] = (try? await BranchStatus.load(repo: repo)) ?? [:]
    }

    /// Runs `body` for each element with bounded parallelism; results come back in completion order.
    @discardableResult
    private func forEach<T: Sendable, R: Sendable>(
        _ elements: [T], _ body: @escaping @MainActor (T) async -> R
    ) async -> [R] {
        await withTaskGroup(of: R.self) { group in
            var results: [R] = []
            var pending = elements[...]
            for _ in 0..<Self.concurrency {
                guard let element = pending.popFirst() else { break }
                group.addTask { await body(element) }
            }
            for await result in group {
                results.append(result)
                if let element = pending.popFirst() { group.addTask { await body(element) } }
            }
            return results
        }
    }
}
