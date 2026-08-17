#!/usr/bin/env bash
#
# Promotes captured screenshots (Tests/Snapshots/actual) to committed fixtures
# (Tests/Snapshots). Run after intentionally changing the UI to update baselines.
#
# Usage: Scripts/record_snapshots.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTUAL="$ROOT/Tests/Snapshots/actual"
FIXTURES="$ROOT/Tests/Snapshots"

if [ ! -d "$ACTUAL" ] || [ -z "$(ls -A "$ACTUAL" 2>/dev/null)" ]; then
  echo "No captured screenshots in $ACTUAL. Run the UI tests first."
  exit 1
fi

for actual in "$ACTUAL"/*.png; do
  name="$(basename "$actual")"
  cp "$actual" "$FIXTURES/$name"
  echo "recorded $name"
done
rm -f "$FIXTURES"/diff-*.png "$FIXTURES"/actual-*.png
echo "Done. Run Scripts/compare_snapshots.sh to verify."
