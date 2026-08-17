#!/usr/bin/env bash
#
# Builds supersimple for local use and signs it so macOS won't quarantine-block it.
#
# Local signing only (no Apple Developer team, no notarization). Because the app is
# built on this machine it carries no quarantine xattr, so Gatekeeper leaves it alone.
#
# Usage:
#   Scripts/build.sh            # Debug build, ad-hoc signed, copied to dist/
#   Scripts/build.sh release    # Release build
#
# Requires: xcodegen, Xcode command line tools.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-Debug}"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
SCHEME="supersimple"

echo "▸ Generating Xcode project"
xcodegen generate --spec "$ROOT/project.yml" >/dev/null

echo "▸ Building ($CONFIG)"
xcodebuild build \
  -project "$ROOT/supersimple.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES

APP_PATH="$DERIVED/Build/Products/$CONFIG/supersimple.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app at $APP_PATH" >&2
  exit 1
fi

# Re-sign the app bundle (top level + nested) with an ad-hoc identity so
# hardened runtime + entitlements are intact.
codesign --force --deep --sign - \
  --options runtime \
  --entitlements "$ROOT/App/Resources/Supersimple.entitlements" \
  "$APP_PATH" >/dev/null

mkdir -p "$DIST"
rm -rf "$DIST/supersimple.app"
cp -R "$APP_PATH" "$DIST/supersimple.app"

echo "▸ Signed app at: $DIST/supersimple.app"
echo "  Open it with: open \"$DIST/supersimple.app\""