#!/bin/zsh
# End-to-end check of a built app on this Mac:
#   scripts/check.sh [path/to/Text to Speech.app]      (default: dist/)
#
# 1. The reading logic (Reading.swift) against the answers of the 0.x reading.js, frozen in
#    scripts/fixtures: how a text becomes parts, when each word is spoken, the clock.
# 2. For each voice with a credential (Davi through Phonon: TTS_HF_TOKEN, else the Hugging Face
#    token saved on this Mac; Rafael through Fish: TTS_FISH_KEY, else FISH_API_KEY in
#    ~/.ciromacielos/.env), a copy of the app under its own identifier (…text-to-speech.check), in
#    a temporary data folder, reads a short text, driven through TTS_E2E_TRIGGER: the voice
#    starts, words light up, Space pauses, + speeds up, → moves on, Esc stops, and a reading ends
#    on its own. It plays aloud for a few seconds. Then, with no key, a reading must not start,
#    and ⌘V pastes a key into the Voice pane (the clipboard is put back after).
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

"$SOURCE/Contents/MacOS/text-to-speech" --speakable "$ROOT/scripts/fixtures/speakable-input.md" > "$WORK/speakable.txt"
cmp -s "$WORK/speakable.txt" "$ROOT/scripts/fixtures/speakable-expected.txt" \
    && ok "Markdown and HTML marks are not read (headings, bold, lists, tables, links, comments)" \
    || { bad "the text to read differs from scripts/fixtures/speakable-expected.txt"; diff "$WORK/speakable.txt" "$ROOT/scripts/fixtures/speakable-expected.txt" | head -8; }

# How each voice cuts a spoken summary (an agent's `<!-- voice: -->`, three sentences): Davi says it
# in one call, as the CCM Stack voice does; Rafael starts with a short part.
davi=$("$SOURCE/Contents/MacOS/text-to-speech" --parts phonon "$ROOT/scripts/fixtures/voice-summary.md" | grep -c .)
rafael=$("$SOURCE/Contents/MacOS/text-to-speech" --parts fish "$ROOT/scripts/fixtures/voice-summary.md" | grep -c .)
[ "$davi" = 1 ] && [ "$rafael" -gt 1 ] \
    && ok "a spoken summary is one Davi call (as in the CCM Stack), $rafael Rafael parts" \
    || bad "a spoken summary became $davi Davi part(s) and $rafael Rafael part(s)"

# Phonon's part silence: 0.5 s quiet, 0.5 s tone (-30 LUFS, quieter than raw Phonon), 0.8 s
# quiet → about 40 ms before and 250 ms after.
python3 -I - "$WORK/silence.wav" <<'PY2'
import sys, wave, math, array
sr = 24000
a = array.array('h', [0] * int(0.5 * sr) + [int(2000 * math.sin(i / 8)) for i in range(int(0.5 * sr))] + [0] * int(0.8 * sr))
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(a.tobytes()); w.close()
PY2
"$SOURCE/Contents/MacOS/text-to-speech" --trim "$WORK/silence.wav" "$WORK/trimmed.wav"
python3 -I - "$WORK/trimmed.wav" <<'PY2' && ok "silence at the ends of a Phonon part is trimmed (no long pause between parts)" || bad "the part's silence was not trimmed"
import sys, wave, array
w = wave.open(sys.argv[1]); sr = w.getframerate(); a = array.array('h', w.readframes(w.getnframes()))
i = [k for k, x in enumerate(a) if abs(x) > 600]
lead, tail = i[0] / sr, (len(a) - 1 - i[-1]) / sr
print(f"       before the voice {lead*1000:.0f} ms, after {tail*1000:.0f} ms")
sys.exit(0 if 0.02 <= lead <= 0.06 and 0.2 <= tail <= 0.3 else 1)
PY2

# The same loudness as the CCM Stack voice (ffmpeg loudnorm, -16 LUFS, peaks under -1.5 dB).
if command -v ffmpeg >/dev/null; then
    m=$(ffmpeg -hide_banner -i "$WORK/trimmed.wav" -af loudnorm=I=-16:TP=-1.5:print_format=summary -f null - 2>&1)
    lufs=$(echo "$m" | awk '/Input Integrated/{print $3}'); peak=$(echo "$m" | awk '/Input True Peak/{print $4}')
    awk -v l="$lufs" -v p="$peak" 'BEGIN { exit !(l >= -17 && l <= -15 && p <= -1) }' \
        && ok "a Phonon part plays at the CCM Stack loudness ($lufs LUFS, peak $peak dB)" \
        || bad "a Phonon part is at $lufs LUFS, peak $peak dB (want -16, under -1.5)"
fi

# The same Phonon command as the CCM Stack voice: 0.7.0 gave a different take on every call.
v=$("$SOURCE/Contents/MacOS/ptts" --version 2>/dev/null)
[ "$v" = "ptts 0.6.0" ] && ok "Phonon runs ptts 0.6.0, the one the CCM Stack voice runs" || bad "the app ships $v, not ptts 0.6.0"

cp -R "$SOURCE" "$APP"
plutil -replace CFBundleIdentifier -string "$ID" "$APP/Contents/Info.plist"
codesign --force --sign - --identifier "$ID" "$APP" 2>/dev/null
codesign --force --sign - --identifier "$ID.ptts" "$APP/Contents/MacOS/ptts" 2>/dev/null
codesign --force --sign - --identifier "$ID" "$APP" 2>/dev/null
# Never `kill 0`: with no copy running yet that would signal this whole process group.
PID=""
stop_copy() { if [ -n "$PID" ]; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""; fi }
trap 'stop_copy; defaults delete "$ID" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

# launch <engine> [VAR=value ...]: a fresh copy with its own data folder; a copy left running
# makes the next one quit, so the one before goes first.
launch() {
    local engine=$1; shift
    stop_copy
    defaults delete "$ID" >/dev/null 2>&1
    defaults write "$ID" importedTauriSettings -bool true
    rm -rf "$WORK/data-$engine"; : > "$WORK/trigger"; : > "$WORK/app.log"
    env TTS_ENGINE=$engine TTS_DATA_DIR="$WORK/data-$engine" TTS_E2E_TRIGGER="$WORK/trigger" "$@" \
        "$APP/Contents/MacOS/text-to-speech" > "$WORK/app.log" 2>&1 &
    PID=$!
    sleep 2
}
send() { print "$1" > "$WORK/trigger"; sleep 0.3; }
state() { send state; grep -o '\[e2e\] state.*' "$WORK/app.log" | tail -1; }
field() { state | sed -n "s/.* $1=\([^ ]*\).*/\1/p"; }

# read_through <name>: the whole reading scenario on the copy that is running.
read_through() {
    local name=$1
    # Over 150 words, so Davi too has a next part for the arrow.
    send "speak Primeira frase do teste. Segunda frase, um pouco mais longa, para ver o destaque das palavras.\nUm segundo parágrafo, com mais algumas palavras para formar outro trecho. E mais uma frase aqui.\nO terceiro parágrafo também tem duas frases. Esta é a última delas, para fechar o texto do teste.\nEste parágrafo existe para que o texto passe de cento e cinquenta palavras, o tamanho de uma chamada do Davi, e a seta tenha um trecho seguinte para onde ir. Ele fala de coisas simples, como o tempo, o café da manhã e o caminho até o trabalho, sem nenhum símbolo que precise de limpeza.\nEste parágrafo existe para que o texto passe de cento e cinquenta palavras, o tamanho de uma chamada do Davi, e a seta tenha um trecho seguinte para onde ir. Ele fala de coisas simples, como o tempo, o café da manhã e o caminho até o trabalho, sem nenhum símbolo que precise de limpeza.\nEste parágrafo existe para que o texto passe de cento e cinquenta palavras, o tamanho de uma chamada do Davi, e a seta tenha um trecho seguinte para onde ir. Ele fala de coisas simples, como o tempo, o café da manhã e o caminho até o trabalho, sem nenhum símbolo que precise de limpeza."
    # The first Phonon reading downloads the voice once (58 MB): up to a minute.
    for _ in {1..240}; do [ "$(field ready)" = yes ] && break; sleep 0.25; done
    [ "$(field ready)" = yes ] && ok "$name: the voice starts in $(field firstSoundMs) ms" || { bad "$name: no audio: $(field hint)"; return; }
    sleep 1.5; a=$(field spoken); sleep 1; b=$(field spoken)
    [ "$b" -gt "$a" ] 2>/dev/null && ok "$name: words light up as they are spoken ($a → $b)" || bad "$name: highlight not moving ($a → $b)"
    print "  $name: memory of the app while reading: $(footprint -p $PID 2>/dev/null | sed -n 's/.*Footprint: \([0-9.]* [MKG]B\).*/\1/p' | head -1)"
    send space; [ "$(field paused)" = yes ] && ok "$name: Space pauses" || bad "$name: Space did not pause"
    a=$(field spoken); sleep 1; b=$(field spoken); [ "$a" = "$b" ] && ok "$name: paused, the highlight holds" || bad "$name: kept moving while paused"
    send space; send faster; [ "$(field speed)" = 1.25 ] && ok "$name: + speeds up" || bad "$name: speed is $(field speed)"
    send slower
    i1=$(field index); send right; sleep 0.5; i2=$(field index)
    [ "$i2" -gt "$i1" ] 2>/dev/null && ok "$name: → goes to the next part ($i1 → $i2)" || bad "$name: → did nothing ($i1 → $i2)"
    send escape; [ "$(field live)" = no ] && ok "$name: Esc stops" || bad "$name: Esc did not stop"
    send "speak Leitura até o fim."
    for _ in {1..80}; do [ "$(field live)" = no ] && break; sleep 0.25; done
    [ "$(field live)" = no ] && ok "$name: a reading ends and the player closes" || bad "$name: the reading did not end"
}

HF_TOKEN_VALUE="${TTS_HF_TOKEN:-$(cat ~/.cache/huggingface/token 2>/dev/null)}"
if [ -n "$HF_TOKEN_VALUE" ]; then
    launch phonon TTS_HF_TOKEN="$HF_TOKEN_VALUE"
    read_through "Davi (Phonon)"
else
    print "  skip Davi (Phonon): no Hugging Face token (TTS_HF_TOKEN)"
fi

FISH_KEY_VALUE="${TTS_FISH_KEY:-$(sed -n 's/^FISH_API_KEY=//p' ~/.ciromacielos/.env 2>/dev/null | tr -d '"' | head -1)}"
if [ -n "$FISH_KEY_VALUE" ]; then
    launch fish TTS_FISH_KEY="$FISH_KEY_VALUE"
    read_through "Rafael (Fish)"
else
    print "  skip Rafael (Fish): no Fish Audio key (TTS_FISH_KEY)"
fi

# No key for the chosen voice: no part, no audio, only the message (the player shows it for a
# moment as an empty session) and the Voice pane.
launch phonon
send "speak Esta leitura não deve começar."
sleep 1
s=$(state)
[ "$(print -r -- "$s" | sed -n 's/.* parts=\([^ ]*\).*/\1/p')" = 0 ] && [ "$(print -r -- "$s" | sed -n 's/.* ready=\([^ ]*\).*/\1/p')" = no ] \
    && print -r -- "$s" | grep -q -E "hint=(Falta configurar a voz|The voice isn't set up)" \
    && ok "with no key, no reading starts and the set-up message shows" || bad "no-key case: $s"

# ⌘V pastes into the key field: a menu bar app gets ⌘ keys only through an Edit menu.
saved_clipboard=$(pbpaste)
printf 'hf_colagemteste9876' | pbcopy
# The no-key message holds the player for 1.8 s; wait for it to go, as a person would.
sleep 2.5; send "open voice"; sleep 1; send focus-field; send "key cmd+v"; send enter; sleep 0.5
printf '%s' "$saved_clipboard" | pbcopy
[ "$(cat "$WORK/data-phonon/huggingface-token.secret" 2>/dev/null)" = hf_colagemteste9876 ] \
    && ok "⌘V pastes a key into the Voice pane" || bad "⌘V did not paste into the key field ($(grep -o '\[e2e\] focus.*' "$WORK/app.log" | tail -1))"

print "$([ $fails = 0 ] && echo "Check passed" || echo "$fails failure(s)")"
exit $fails
