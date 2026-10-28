# Text to Speech by Ciro Cesar Maciel

**Select text in any Mac app, press one shortcut, and hear it read aloud.**

One of [six free, open-source Mac apps](#more-from-ciro-cesar-maciel) by [Ciro Cesar Maciel](https://ciromaciel.click/?ref=oss-text-to-speech).

**[Watch the 1-minute video](https://youtu.be/EqDHxP9jKp4)**

[![As seen on Open Source Alternatives](https://www.opensourcealternatives.to/badge-osa.svg)](https://www.opensourcealternatives.to) [![Text to Speech by Ciro Cesar Maciel | AlternativeTo](https://alternativeto.net/static/badges/badge-compact-color.svg)](https://alternativeto.net/software/text-to-speech-by-ciro-cesar-maciel/about/?utm_source=badge&utm_medium=referral)

Rafael, a natural Brazilian Portuguese voice from [Fish Audio](https://fish.audio), reads it over the internet, and starts in under a second: the audio plays as it arrives. A small floating player shows the word being spoken and goes away when the reading ends. No account, no telemetry. A native menu bar app in Swift: 3 MB on disk, about 30 MB of memory while reading.

[Português](README.pt-BR.md)

![Text to Speech: the settings window, on the Shortcut screen](docs/overview.webp)

## Install

```bash
curl -fsSL https://blob.ciromaciel.click/tools/text-to-speech/install.sh | bash
```

The script downloads the latest `.dmg`, copies Text to Speech to `/Applications` and opens it.

With [Homebrew](https://github.com/ciro-maciel/homebrew-tap): `brew install --cask ciro-maciel/tap/ciro-text-to-speech`.

Prefer the disk image? [Download Text-to-Speech-macos.dmg](https://blob.ciromaciel.click/tools/text-to-speech/latest/Text-to-Speech-macos.dmg). Open it and drag Text to Speech to Applications. It is signed with Developer ID and notarized by Apple, so macOS opens it with no warning.

The app asks for one permission, **Accessibility**: reading the selection sends Cmd + C to the app in front, and macOS only allows that to a trusted app.

## How it works

1. Select text anywhere: an e-mail, a PDF, a web page, a document.
2. Press **Cmd + Shift + S**. The app copies the selection, puts your clipboard back the way it was, and starts reading.
3. Listen. The player floats on the screen and closes when the reading ends.

| Key | What it does |
| --- | --- |
| Cmd + Shift + S | Read the selection. Can be changed in the settings window |
| Esc | Stop |
| Space | Pause and resume |
| Left / Right arrow | Back or forward one part |
| - / + | Slower or faster |

The text is read in parts, whole paragraphs where it can, so the voice keeps the sense of what it reads. The first part is short, and its audio plays while it still arrives, so the voice starts in under a second even on a long text.

## Privacy: what goes where

Each part of the text you selected, and the speed, go over HTTPS to the Text to Speech server (`manager.ciromaciel.click`, the same one the web page at [ciromaciel.click/tools/text-to-speech](https://ciromaciel.click/tools/text-to-speech?ref=oss-text-to-speech) uses). The server sends it to Fish Audio, which makes the audio, and passes the MP3 and the time of each word on as they come. The server does not store the text. The app holds no API key.

Nothing else leaves your Mac: the interface font is bundled, there is no analytics, no account and no update check.

### Use your own server

The app calls `POST <server>/speak-stream` with `{ "text": "...", "speed": 1.0 }` and reads NDJSON back, one line per piece: `{ "audio": "<base64 MP3>" }`, `{ "chunk": 0, "offset": 0, "words": [{ "text", "start", "end" }] }` (the latest timings of a text chunk, `offset` seconds into the part), and finally `{ "done": true }`. To point the app at a server of your own:

```bash
defaults write click.ciromaciel.text-to-speech serverURL https://your-server.example/text-to-speech
```

or set `TEXT_TO_SPEECH_SERVER` in the environment of the app. With neither, the app uses the public server.

## Build it yourself

You need macOS 14 or later on Apple Silicon and the Xcode Command Line Tools (Swift 5.10 or later).

```bash
git clone https://github.com/ciro-maciel/text-to-speech.git
cd text-to-speech
scripts/build.sh             # → dist/Text to Speech.app
scripts/check.sh             # the reading logic, then a short reading out loud through the server
```

Without a Developer ID certificate the build is signed ad hoc, so macOS asks for Accessibility again after each rebuild. `scripts/dist.sh` bumps the version, builds, packs the `.dmg`, has Apple notarize it (keychain profile `notary`) and installs it.

## Limits

- macOS 14 or newer on Apple Silicon.
- Rafael speaks Brazilian Portuguese: text in another language is read with a Portuguese accent. The interface is in English and Brazilian Portuguese, following the Mac's language.
- The voice depends on the public server and on Fish Audio; when either is busy, a part can fail. There is no offline voice.
- No automatic updates yet: install the new version the same way as the first.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Montserrat and the icons keep their own licenses: see [NOTICE](NOTICE).

---

## More from Ciro Cesar Maciel

I build software on my own, with a team of AI agents, and open what I can. Six native Mac apps, all free, MIT, signed and notarized by Apple, in English and Brazilian Portuguese: [Cleaner](https://github.com/ciro-maciel/cleaner), the Mac cleaner that shows you everything before it deletes anything · [Screenshots](https://github.com/ciro-maciel/screenshots), capture, annotate and record the screen, with nothing leaving your Mac · [Speech to Text](https://github.com/ciro-maciel/speech-to-text), dictation by shortcut, with Parakeet running on your Mac · [Assistant](https://github.com/ciro-maciel/voice-assistant), Claude Code by voice · [Windows](https://github.com/ciro-maciel/windows), snap windows into place with a shortcut or by dragging them to the edge · [Text to Speech](https://github.com/ciro-maciel/text-to-speech), select text in any app and hear it read aloud (this one).

Beyond the apps: [free tools for the browser](https://ciromaciel.click/tools?ref=oss-text-to-speech), [books](https://ciromaciel.click/books?ref=oss-text-to-speech), and [Infrastructure](https://myinfrastructure.click/?ref=oss-text-to-speech), the infrastructure AI agents already know how to run.

**Follow along.** [Follow @ciro-maciel](https://github.com/ciro-maciel) for the next open-source apps, click **Watch → Custom → Releases** above for every new version, and see how it is all made on [YouTube](https://www.youtube.com/@ciro-maciel) and at [ciromaciel.click](https://ciromaciel.click/?ref=oss-text-to-speech).
