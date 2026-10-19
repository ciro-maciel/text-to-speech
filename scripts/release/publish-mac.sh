#!/usr/bin/env bash
#
# publish-mac.sh — puts a built release on blob.ciromaciel.click.
#
#   scripts/release/publish-mac.sh <dir>
#
# <dir> is what scripts/release/build-mac.sh wrote: the notarized .dmg. Run by
# .github/workflows/release.yml, only when the version in package.json is newer than the
# published one.
#
# In the R2 bucket (blob.ciromaciel.click), under tools/text-to-speech/:
#
#   <version>/Text-to-Speech-<version>-macos.dmg   every release, kept, immutable
#   latest/Text-to-Speech-macos.dmg                the fixed link the site points to
#   install.sh                                     the one-line installer
#   latest.json                                    {version, pub_date, url} — last
#
# latest.json goes up last, after everything it names. A version not greater than the
# published one is refused: bump package.json first.
#
# Needs aws (CLI), R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and CLOUDFLARE_ACCOUNT_ID.
# PREFIX overrides the folder, for a dry run (tools/text-to-speech-test).

set -euo pipefail

DIR="$1"
BUCKET="${BUCKET:-ciromaciel-blob}"
PREFIX="${PREFIX:-tools/text-to-speech}"
PUBLIC="https://blob.ciromaciel.click"
BASE="$PUBLIC/$PREFIX"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$HERE/../../package.json" | head -1)"
NAME="Text-to-Speech"

fail() { echo "✗ $1" >&2; exit 1; }

DMG="$DIR/$NAME-$VERSION-macos.dmg"
[ -f "$DMG" ] || fail "missing $DMG"
hdiutil imageinfo "$DMG" >/dev/null 2>&1 || fail "$DMG is not a disk image"

PUBLISHED="$(curl -sf "$BASE/latest.json" | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1 || true)"
if [ -n "$PUBLISHED" ]; then
    HIGHEST="$(printf '%s\n%s\n' "$PUBLISHED" "$VERSION" | sort -V | tail -1)"
    if [ "$VERSION" = "$PUBLISHED" ] || [ "$HIGHEST" != "$VERSION" ]; then
        fail "version $VERSION is not greater than the published $PUBLISHED — bump package.json"
    fi
fi
echo "Publishing Text to Speech $VERSION (published: ${PUBLISHED:-none}) to $BASE"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=auto AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
ENDPOINT="https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com"
put() { # put <file> <key> <content-type> <cache-control>
    aws s3 cp "$1" "s3://$BUCKET/$PREFIX/$2" --endpoint-url "$ENDPOINT" --only-show-errors \
        --content-type "$3" --cache-control "$4"
    echo "  ↑ $PREFIX/$2"
}
KEEP="public, max-age=31536000, immutable"
FRESH="public, max-age=300"

MANIFEST="$(mktemp)"
trap 'rm -f "$MANIFEST"' EXIT
printf '{\n  "version": "%s",\n  "pub_date": "%s",\n  "url": "%s"\n}\n' \
    "$VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BASE/$VERSION/$NAME-$VERSION-macos.dmg" >"$MANIFEST"

bash -n "$HERE/install-mac.sh" || fail "install-mac.sh does not parse"

put "$DMG"                 "$VERSION/$NAME-$VERSION-macos.dmg" application/x-apple-diskimage "$KEEP"
put "$DMG"                 "latest/$NAME-macos.dmg"            application/x-apple-diskimage "$FRESH"
put "$HERE/install-mac.sh" "install.sh"                        "text/plain; charset=utf-8"   "$FRESH"
put "$MANIFEST"            "latest.json"                       application/json              "public, max-age=60"

# What a person gets is what was built: the fixed link serves these bytes.
WANT="$(stat -f %z "$DMG")"
GOT="$(curl -sfI "$BASE/latest/$NAME-macos.dmg?v=$VERSION" | awk 'tolower($1)=="content-length:"{print $2}' | tr -d '\r')"
[ "$GOT" = "$WANT" ] || fail "latest/$NAME-macos.dmg has $GOT bytes online, $WANT here"

echo "✓ Text to Speech $VERSION published — $BASE/latest.json"
echo "  curl -fsSL $BASE/install.sh | bash"
