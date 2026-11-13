# Changelog

All notable changes to GitSpect are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

Each release's section becomes its GitHub release notes, so add an entry before tagging.

## [Unreleased]

## [0.2.0] - 2026-11-13

### Changed

- GitSpect has its own interface instead of the stock macOS controls: its own top bar level with the window buttons, sidebar, buttons, filter field, dialogs and settings page, in a light and a dark palette that both honour Increase Contrast.
- Text is set in Geist, and everything git says (branches, hashes, paths, command output) in Geist Mono. Both fonts ship inside the app.
- Rows are taller and every button is at least 24 points, so they're easier to hit; the alternating row stripes are gone in favour of a highlight under the pointer.
- The sidebar can be resized and hidden (View → Hide Sidebar, ⌃⌘S), and shows how many repositories it found. Repositories without a remote are marked "local".
- The commit graph leaves out the author when the pane is narrow, so the subject stays readable; the author is still in the commit details.
- Settings is one page: scanned folders, then appearance.

- Right-clicking one of several selected rows offers to delete all of them; on a row outside the selection it still acts on that row alone.
- Add Folders (⇧⌘O) and Rescan Folders (⌘R) are in the File menu, so they work with the sidebar hidden.
- A detached worktree's commit is in its tag's tooltip rather than on the row.
- In a small window the commit graph takes the whole pane instead of squeezing the branch list; closing it brings the list back.

### Added

- ⌘F puts the cursor in the filter field; Escape clears it.

### Fixed

- The output panel no longer rebuilds and jumps as output streams in.

## [0.1.2] - 2026-10-28

### Changed

- The app icon is now the blue style everywhere, and the icon choice in Settings is gone: macOS only showed a chosen icon reliably while GitSpect was running.

## [0.1.1] - 2026-10-28

First published release: 0.1.0 was tagged, but its build failed. Everything 0.1.0 lists is here.

### Fixed

- Builds with Xcode 16 (Swift 6.1) again, which the release build uses.

### Included

- Scan one or more folders for git repositories, shown in the sidebar as a tree grouped by parent folder.
- An overview of every repository when nothing is selected: how many there are, commits to pull and push, and which are local only.
- Select a folder to see what's in it; remove added folders from GitSpect, or move nested folders to the Trash.
- Branches and worktrees side by side for each repository, with commits to pull and push.
- Repositories without a remote are marked as local only; the others link to their remote's web page.
- Click a branch to open its commit graph beside the repository, together with its upstream's history.
- Click a commit in the graph to see its full message, author, signature, parents and changed files, with each file's diff a click away.
- Fetch one repository or all of them in parallel, fast-forward pull, and push.
- Pull All fast-forwards every branch that is behind its upstream, across all repositories; a repository's pull and push counts in the sidebar do the same for that repository.
- Select rows like a list and delete their branches, their worktrees, or both, with a confirmation before anything is forced.
- Output panel with the live output of every git command GitSpect runs.
- Settings for scanned folders, light/dark/system theme and the app icon.

## [0.1.0] - 2026-10-28

First release.

### Added

- Scan one or more folders for git repositories, shown in the sidebar as a tree grouped by parent folder.
- An overview of every repository when nothing is selected: how many there are, commits to pull and push, and which are local only.
- Select a folder to see what's in it; remove added folders from GitSpect, or move nested folders to the Trash.
- Branches and worktrees side by side for each repository, with commits to pull and push.
- Repositories without a remote are marked as local only; the others link to their remote's web page.
- Click a branch to open its commit graph beside the repository, together with its upstream's history.
- Click a commit in the graph to see its full message, author, signature, parents and changed files, with each file's diff a click away.
- Fetch one repository or all of them in parallel, fast-forward pull, and push.
- Pull All fast-forwards every branch that is behind its upstream, across all repositories; a repository's pull and push counts in the sidebar do the same for that repository.
- Select rows like a list and delete their branches, their worktrees, or both, with a confirmation before anything is forced.
- Output panel with the live output of every git command GitSpect runs.
- Settings for scanned folders, light/dark/system theme and the app icon.
