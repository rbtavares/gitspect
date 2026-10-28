#!/bin/sh
# Tags a release after checking it's ready. Pushing the tag makes GitHub build and publish it.
# Usage: scripts/release.sh 0.2.0
set -eu
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh X.Y.Z}
TAG="v$VERSION"

echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' \
    || { echo "error: $VERSION is not a semantic version (X.Y.Z or X.Y.Z-pre)" >&2; exit 1; }
[ "$(git branch --show-current)" = main ] \
    || { echo "error: releases are tagged from main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] \
    || { echo "error: the working tree has uncommitted changes" >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || { echo "error: $TAG already exists" >&2; exit 1; }
scripts/changelog-section.sh "$VERSION" >/dev/null \
    || { echo "error: CHANGELOG.md has no '## [$VERSION]' entry" >&2; exit 1; }

git tag -a "$TAG" -m "GitSpect $VERSION"
echo "Tagged $TAG. Publish it with:"
echo "  git push origin main $TAG"
