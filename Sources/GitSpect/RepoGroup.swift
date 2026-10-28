import Foundation

struct RepoGroup: Identifiable, Sendable {
    /// Parent path relative to the scan root; empty for repos directly under the root.
    let id: String
    let repos: [Repo]

    static func grouping(_ repos: [Repo]) -> [RepoGroup] {
        let byParent = Dictionary(grouping: repos) { repo -> String in
            let parent = (repo.relativePath as NSString).deletingLastPathComponent
            return parent == "." ? "" : parent
        }
        return byParent
            .map { RepoGroup(id: $0.key, repos: $0.value) }
            .sorted { lhs, rhs in
                // Root-level repos first, then groups alphabetically.
                if lhs.id.isEmpty != rhs.id.isEmpty { return lhs.id.isEmpty }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
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

    /// Branches not checked out in any worktree, in display order.
    var deletableBranches: [String] {
        pairs.compactMap { $0.worktree == nil ? $0.branch : nil }
    }

    /// Linked worktrees (the main checkout can't be removed), in display order.
    var removableWorktrees: [Worktree] {
        pairs.compactMap { $0.worktree?.isMain == false ? $0.worktree : nil }
    }

    func matches(_ query: String) -> Bool {
        relativePath.localizedCaseInsensitiveContains(query)
            || branches.contains { $0.localizedCaseInsensitiveContains(query) }
            || worktrees.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
