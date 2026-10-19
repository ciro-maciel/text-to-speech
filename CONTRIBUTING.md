# Contributing

Thanks for helping. Text to Speech reads whatever people select, from any app, so the bar is "the text goes only where the person chose to send it".

## Setup

```bash
bun install
bun run dev
```

You need the Xcode Command Line Tools, Rust, Bun and CMake. Use Bun, not npm: there is one lockfile, `bun.lock`.

## Before you open a pull request

Run the tests, build the app and check that the packaged build reads aloud with both voices. The check runs with no window and keeps everything in the folder you give it:

```bash
bun test src
bun run build
"/tmp/tts-target/release/bundle/macos/Text to Speech.app/Contents/MacOS/text-to-speech" --self-test /tmp/tts-check
afplay /tmp/tts-check/rafael.mp3 && afplay /tmp/tts-check/piper.wav
```

Then select some text in another app and press the shortcut. If your change touches a window, attach a capture.

## House rules

- **The text goes only where the person chose.** With Piper it never leaves the Mac. With Rafael it goes to the configured server and nowhere else. A new network call needs a reason in the pull request and a line in the README's Privacy section.
- No analytics, no account, no remote font or script: the windows load only what is in `src/`.
- The clipboard is put back the way it was after the selection is read.
- Code, comments and file names in English; the interface text is in Portuguese for now.
- The bundle identifier (`click.ciromaciel.text-to-speech`) never changes: macOS ties Accessibility to it.

## Reporting a bug

Say which macOS version, which Mac, which voice and what the player showed. Never paste a private text into an issue: reproduce it with a sentence of your own.

For anything that could expose someone's text, read [SECURITY.md](SECURITY.md) first.
