# Contributing

Thanks for helping. Text to Speech reads whatever people select, from any app, so the bar is "the text goes only where the person chose to send it".

## Setup

```bash
scripts/build.sh             # → dist/Text to Speech.app
```

You need macOS 14 or later on Apple Silicon and the Xcode Command Line Tools (Swift 5.10 or later). There are no dependencies.

## Before you open a pull request

Build the app and run the end-to-end check on your Mac. It checks the reading logic against the frozen answers of 0.x, then runs a copy of the app under another identifier and reads a short text through the server, out loud:

```bash
scripts/build.sh
scripts/check.sh
```

If your change touches the window or the player, attach a capture.

## House rules

- **The text goes only where the person chose.** It goes to the configured server, part by part, and nowhere else. A new network call needs a reason in the pull request and a line in the README's Privacy section.
- No analytics, no account, no remote font or image.
- The clipboard is put back the way it was after the selection is read.
- Code, comments and file names in English.
- Every user-facing string exists in English and Brazilian Portuguese, with the same keys in `Resources/en.lproj` and `Resources/pt-BR.lproj`; a change that adds text adds both.
- The bundle identifier (`click.ciromaciel.text-to-speech`) never changes: macOS ties Accessibility to it.

## Reporting a bug

Say which macOS version, which Mac, which voice and what the player showed. Never paste a private text into an issue: reproduce it with a sentence of your own.

For anything that could expose someone's text, read [SECURITY.md](SECURITY.md) first.
