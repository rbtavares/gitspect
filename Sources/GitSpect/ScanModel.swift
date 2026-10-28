import Foundation
import Observation

enum RepoOperation: Hashable, Sendable {
    case fetch
    case pull(branch: String)
    case push(branch: String)
    case delete(branch: String)
    case removeWorktree(path: String)
}

/// Something the user can select and delete: a local branch or a linked worktree.
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
    /// Also delete the branches of removed worktrees.
    let alsoBranches: Bool
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
    private(set) var selection: Set<Selectable> = []
    private var selectionAnchor: Selectable?
    /// The branch shown in the graph pane, if it's open.
    private(set) var graphTarget: GraphTarget?
    var deletionRequest: DeletionRequest?
    private(set) var log: [LogEntry] = []
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
            let branches = (statuses[repo.url] ?? [:])
                .filter { $0.value.behind > 0 && $0.value.ahead == 0 && !$0.value.isGone }
                .keys
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return branches.isEmpty ? nil : (repo, branches)
        }
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
        guard let status = statuses[repo.url]?[branch], status.canPush(branch) else { return }
        Task {
            await perform(.push(branch: branch), on: repo.url) {
                _ = try await runLogged(
                    ["push", status.remote, "refs/heads/\(branch):\(status.remoteRef)"], in: repo.url, repo: repo,
                    timeout: Self.networkTimeout
                )
            }
        }
    }

    // MARK: - Deletion

    func requestDeletion(_ items: [Selectable]) {
        deletionRequest = DeletionRequest(items: items, force: false, alsoBranches: false)
    }

    /// Repos are processed in parallel; git can't safely run two commands on one repo at once,
    /// so each repo's items run in order. Items git refuses without force (dirty worktrees,
    /// unmerged branches) come back as a new request for the user to confirm.
    func delete(_ items: [Selectable], force: Bool, alsoBranches: Bool) async {
        let byRepo = Array(Dictionary(grouping: items, by: \.repo).values)
        let refused = await forEach(byRepo) { items in
            await self.deleteInRepo(items, force: force, alsoBranches: alsoBranches)
        }.flatMap { $0 }

        if !refused.isEmpty {
            deletionRequest = DeletionRequest(items: refused, force: true, alsoBranches: alsoBranches)
        }
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
                    selection.remove(item)
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
                selection.remove(item)
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

    /// Finder-style: click selects one, ⌘ toggles, ⇧ extends a range of the same kind within one repo.
    func select(_ item: Selectable, mode: SelectMode) {
        switch mode {
        case .only:
            selection = selection == [item] ? [] : [item]
            selectionAnchor = item
        case .toggle:
            if selection.remove(item) == nil { selection.insert(item) }
            selectionAnchor = item
        case .extend:
            guard let anchor = selectionAnchor, anchor.repo == item.repo, anchor.isWorktree == item.isWorktree,
                  let repo = repo(item.repo)
            else { return select(item, mode: .toggle) }
            let ordered = item.isWorktree
                ? repo.removableWorktrees.map { Selectable.worktree(repo: repo.url, path: $0.path) }
                : repo.deletableBranches.map { Selectable.branch(repo: repo.url, name: $0) }
            guard let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: item)
            else { return select(item, mode: .toggle) }
            selection.formUnion(ordered[min(from, to)...max(from, to)])
        }
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    // MARK: - Graph

    /// Opens the graph for a branch; showing the branch already open closes it again.
    func toggleGraph(_ target: GraphTarget) {
        graphTarget = graphTarget == target ? nil : target
    }

    func closeGraph() {
        graphTarget = nil
    }

    // MARK: - Output log

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
