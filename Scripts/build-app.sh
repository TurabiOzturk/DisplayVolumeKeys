#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="DisplayVolumeKeys"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
swift build --configuration "$CONFIGURATION"
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Keep a stable designated requirement across local ad-hoc builds so macOS
# does not invalidate Accessibility permission every time the binary changes.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.turabiozturk.DisplayVolumeKeys"' \
  "$APP"
printf 'Built %s\n' "$APP"
