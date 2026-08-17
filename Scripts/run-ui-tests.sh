#!/usr/bin/env bash
#
# Builds and runs the macOS UI tests, re-signing the UI-test runner so it loads
# under ad-hoc (no developer team) signing.
#
# Usage:
#   Scripts/run-ui-tests.sh            # run UI tests (captures screenshots)
#   Scripts/run-ui-tests.sh compare   # also compare snapshots against fixtures
#
# Requires: xcodegen, Xcode command line tools.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/UITests"
SCHEME="supersimple"

xcodegen generate --spec "$ROOT/project.yml" >/dev/null

echo "▸ Building for testing"
xcodebuild build-for-testing \
  -project "$ROOT/supersimple.xcodeproj" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED"

RUNNER="$DERIVED/Build/Products/Debug/supersimpleUITests-Runner.app"
echo "▸ Re-signing UI test runner (ad-hoc)"
codesign --force --sign - --timestamp=none "$RUNNER/Contents/PlugIns/supersimpleUITests.xctest" >/dev/null
codesign --force --sign - --timestamp=none "$RUNNER" >/dev/null

echo "▸ Running UI tests"
xcodebuild test-without-building \
  -project "$ROOT/supersimple.xcodeproj" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:supersimpleUITests

if [ "${1:-}" = "compare" ]; then
  echo "▸ Comparing snapshots"
  "$ROOT/Scripts/compare_snapshots.sh"
fi
