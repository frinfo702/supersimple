#!/usr/bin/env bash
#
# Lints and formats Swift sources with the Xcode-bundled swift-format.
# Use `Scripts/format.sh` to auto-fix, or add `--check-only` to verify only.
#
# Usage:
#   Scripts/format.sh            # format in place
#   Scripts/format.sh lint       # check only, useful for CI

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORMAT="$(xcrun --find swift-format)"

# Core package sources + app sources (exclude generated project files).
SOURCES=(
  "$ROOT/Packages/SupersimpleCore/Sources"
  "$ROOT/Packages/SupersimpleCore/Tests"
  "$ROOT/App"
  "$ROOT/supersimpleTests"
  "$ROOT/supersimpleUITests"
)

if [ "${1:-}" = "lint" ]; then
  echo "▸ Checking Swift format"
  "$FORMAT" lint --strict --recursive "${SOURCES[@]}"
else
  echo "▸ Formatting Swift sources"
  "$FORMAT" format --in-place --recursive "${SOURCES[@]}"
fi
echo "▸ Done"