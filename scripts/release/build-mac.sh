#!/usr/bin/env bash
#
# build-mac.sh — the official macOS build: signed with Developer ID, hardened runtime,
# notarized by Apple and stapled.
#
#   scripts/release/build-mac.sh <out-dir>
#
# Used by .github/workflows/release.yml, and the same on a Mac with the certificate:
#
#   1. `tauri build` signs the app with the Developer ID identity and the hardened runtime
#      (entitlements.mac.plist), has Apple notarize it and staples the ticket, then packs
#      the .dmg;
#   2. the .dmg itself is signed, notarized and stapled, so a browser download opens with
#      no warning, even offline.
#
# Needs, in the environment:
#   APPLE_API_KEY, APPLE_API_ISSUER, APPLE_API_KEY_PATH   App Store Connect API key (.p8)
#   APPLE_SIGNING_IDENTITY       optional: found in the keychain when unset
#
# Writes <out-dir>/Text-to-Speech-<version>-macos.dmg

set -euo pipefail

OUT="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() { echo "✗ $1" >&2; exit 1; }
for v in APPLE_API_KEY APPLE_API_ISSUER APPLE_API_KEY_PATH; do
    [ -n "${!v:-}" ] || fail "$v is not set"
done
[ -f "$APPLE_API_KEY_PATH" ] || fail "no API key at APPLE_API_KEY_PATH"

if [ -z "${APPLE_SIGNING_IDENTITY:-}" ]; then
    APPLE_SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
    [ -n "$APPLE_SIGNING_IDENTITY" ] || fail "no Developer ID Application identity in the keychain"
fi
export APPLE_SIGNING_IDENTITY

VERSION="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' package.json | head -1)"
NAME="Text-to-Speech"
# src-tauri/.cargo/config.toml builds in a short directory outside the clone.
BUNDLE="/tmp/tts-target/release/bundle"

bun install --frozen-lockfile
rm -rf "$BUNDLE/macos" "$BUNDLE/dmg"
bunx tauri build --bundles app,dmg

APP="$BUNDLE/macos/Text to Speech.app"
DMG_BUILT="$(ls "$BUNDLE"/dmg/*.dmg | head -1)"
[ -d "$APP" ] && [ -f "$DMG_BUILT" ] || fail "tauri build left no app or .dmg"

# The app: Developer ID, hardened runtime, ticket stapled.
# (Read into a variable first: grep -q stops reading early, and under pipefail the
# writer's SIGPIPE would count as a failure.)
codesign --verify --deep --strict "$APP" || fail "the app signature does not verify"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$SIGNATURE" || fail "the app is not signed with Developer ID"
grep -q "flags=.*runtime" <<<"$SIGNATURE" || fail "the app has no hardened runtime"
# Tauri staples right after Apple accepts, and the ticket can take a minute to be served:
# on 19/10/2026 the 0.4.0 release stopped here with the notarization accepted. Staple again
# before giving up.
for try in 1 2 3 4 5; do
    xcrun stapler validate "$APP" >/dev/null 2>&1 && break
    [ "$try" = 5 ] && fail "the app has no stapled ticket"
    sleep 30
    xcrun stapler staple "$APP" || true
done

mkdir -p "$OUT"
DMG="$OUT/$NAME-$VERSION-macos.dmg"
cp "$DMG_BUILT" "$DMG"
codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$DMG"
NOTARY="$(mktemp)"
xcrun notarytool submit "$DMG" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER" \
    --wait --timeout 30m | tee "$NOTARY"
grep -q "status: Accepted" "$NOTARY" || fail "Apple did not accept the .dmg"
rm -f "$NOTARY"
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"

echo "✓ Text to Speech $VERSION → $OUT"
ls -1 "$OUT"
