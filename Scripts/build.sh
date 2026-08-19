#!/usr/bin/env bash
#
# Builds supersimple for local use and signs it so macOS won't quarantine-block it.
#
# Local signing only (no Apple Developer team, no notarization). Because the app is
# built on this machine it carries no quarantine xattr, so Gatekeeper leaves it alone.
#
# Usage:
#   Scripts/build.sh            # Release build, ad-hoc signed, copied to dist/
#   Scripts/build.sh debug      # Debug build (disables the debug dylib)
#
# NOTE: Use Release for the local app. Debug configs normally inject a
# `supersimple.debug.dylib` (for dynamic testability); that dylib often fails at
# launch after an ad-hoc re-sign with a dyld "different Team IDs" error. We
# explicitly disable it so both configs produce a launchable .app.
#
# Requires: xcodegen, Xcode command line tools.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-Release}"
if [ "$CONFIG" = "release" ]; then CONFIG="Release"; fi
if [ "$CONFIG" = "debug" ]; then CONFIG="Debug"; fi
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
SCHEME="supersimple"

echo "▸ Generating Xcode project"
xcodegen generate --spec "$ROOT/project.yml" >/dev/null

VERSION_SETTINGS=()
if [ -n "${MARKETING_VERSION:-}" ]; then
  VERSION_SETTINGS+=("MARKETING_VERSION=${MARKETING_VERSION}")
fi
if [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
  VERSION_SETTINGS+=("CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}")
fi

echo "▸ Building ($CONFIG)"
XCODEBUILD_ARGS=(
  xcodebuild build
  -project "$ROOT/supersimple.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -derivedDataPath "$DERIVED"
  CODE_SIGN_IDENTITY="-"
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM=""
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGNING_ALLOWED=YES
  ENABLE_DEBUG_DYLIB=NO
)
if [ ${#VERSION_SETTINGS[@]} -gt 0 ]; then
  XCODEBUILD_ARGS+=("${VERSION_SETTINGS[@]}")
fi
"${XCODEBUILD_ARGS[@]}"

APP_PATH="$DERIVED/Build/Products/$CONFIG/supersimple.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app at $APP_PATH" >&2
  exit 1
fi

# Sign the nested updater first *without* the app entitlements, then the
# outer app. `--deep` on the outer bundle would apply the main app's
# entitlements to the helper.
HELPER_PATH="$APP_PATH/Contents/PlugIns/SupersimpleUpdater.app"
if [ -d "$HELPER_PATH" ]; then
  codesign --force --sign - --options runtime "$HELPER_PATH" >/dev/null
fi

codesign --force --sign - \
  --options runtime \
  --entitlements "$ROOT/App/Resources/Supersimple.entitlements" \
  "$APP_PATH" >/dev/null

mkdir -p "$DIST"
rm -rf "$DIST/supersimple.app"
cp -R "$APP_PATH" "$DIST/supersimple.app"

echo "▸ Signed app at: $DIST/supersimple.app"
echo "  Open it with: open \"$DIST/supersimple.app\""