#!/bin/sh
# Prints the CHANGELOG.md entry for a version, without its heading. Fails if there is none.
# Usage: scripts/changelog-section.sh 0.2.0
set -eu
awk -v version="$1" '
    /^## \[/ {
        if (found) exit
        if (index($0, "## [" version "]") == 1) { found = 1; next }
    }
    found { print }
    END { if (!found) exit 1 }
' "$(dirname "$0")/../CHANGELOG.md"
