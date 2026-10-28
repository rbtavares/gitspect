# Changelog

All notable changes to GitSpect are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

Each release's section becomes its GitHub release notes, so add an entry before tagging.

## [Unreleased]

## [0.1.0] - 2026-10-28

First release.

### Added

- Scan one or more folders for git repositories, shown in the sidebar as a tree grouped by parent folder.
- Branches and worktrees side by side for each repository, with commits to pull and push.
- Repositories without a remote are marked as local only; the others link to their remote's web page.
- Click a branch to open its commit graph beside the repository, together with its upstream's history.
- Click a commit in the graph to see its full message, author, signature, parents and changed files, with each file's diff a click away.
- Fetch one repository or all of them in parallel, fast-forward pull, and push.
- Pull All fast-forwards every branch that is behind its upstream, across all repositories.
- Delete branches and remove worktrees, one at a time or in bulk, with a confirmation before anything is forced.
- Output panel with the live output of every git command GitSpect runs.
- Settings for scanned folders, light/dark/system theme and the app icon.
