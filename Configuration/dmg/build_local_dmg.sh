#!/usr/bin/env bash
set -euo pipefail

# Builds VornyxNotch.app in Release on this Mac and packs it into a DMG.
#
# No developer account needed: the app is signed ad-hoc, the same as a Debug
# build from Xcode. CI does the signed build (build_reusable.yml); this is for
# making an installer locally.
#
# Usage:  ./Configuration/dmg/build_local_dmg.sh [version]
# Output: build/VornyxNotch-<version>.dmg

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_NAME="VornyxNotch"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$PROJECT_NAME.xcarchive"
APP="$BUILD_DIR/$PROJECT_NAME.app"
VENV="$BUILD_DIR/dmg-venv"
LOG="$BUILD_DIR/archive.log"

die() {
  echo "Error: $*" >&2
  exit 1
}

# xcodebuild needs full Xcode, even when xcode-select points at the Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  xcodebuild -version >/dev/null 2>&1 || die "Xcode not found. Install it, or run: sudo xcode-select -s /path/to/Xcode.app"
fi

VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$ROOT/$PROJECT_NAME.xcodeproj/project.pbxproj" | head -1)}"
DMG="$BUILD_DIR/$PROJECT_NAME-$VERSION.dmg"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE" "$APP"

echo "==> Archiving $PROJECT_NAME $VERSION (Release, universal, ad-hoc signed)"
# Hardened runtime off: it turns on library validation, which only lets a
# process load frameworks signed by its own Team ID - and ad-hoc signatures
# have none, so the app died at launch on "Library not loaded:
# MediaRemoteAdapter.framework". Debug builds never hit it, because Xcode's
# get-task-allow exempts them. The hardened runtime is only needed for
# notarization, which an ad-hoc build cannot have anyway.
if ! xcodebuild archive \
  -project "$ROOT/$PROJECT_NAME.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -20 >&2 || true
  die "archive failed - full log: $LOG"
fi

ditto "$ARCHIVE/Products/Applications/$PROJECT_NAME.app" "$APP"
codesign --verify --deep --strict "$APP" || die "the built app's signature does not verify"
echo "==> App: $APP"

# A plain DMG - the app and a link to Applications - for when dmgbuild cannot
# be installed.
make_plain_dmg() {
  local staging="$BUILD_DIR/dmg-staging"
  rm -rf "$staging"
  mkdir -p "$staging"
  ditto "$APP" "$staging/$PROJECT_NAME.app"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname "$PROJECT_NAME $VERSION" -srcfolder "$staging" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$staging"
}

echo "==> Packing $DMG"
rm -f "$DMG"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV" \
    && "$VENV/bin/python" -m pip install --quiet --upgrade pip \
    && "$VENV/bin/python" -m pip install --quiet --require-hashes -r "$ROOT/Configuration/dmg/requirements.txt" \
    || { rm -rf "$VENV"; echo "dmgbuild could not be installed; making a plain DMG instead."; }
fi

if [ -x "$VENV/bin/dmgbuild" ]; then
  PATH="$VENV/bin:$PATH" "$ROOT/Configuration/dmg/create_dmg.sh" "$APP" "$DMG" "$PROJECT_NAME $VERSION"
else
  make_plain_dmg
fi

echo
echo "Done: $DMG"
echo "The app is signed ad-hoc, so on another Mac the first launch needs"
echo "System Settings > Privacy & Security > Open Anyway (or: xattr -dr com.apple.quarantine /Applications/$PROJECT_NAME.app)."
