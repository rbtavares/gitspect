# GitSpect

A native macOS app for keeping an eye on all your local git repositories at once: which branches
are behind or ahead, which worktrees exist, and what can be cleaned up.

- **Every repo in one place.** Add the folders where you keep code; GitSpect finds the repositories
  inside and shows them as a tree, grouped by parent folder.
- **Branches and worktrees side by side**, with how many commits each branch has to pull or push.
- **Fetch, pull and push** one repository, or fetch all of them in parallel.
- **Clean up** stale branches and worktrees, one at a time or in bulk. Nothing is forced without
  asking first, and remotes are never touched.
- **See what ran.** The output panel (View → Show Output, ⇧⌘Y) shows every git command and its output.

GitSpect only reads the filesystem to find repositories and runs the `git` already on your Mac for
everything else.

## Requirements

- macOS 14 Sonoma or later.
- Git, from Apple's Command Line Tools: `xcode-select --install`.

## Install

### Download a release

1. Download `GitSpect-<version>.zip` from [Releases](../../releases) and unzip it.
2. Move `GitSpect.app` to `/Applications`.
3. The app isn't notarized by Apple, so the first launch is blocked. Allow it once in
   **System Settings → Privacy & Security → Open Anyway**, or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/GitSpect.app
   ```

### Build from source

Building locally avoids the Gatekeeper prompt. The Command Line Tools are enough; Xcode is optional.

```sh
git clone https://github.com/rbtavares/gitspect.git
cd gitspect
./make-app.sh
open GitSpect.app
```

## Development

| | |
|---|---|
| `./make-app.sh` | Build `GitSpect.app` for this Mac. `ARCHS="arm64 x86_64"` builds a universal app. |
| `swift build` | Compile only. |
| `scripts/make-icon.swift` | Draws the app icons. Delete `Assets/` and run `./make-app.sh` to regenerate them. |

The app version comes from the latest `vX.Y.Z` git tag, and the build number is the commit count.

## Releasing

1. Move the changes under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) into a new
   `## [X.Y.Z] - YYYY-MM-DD` section and commit it.
2. Run `scripts/release.sh X.Y.Z`. It checks you're on a clean `main` with a changelog entry, then
   creates the `vX.Y.Z` tag.
3. Push it: `git push origin main vX.Y.Z`.

GitHub Actions then builds a universal app and publishes it as a release, with that changelog
section as the notes. Tags with a suffix, like `v1.0.0-beta.1`, are published as pre-releases.

## License

[MIT](LICENSE)
