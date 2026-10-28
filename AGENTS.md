# Notes for coding agents

Text to Speech is a native macOS menu bar app: AppKit and SwiftUI, one Swift package with no dependencies (`Package.swift`), wrapped into `dist/Text to Speech.app` by `scripts/build.sh`. It reads the selection aloud with Rafael, a Fish Audio voice, through the Text to Speech server. Versions 0.x were a Tauri app with an offline Piper voice too; the last one is commit `33bd6dd`.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/TextToSpeech/main.swift` | The app: menu bar glyph and menu, the reading shortcut, Esc while reading, the window, single instance, end-to-end commands |
| `Sources/TextToSpeech/Reading.swift` | Pure logic, ported rule for rule from 0.x `reading.js`: how a text becomes parts, when each word is spoken, the clock |
| `Sources/TextToSpeech/Player.swift` | The reading session (parts ahead, pause, jump, speed) and the floating player |
| `Sources/TextToSpeech/Playback.swift` | Plays the MP3 as it arrives: AudioFileStream, AVAudioConverter, AVAudioPlayerNode with time-pitch |
| `Sources/TextToSpeech/Voice.swift` | `POST /speak-stream` (NDJSON) and reading the selection (⌘C with a sentinel, clipboard put back) |
| `Sources/TextToSpeech/Settings.swift` | Settings (UserDefaults) and the one-time import of the 0.x `config.json` |
| `Sources/TextToSpeech/Screens.swift` | The window's panes |
| `Sources/TextToSpeech/MacShell.swift`, `Theme.swift`, `Components.swift`, `Controls.swift` | The house frame and controls, the same as Cleaner and Speech to Text |
| `Resources/` | App icon, Montserrat, Tabler and menu bar icons as template PDFs, `en.lproj` and `pt-BR.lproj` |
| `scripts/build.sh`, `dist.sh`, `check.sh`, `assets.mjs` | Build and sign; bump, notarize and install; end-to-end check; regenerate the icon PDFs |
| `scripts/fixtures/` | 0.x `reading.js` answers, frozen, that `check.sh` compares the Swift port with |
| `scripts/release/` | `.dmg`, publishing to blob.ciromaciel.click, the one-line installer; used by `.github/workflows/release.yml` |

## Before you say it works

```bash
scripts/build.sh
scripts/check.sh
```

`check.sh` compares the reading logic with the frozen answers, then runs a copy of the app under another identifier with `TTS_DATA_DIR` in a temporary folder and reads a short text through the real server, out loud. The hooks (`TTS_E2E_TRIGGER`, `TTS_DATA_DIR`, `--reading <cases.json>`) drive any other check; never run one against the person's own data folder.

## Rules that must hold

- The text goes only to the configured server (`serverURL`, `TEXT_TO_SPEECH_SERVER`, else `manager.ciromaciel.click/text-to-speech`), part by part. The app holds no Fish key. No other network call.
- The server's `speak-stream` route (in `ciro-maciel/applications`, `apps/text-to-speech/manager`) is what the app needs; `speak-timed` stays for 0.x copies and the web page.
- The bundle identifier `click.ciromaciel.text-to-speech` and the executable name `text-to-speech` never change, and builds are signed with the same identity: macOS ties Accessibility to them, and the 0.x login item points to the executable.
- The version lives in `VERSION`. Publishing is the release workflow, run by hand, or `scripts/dist.sh` and the release scripts locally.
- Code, comments and file names are in English.
- Every user-facing string exists in English and Brazilian Portuguese: `Resources/en.lproj` and `Resources/pt-BR.lproj`, always the same keys in both. Every on-screen string goes through `L(...)`.
- The window follows the house frame (Cleaner's): logotype, grouped menu, status line, version line. Icons only from Tabler, as template PDFs made by `scripts/assets.mjs`.
