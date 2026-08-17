#!/usr/bin/env bash
#
# Compares captured UI screenshots (Tests/Snapshots/actual) against committed
# fixtures (Tests/Snapshots) with a 0.1% pixel threshold, writing a diff image
# on failure. Exits non-zero if any comparison fails.
#
# Usage:
#   Scripts/compare_snapshots.sh            # compare actual vs fixtures
#   Scripts/record_snapshots.sh             # (separate) promote actual -> fixtures
#
# Requires: swift (to run the comparison), and prior UI-test run that produced
# Tests/Snapshots/actual/*.png.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTUAL="$ROOT/Tests/Snapshots/actual"
FIXTURES="$ROOT/Tests/Snapshots"

if [ ! -d "$ACTUAL" ] || [ -z "$(ls -A "$ACTUAL" 2>/dev/null)" ]; then
  echo "No captured screenshots in $ACTUAL. Run the UI tests first."
  exit 1
fi

failures=0
any_fixture=0
for actual in "$ACTUAL"/*.png; do
  name="$(basename "$actual")"
  fixture="$FIXTURES/$name"
  if [ ! -f "$fixture" ]; then
    echo "· no fixture for $name yet (baseline not recorded; see uploaded artifacts)"
    continue
  fi
  any_fixture=1
  diff_out="$FIXTURES/diff-$name"
  result="$(swift "$ROOT/Scripts/compare_png.swift" "$fixture" "$actual" "$diff_out" 2>/dev/null || true)"
  ratio="${result:-1.0}"
  if awk "BEGIN{exit !($ratio <= 0.001)}"; then
    echo "✔ $name matches (diff $ratio)"
  else
    echo "✘ $name differs by $ratio (see $diff_out)"
    failures=$((failures+1))
  fi
done

if [ "$any_fixture" -eq 0 ]; then
  echo "No committed fixtures yet. Captured screenshots are available as artifacts; run Scripts/record_snapshots.sh to baseline them."
  exit 0
fi

if [ "$failures" -gt 0 ]; then
  echo "Snapshot comparison FAILED: $failures mismatch(es)"
  exit 1
fi
echo "All snapshots match."
