#!/bin/zsh
# End-to-end check of a built app on this Mac:
#   scripts/check.sh [path/to/Text to Speech.app]      (default: dist/)
#
# 1. The reading logic (Reading.swift) against the answers of the 0.x reading.js, frozen in
#    scripts/fixtures: how a text becomes parts, when each word is spoken, the clock.
# 2. A copy of the app under its own identifier (…text-to-speech.check), in a temporary data
#    folder, reads a short text through the real server, driven through TTS_E2E_TRIGGER: the
#    voice starts, words light up, Space pauses, + speeds up, → moves on, Esc stops, and a reading
#    ends on its own. It plays aloud for a few seconds.
set -u
ROOT="${0:A:h:h}"
SOURCE="${1:-$ROOT/dist/Text to Speech.app}"
ID="click.ciromaciel.text-to-speech.check"
WORK="$(mktemp -d)"
APP="$WORK/check.app"
fails=0
ok() { print "  ok   $1"; }
bad() { print "  FAIL $1"; fails=$((fails + 1)); }
[ -d "$SOURCE" ] || { print "no app at $SOURCE: run scripts/build.sh"; exit 1; }

print "Text to Speech — end-to-end check"
"$SOURCE/Contents/MacOS/text-to-speech" --reading "$ROOT/scripts/fixtures/reading-cases.json" > "$WORK/reading.json"
python3 -I - "$WORK/reading.json" "$ROOT/scripts/fixtures/reading-expected.json" <<'PY' && ok "reading logic matches the 0.x answers" || bad "reading logic differs"
import json, sys
got, want = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
diffs = [i for i, (g, w) in enumerate(zip(got, want))
         if g["parts"] != w["parts"] or g["clock"] != w["clock"] or len(g["times"]) != len(w["times"])
         or any(a["text"] != b["text"] or abs(a["start"] - b["start"]) > 1e-9 for a, b in zip(g["times"], w["times"]))]
print(f"       {len(want)} cases, {len(diffs)} differences")
sys.exit(1 if diffs or len(got) != len(want) else 0)
PY

cp -R "$SOURCE" "$APP"
plutil -replace CFBundleIdentifier -string "$ID" "$APP/Contents/Info.plist"
codesign --force --sign - --identifier "$ID" "$APP" 2>/dev/null
defaults delete "$ID" >/dev/null 2>&1
defaults write "$ID" importedTauriSettings -bool true
: > "$WORK/trigger"
TTS_DATA_DIR="$WORK/data" TTS_E2E_TRIGGER="$WORK/trigger" "$APP/Contents/MacOS/text-to-speech" > "$WORK/app.log" 2>&1 &
PID=$!
# Whatever happens below, the copy goes: a copy left running makes the next one quit.
trap 'kill $PID 2>/dev/null; defaults delete "$ID" >/dev/null 2>&1; rm -rf "$WORK"' EXIT
sleep 2
send() { print "$1" > "$WORK/trigger"; sleep 0.3; }
state() { send state; grep -o '\[e2e\] state.*' "$WORK/app.log" | tail -1; }
field() { state | sed -n "s/.* $1=\([^ ]*\).*/\1/p"; }

send "speak Primeira frase do teste. Segunda frase, um pouco mais longa, para ver o destaque das palavras.\nUm segundo parágrafo, com mais algumas palavras para formar outro trecho. E mais uma frase aqui.\nO terceiro parágrafo também tem duas frases. Esta é a última delas, para fechar o texto do teste."
for _ in {1..80}; do [ "$(field ready)" = yes ] && break; sleep 0.25; done
[ "$(field ready)" = yes ] && ok "the voice starts in $(field firstSoundMs) ms" || bad "no audio from the server: $(field hint)"
sleep 1.5; a=$(field spoken); sleep 1; b=$(field spoken)
[ "$b" -gt "$a" ] 2>/dev/null && ok "words light up as they are spoken ($a → $b)" || bad "highlight not moving ($a → $b)"
print "  memory while reading: $(footprint -p $PID 2>/dev/null | sed -n 's/.*Footprint: \([0-9.]* [MKG]B\).*/\1/p' | head -1)"
send space; [ "$(field paused)" = yes ] && ok "Space pauses" || bad "Space did not pause"
a=$(field spoken); sleep 1; b=$(field spoken); [ "$a" = "$b" ] && ok "paused, the highlight holds" || bad "kept moving while paused"
send space; send faster; [ "$(field speed)" = 1.25 ] && ok "+ speeds up" || bad "speed is $(field speed)"
send slower
i1=$(field index); send right; sleep 0.5; i2=$(field index)
[ "$i2" -gt "$i1" ] 2>/dev/null && ok "→ goes to the next part ($i1 → $i2)" || bad "→ did nothing ($i1 → $i2)"
send escape; [ "$(field live)" = no ] && ok "Esc stops" || bad "Esc did not stop"
send "speak Leitura até o fim."
for _ in {1..80}; do [ "$(field live)" = no ] && break; sleep 0.25; done
[ "$(field live)" = no ] && ok "a reading ends and the player closes" || bad "the reading did not end"

print "$([ $fails = 0 ] && echo "Check passed" || echo "$fails failure(s)")"
exit $fails
