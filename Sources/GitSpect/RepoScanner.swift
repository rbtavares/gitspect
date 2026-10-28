import Foundation

struct Worktree: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    /// Checked-out branch, or nil when HEAD is detached.
    let branch: String?
    let detachedAt: String?
    let isMain: Bool
    /// The worktree's directory no longer exists (would be pruned by `git worktree prune`).
    let isMissing: Bool
}

struct Repo: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    /// The added folder this repo was found under, as the user chose it.
    let root: URL
    let relativePath: String
    let branches: [String]
    let worktrees: [Worktree]

    var currentBranch: String? { worktrees.first(where: \.isMain)?.branch }
}

/// Read-only filesystem walk. Never invokes `git` (which can write `.git/index`).
enum RepoScanner {
    private static let skippedDirectories: Set<String> = ["node_modules", "Pods", "DerivedData"]

    static func scan(root: URL) -> [Repo] {
        let fm = FileManager.default
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()

        if let repo = repo(at: resolvedRoot, root: root) {
            return [repo]
        }

        guard let enumerator = fm.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var repos: [Repo] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true
            else { continue }

            let name = url.lastPathComponent
            if name.hasPrefix(".") || skippedDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if let repo = repo(at: url, root: root) {
                repos.append(repo)
                enumerator.skipDescendants()
            }
        }

        // Linked worktrees found on disk are already listed under their owning repo.
        let linkedPaths = Set(repos.flatMap { $0.worktrees.filter { !$0.isMain }.map { canonical($0.path) } })
        return repos
            .filter { !linkedPaths.contains(canonical($0.url.path)) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// `root` is the added folder as the user chose it; paths are made relative to its resolved form.
    static func repo(at dir: URL, root: URL) -> Repo? {
        let dotGit = dir.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: dotGit.path),
              let gitDir = resolveGitDir(dotGit: dotGit)
        else { return nil }

        let commonDir = resolveCommonDir(gitDir: gitDir)
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        var relative = dir.path.hasPrefix(rootPath) ? String(dir.path.dropFirst(rootPath.count)) : dir.path
        if relative.isEmpty { relative = "." }

        let head = readHead(gitDir: gitDir)
        var worktrees = [Worktree(
            name: dir.lastPathComponent, path: dir.path, branch: head.branch,
            detachedAt: head.detachedAt, isMain: true, isMissing: false
        )]
        worktrees += linkedWorktrees(commonDir: commonDir).filter { $0.path != dir.path }

        return Repo(
            url: dir, name: dir.lastPathComponent, root: root, relativePath: relative,
            branches: branches(commonDir: commonDir), worktrees: worktrees
        )
    }

    /// `.git` is a directory for regular repos, or a file with `gitdir: <path>` for worktrees and submodules.
    private static func resolveGitDir(dotGit: URL) -> URL? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir)
        if isDir.boolValue { return dotGit }
        guard let path = readValue(dotGit, prefix: "gitdir:") else { return nil }
        return URL(fileURLWithPath: path, relativeTo: dotGit.deletingLastPathComponent()).standardizedFileURL
    }

    /// Linked worktrees keep refs and the worktree registry in the shared "common" dir.
    private static func resolveCommonDir(gitDir: URL) -> URL {
        guard let path = readLine(gitDir.appendingPathComponent("commondir")) else { return gitDir }
        return URL(fileURLWithPath: path, relativeTo: gitDir.appendingPathComponent("/")).standardizedFileURL
    }

    private static func readHead(gitDir: URL) -> (branch: String?, detachedAt: String?) {
        guard let head = readLine(gitDir.appendingPathComponent("HEAD")) else { return (nil, nil) }
        let prefix = "ref: refs/heads/"
        if head.hasPrefix(prefix) { return (String(head.dropFirst(prefix.count)), nil) }
        return (nil, String(head.prefix(7)))
    }

    private static func linkedWorktrees(commonDir: URL) -> [Worktree] {
        let registry = commonDir.appendingPathComponent("worktrees")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: registry, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries.compactMap { entry -> Worktree? in
            // `gitdir` holds the absolute path of the worktree's `.git` file.
            guard let gitdirPath = readLine(entry.appendingPathComponent("gitdir")) else { return nil }
            let path = URL(fileURLWithPath: gitdirPath).deletingLastPathComponent().standardizedFileURL.path
            let head = readHead(gitDir: entry)
            return Worktree(
                name: URL(fileURLWithPath: path).lastPathComponent, path: path, branch: head.branch,
                detachedAt: head.detachedAt, isMain: false,
                isMissing: !FileManager.default.fileExists(atPath: path)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Local branches from loose refs plus `packed-refs`.
    private static func branches(commonDir: URL) -> [String] {
        var names = Set<String>()

        let headsDir = commonDir.appendingPathComponent("refs/heads")
        if let enumerator = FileManager.default.enumerator(
            at: headsDir, includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            let base = headsDir.standardizedFileURL.path + "/"
            for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let path = url.standardizedFileURL.path
                if path.hasPrefix(base) { names.insert(String(path.dropFirst(base.count))) }
            }
        }

        if let packed = try? String(contentsOf: commonDir.appendingPathComponent("packed-refs"), encoding: .utf8) {
            for line in packed.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
                let parts = line.split(separator: " ", maxSplits: 1)
                if parts.count == 2, parts[1].hasPrefix("refs/heads/") {
                    names.insert(String(parts[1].dropFirst("refs/heads/".count)))
                }
            }
        }

        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// `realpath`, since Foundation's symlink resolution maps `/private/tmp` to `/tmp` while git records the former.
    private static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func readLine(_ url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    private static func readValue(_ url: URL, prefix: String) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) })
        else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
