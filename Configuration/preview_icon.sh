#!/bin/bash
#
# Put an image on an app's icon right now, without rebuilding.
#
# For looking at a candidate icon in the Dock and in Finder before deciding.
# It sets Finder's custom icon on the bundle - the app's own icon inside it is
# untouched, so a rebuild puts everything back.
#
# Usage:  ./Configuration/preview_icon.sh <image> [app]
#         ./Configuration/preview_icon.sh ~/Downloads/"Vornyx Notch 2.png"
#         ./Configuration/preview_icon.sh --raw <image> [app]
#         ./Configuration/preview_icon.sh --clear [app]
#
# The image goes through make_icon.swift first: whatever flat backdrop it was
# exported on is trimmed away and it is cut to the rounded-rect shape macOS
# draws app icons in, at its own size. --raw puts the file on as it is, for an
# icon that is already shaped.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DEFAULT="$ROOT/build/VornyxNotch.app"

if [ "${1:-}" = "--clear" ]; then
  APP="${2:-$APP_DEFAULT}"
  /usr/bin/swift - "$APP" <<'SWIFT'
import AppKit
let app = CommandLine.arguments[1]
NSWorkspace.shared.setIcon(nil, forFile: app, options: [])
print("cleared the custom icon on \(app)")
SWIFT
else
  RAW=no
  if [ "${1:-}" = "--raw" ]; then RAW=yes; shift; fi
  IMAGE="${1:?usage: preview_icon.sh [--raw] <image> [app]}"
  APP="${2:-$APP_DEFAULT}"
  [ -e "$IMAGE" ] || { echo "no such image: $IMAGE" >&2; exit 1; }
  [ -d "$APP" ] || { echo "no such app: $APP - build one first" >&2; exit 1; }

  if [ "$RAW" = no ]; then
    SHAPED="$(mktemp -t icon).png"
    /usr/bin/swift "$ROOT/Configuration/make_icon.swift" "$IMAGE" "$SHAPED"
    IMAGE="$SHAPED"
  fi
  /usr/bin/swift - "$IMAGE" "$APP" <<'SWIFT'
import AppKit
let image = CommandLine.arguments[1], app = CommandLine.arguments[2]
guard let icon = NSImage(contentsOfFile: image) else {
    FileHandle.standardError.write(Data("could not read \(image)\n".utf8)); exit(1)
}
guard NSWorkspace.shared.setIcon(icon, forFile: app, options: []) else {
    FileHandle.standardError.write(Data("could not set the icon on \(app)\n".utf8)); exit(1)
}
print("set \(image) on \(app)")
SWIFT
fi

# Finder and the Dock both cache icons; this is what makes it show up at once.
touch "$APP"
killall Finder >/dev/null 2>&1 || true
open -R "$APP"
