#!/bin/bash
#
# Installs Text to Speech with one line, on a Mac with Apple Silicon:
#
#   curl -fsSL https://blob.ciromaciel.click/tools/text-to-speech/install.sh | bash
#
# Downloads the latest .dmg (signed with Developer ID and notarized by Apple), copies the
# app to /Applications and opens it. publish-mac.sh uploads this file as install.sh.

set -euo pipefail

BASE="https://blob.ciromaciel.click/tools/text-to-speech"
PAGE="https://ciromaciel.click/tools/text-to-speech"
APP="Text to Speech.app"

WORK="$(mktemp -d)"
cleanup() {
    hdiutil detach "$WORK/volume" -quiet 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

[ "$(uname -s)" = Darwin ] || { echo "Text to Speech is published for the Mac only. More at $PAGE"; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo "Text to Speech needs a Mac with Apple Silicon (M1 or newer)."; exit 1; }

TARGET="/Applications"
[ -w "$TARGET" ] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }

echo "Downloading Text to Speech…"
curl -fL --progress-bar -o "$WORK/app.dmg" "$BASE/latest/Text-to-Speech-macos.dmg"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$WORK/volume" "$WORK/app.dmg"

# An open copy would keep running the old version.
osascript -e 'quit app "Text to Speech"' >/dev/null 2>&1 || true
sleep 1

rm -rf "${TARGET:?}/$APP"
cp -R "$WORK/volume/$APP" "$TARGET/"

echo "Installed in $TARGET. Opening…"
open "$TARGET/$APP"
