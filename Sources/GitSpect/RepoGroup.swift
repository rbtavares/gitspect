import Foundation

/// An added folder and the repos found under it, grouped by parent folder.
struct RootNode: Identifiable, Sendable {
    var id: URL { root }
    let root: URL
    let groups: [RepoGroup]

    /// One node per root, in the order the folders were added.
    static func tree(roots: [URL], repos: [Repo]) -> [RootNode] {
        let byRoot = Dictionary(grouping: repos, by: \.root)
        return roots.map { RootNode(root: $0, groups: RepoGroup.grouping(byRoot[$0] ?? [], in: $0)) }
    }
}

struct RepoGroup: Identifiable, Sendable {
    let root: URL
    /// Parent path relative to the root; empty for repos directly under the root.
    let path: String
    let repos: [Repo]

    var id: String { root.path + "\n" + path }

    static func grouping(_ repos: [Repo], in root: URL) -> [RepoGroup] {
        let byParent = Dictionary(grouping: repos) { repo -> String in
            let parent = (repo.relativePath as NSString).deletingLastPathComponent
            return parent == "." ? "" : parent
        }
        return byParent
            .map { RepoGroup(root: root, path: $0.key, repos: $0.value) }
            .sorted { lhs, rhs in
                // Root-level repos first, then groups alphabetically.
                if lhs.path.isEmpty != rhs.path.isEmpty { return lhs.path.isEmpty }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
    }
}

/// One line of the branches | worktrees split: a branch and the worktree that has it checked out, if any.
struct CheckoutPair: Identifiable, Sendable {
    let id: String
    let branch: String?
    let worktree: Worktree?
}

extension Repo {
    /// Checked-out branches come first in worktree order, so each sits beside its worktree.
    var pairs: [CheckoutPair] {
        var remaining = branches
        var result = worktrees.map { worktree -> CheckoutPair in
            if let branch = worktree.branch, let index = remaining.firstIndex(of: branch) {
                remaining.remove(at: index)
            }
            return CheckoutPair(id: "wt:" + worktree.path, branch: worktree.branch, worktree: worktree)
        }
        result += remaining.map { CheckoutPair(id: "br:" + $0, branch: $0, worktree: nil) }
        return result
    }

    /// What deleting a row removes: a branch on its own, or a linked worktree together with its
    /// branch. Nil for the main checkout, which can't be removed.
    func rowItem(_ pair: CheckoutPair) -> Selectable? {
        if let worktree = pair.worktree {
            return worktree.isMain ? nil : .worktree(repo: url, path: worktree.path)
        }
        guard let branch = pair.branch, branches.contains(branch) else { return nil }
        return .branch(repo: url, name: branch)
    }

    /// Deletable rows in display order.
    var selectableRows: [Selectable] { pairs.compactMap(rowItem) }

    func matches(_ query: String) -> Bool {
        relativePath.localizedCaseInsensitiveContains(query)
            || branches.contains { $0.localizedCaseInsensitiveContains(query) }
            || worktrees.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
