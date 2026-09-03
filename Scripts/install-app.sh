#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/build/DisplayVolumeKeys.app"
DEST_APP="/Applications/DisplayVolumeKeys.app"

"$ROOT/Scripts/build-app.sh"

osascript -e 'tell application "DisplayVolumeKeys" to quit' 2>/dev/null || true
sleep 0.5
rm -rf "$DEST_APP"
cp -R "$SOURCE_APP" "$DEST_APP"
open "$DEST_APP"
printf 'Installed and launched %s\n' "$DEST_APP"
