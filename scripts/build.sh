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

# Phonon's `ptts` command (Gradium, MIT or Apache-2.0), the voice that runs on the Mac: the
# official release archive, pinned by version and SHA-256, cached in .build. It goes next to the
# app's executable, where Bundle.main finds it, after the strip above: a third party's binary
# is shipped as released.
PTTS_VERSION="0.7.0"
PTTS_SHA256="14b41430c53a08c1666518210f066a5dc3537fc1d191a0d284f6db1451fd2659"
PTTS_ARCHIVE="$ROOT/.build/ptts-$PTTS_VERSION-aarch64-apple-darwin.tar.gz"
if [ ! -f "$PTTS_ARCHIVE" ] || ! echo "$PTTS_SHA256  $PTTS_ARCHIVE" | shasum -a 256 -c - >/dev/null 2>&1; then
    mkdir -p "$ROOT/.build"
    curl -fsSL -o "$PTTS_ARCHIVE" \
        "https://github.com/gradium-ai/xn-ptts/releases/download/v$PTTS_VERSION/ptts-$PTTS_VERSION-aarch64-apple-darwin.tar.gz"
fi
echo "$PTTS_SHA256  $PTTS_ARCHIVE" | shasum -a 256 -c - >/dev/null || { echo "ptts archive checksum mismatch" >&2; exit 1; }
PTTS_DIR="$(mktemp -d)"
tar -xzf "$PTTS_ARCHIVE" -C "$PTTS_DIR"
cp "$PTTS_DIR/ptts-$PTTS_VERSION-aarch64-apple-darwin/ptts" "$APP/Contents/MacOS/ptts"
mkdir -p "$RESOURCES/ptts"
cp "$PTTS_DIR/ptts-$PTTS_VERSION-aarch64-apple-darwin/LICENSE-MIT" "$PTTS_DIR/ptts-$PTTS_VERSION-aarch64-apple-darwin/LICENSE-APACHE" "$RESOURCES/ptts/"
rm -rf "$PTTS_DIR"

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1 || true)"
SIGN="${DEVELOPER_ID:--}"
[ "$SIGN" = "-" ] && echo "warning: no Developer ID: signing ad hoc, macOS will ask for the permissions again" >&2
TIMESTAMP=(); if [ "$SIGN" != "-" ]; then TIMESTAMP=(--timestamp); fi
# The nested command first, with the same identity and hardened runtime: notarization checks it.
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --identifier click.ciromaciel.text-to-speech.ptts \
    --sign "$SIGN" "$APP/Contents/MacOS/ptts"
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --identifier click.ciromaciel.text-to-speech \
    --entitlements "$ROOT/scripts/TextToSpeech.entitlements" --sign "$SIGN" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed with: $([ "$SIGN" = "-" ] && echo "ad hoc" || echo "$SIGN")"
echo "Text to Speech $VERSION → $APP"
