import Foundation

/// The branch whose history the graph pane shows.
struct GraphTarget: Hashable, Sendable {
    let repo: URL
    let branch: String
}

struct GraphCommit: Identifiable, Hashable, Sendable {
    var id: String { hash }
    let hash: String
    let parents: [String]
    let author: String
    let date: Date
    let subject: String
    /// Branches and tags pointing at this commit.
    let refs: [GraphRef]
    let isHead: Bool

    var shortHash: String { String(hash.prefix(7)) }
}

struct GraphRef: Hashable, Sendable {
    enum Kind: Sendable { case local, remote, tag }
    let kind: Kind
    /// `main`, `origin/main` or `v1.0`.
    let name: String

    /// Parses a full ref name from `--decorate=full`; nil for refs that aren't shown.
    init?(fullName: String) {
        for (prefix, kind) in [("refs/heads/", Kind.local), ("refs/remotes/", .remote), ("tag: refs/tags/", .tag)]
        where fullName.hasPrefix(prefix) {
            name = String(fullName.dropFirst(prefix.count))
            self.kind = kind
            // origin/HEAD only says which branch the remote defaults to.
            if kind == .remote && name.hasSuffix("/HEAD") { return nil }
            return
        }
        return nil
    }
}

/// One commit laid out in the graph. Lanes are columns of lines; each holds the hash of the
/// commit it is heading towards (nil when free). Lanes keep their index from row to row, so
/// lines that pass a commit by are straight.
struct GraphRow: Identifiable, Sendable {
    var id: String { commit.hash }
    let commit: GraphCommit
    /// The lane the commit's dot sits in.
    let column: Int
    /// Lanes entering the row from above, and leaving it below.
    let lanesIn: [String?]
    let lanesOut: [String?]
    /// Lane each parent continues in, in parent order.
    let parentColumns: [Int]
}

/// What the commit drawer shows beyond the graph row.
struct CommitDetails: Sendable {
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let committerName: String
    let committerEmail: String
    let commitDate: Date
    let message: String
    /// Against the first parent, or everything for a root commit.
    let files: [FileChange]
}

struct FileChange: Identifiable, Sendable {
    var id: String { (oldPath ?? "") + "\0" + path }
    let path: String
    /// Set when the file was renamed or moved.
    let oldPath: String?
    /// Lines added and removed; nil for binary files.
    let added: Int?
    let deleted: Int?
}

enum GitGraph {
    static let commitLimit = 400

    static func details(repo: URL, commit: GraphCommit) async throws -> CommitDetails {
        let format = ["%an", "%ae", "%at", "%cn", "%ce", "%ct", "%B"].joined(separator: "%x1f")
        let meta = try await Git.run(
            ["--no-optional-locks", "show", "-s", "--no-color", "--format=\(format)", commit.hash], in: repo
        )
        let fields = meta.split(separator: "\u{1f}", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7 else { throw GitError(message: "Unexpected output from git show") }

        let base = commit.parents.first.map { [$0] } ?? ["--root"]
        let stat = try await Git.run(
            ["--no-optional-locks", "diff-tree", "-r", "-M", "--numstat", "-z", "--no-commit-id"] + base + [commit.hash],
            in: repo
        )

        return CommitDetails(
            authorName: fields[0], authorEmail: fields[1], authorDate: date(fields[2]),
            committerName: fields[3], committerEmail: fields[4], commitDate: date(fields[5]),
            message: fields[6].trimmingCharacters(in: .whitespacesAndNewlines), files: parseNumstat(stat)
        )
    }

    /// `--numstat -z`: `added\tdeleted\tpath\0`, or for a rename `added\tdeleted\t\0old\0new\0`.
    /// Binary files report `-` for both counts.
    static func parseNumstat(_ output: String) -> [FileChange] {
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: false)[...]
        var files: [FileChange] = []
        while let token = tokens.popFirst() {
            let parts = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let added = Int(parts[0]), deleted = Int(parts[1])
            if parts[2].isEmpty {
                guard let old = tokens.popFirst(), let new = tokens.popFirst() else { break }
                files.append(FileChange(path: String(new), oldPath: String(old), added: added, deleted: deleted))
            } else {
                files.append(FileChange(path: String(parts[2]), oldPath: nil, added: added, deleted: deleted))
            }
        }
        return files
    }

    private static func date(_ seconds: String) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds) ?? 0)
    }

    /// History of `branch` and, when given, its upstream, newest first.
    static func load(repo: URL, branch: String, upstreamRef: String?) async throws -> [GraphCommit] {
        let format = ["%H", "%P", "%an", "%at", "%D", "%s"].joined(separator: "%x1f") + "%x1e"
        let revisions = ["refs/heads/\(branch)"] + (upstreamRef.map { [$0] } ?? [])
        let output = try await Git.run(
            ["--no-optional-locks", "log", "--topo-order", "--no-color", "--decorate=full",
             "-n", "\(commitLimit)", "--format=\(format)"] + revisions + ["--"],
            in: repo
        )
        return output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.trimmingCharacters(in: .newlines)
                .split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6 else { return nil }
            var isHead = false
            let refs = fields[4].split(separator: ",").compactMap { raw -> GraphRef? in
                var ref = raw.trimmingCharacters(in: .whitespaces)
                if ref.hasPrefix("HEAD -> ") { isHead = true; ref.removeFirst("HEAD -> ".count) }
                if ref == "HEAD" { isHead = true; return nil }
                return GraphRef(fullName: ref)
            }
            return GraphCommit(
                hash: fields[0], parents: fields[1].split(separator: " ").map(String.init),
                author: fields[2], date: Date(timeIntervalSince1970: TimeInterval(fields[3]) ?? 0),
                subject: fields[5], refs: refs, isHead: isHead
            )
        }
    }

    /// Assigns each commit a lane. Commits must be in topological order, children before parents.
    static func layout(_ commits: [GraphCommit]) -> [GraphRow] {
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            let lanesIn = lanes
            // A lane already heading here, else the first free one (a branch tip).
            let column = lanes.firstIndex(of: commit.hash) ?? lanes.firstIndex(of: nil) ?? lanes.count
            if column == lanes.count { lanes.append(nil) }
            // Every lane heading here ends at this commit.
            for index in lanes.indices where lanes[index] == commit.hash { lanes[index] = nil }

            var parentColumns: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(of: parent) {
                    // Already on its way down another lane: join it.
                    parentColumns.append(existing)
                } else if index == 0 {
                    // The first parent carries on straight down.
                    lanes[column] = parent
                    parentColumns.append(column)
                } else {
                    let free = lanes.firstIndex(of: nil) ?? lanes.count
                    if free == lanes.count { lanes.append(nil) }
                    lanes[free] = parent
                    parentColumns.append(free)
                }
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }

            rows.append(GraphRow(commit: commit, column: column, lanesIn: lanesIn, lanesOut: lanes,
                                 parentColumns: parentColumns))
        }
        return rows
    }
}
