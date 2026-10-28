#!/bin/bash
# Builds "dist/Text to Speech.app": SwiftPM for the binary, then the
# bundle around it. Command Line Tools are enough.
#   scripts/build.sh
#
# Signed with the Developer ID when the keychain has it (the official build, hardened runtime),
# else ad hoc: macOS ties Accessibility to the signature, so the official identity keeps it from
# one version to the next and from the Tauri build (0.x) to this one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
APP="$ROOT/dist/Text to Speech.app"
RESOURCES="$APP/Contents/Resources"

SWIFT=(swift build --package-path "$ROOT" -c release --arch arm64)
# A failed build stops here: never wrap an older binary left in .build.
LOG="$(mktemp)"
if ! "${SWIFT[@]}" >"$LOG" 2>&1; then
    grep -vE '^\[ ?[0-9]+ ?/ ?[0-9]+ ?\]' "$LOG" >&2
    rm -f "$LOG"
    exit 1
fi
rm -f "$LOG"
BIN="$("${SWIFT[@]}" --show-bin-path)/TextToSpeech"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RESOURCES"
# The executable keeps the 0.x name, which the 0.x login item points to.
cp "$BIN" "$APP/Contents/MacOS/text-to-speech"
# The symbols out of the shipped binary: half its size. Crash reports still locate each frame.
strip -rSTx "$APP"/Contents/MacOS/*
# Every build carries VERSION; the window's footer reads it back.
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/Fonts" "$ROOT/Resources/Icons" \
    "$ROOT/Resources/en.lproj" "$ROOT/Resources/pt-BR.lproj" "$RESOURCES/"

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1 || true)"
SIGN="${DEVELOPER_ID:--}"
[ "$SIGN" = "-" ] && echo "warning: no Developer ID: signing ad hoc, macOS will ask for the permissions again" >&2
TIMESTAMP=(); if [ "$SIGN" != "-" ]; then TIMESTAMP=(--timestamp); fi
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --identifier click.ciromaciel.text-to-speech \
    --entitlements "$ROOT/scripts/TextToSpeech.entitlements" --sign "$SIGN" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed with: $([ "$SIGN" = "-" ] && echo "ad hoc" || echo "$SIGN")"
echo "Text to Speech $VERSION → $APP"
