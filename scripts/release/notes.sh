#!/bin/bash
# Prints the GitHub release notes for <version>: docs/releases/<version>.md
# followed by the checksums in <dist dir>/SHA256SUMS.txt.
#
#   scripts/release/notes.sh <version> <dist dir>
#
# Fails when docs/releases/<version>.md is missing.
set -euo pipefail

VERSION=${1:?usage: scripts/release/notes.sh <version> <dist dir>}
DIST=${2:?usage: scripts/release/notes.sh <version> <dist dir>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NOTES=$ROOT/docs/releases/$VERSION.md

[ -f "$NOTES" ] || { echo "error: $NOTES is missing" >&2; exit 1; }

cat "$NOTES"
printf '\n## SHA-256 checksums\n\n```\n'
cat "$DIST/SHA256SUMS.txt"
printf '```\n'
