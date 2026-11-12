# Notes for coding agents

Text to Speech is a native macOS menu bar app: AppKit and SwiftUI, one Swift package with no dependencies (`Package.swift`), wrapped into `dist/Text to Speech.app` by `scripts/build.sh`. It reads the selection aloud with the voice the person picks: Davi, Phonon's Brazilian Portuguese model run on the Mac by Gradium's `ptts` command shipped inside the app, or Rafael, from Fish Audio, called directly with the person's own Fish key. Since 1.1.0 there is no Text to Speech server in the path. Versions 0.x were a Tauri app with an offline Piper voice too; the last one is commit `33bd6dd`.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/TextToSpeech/main.swift` | The app: menu bar glyph and menu, the reading shortcut, Esc while reading, the window, single instance, end-to-end commands |
| `Sources/TextToSpeech/Reading.swift` | Pure logic, ported rule for rule from 0.x `reading.js`: how a text becomes parts, when each word is spoken, the clock |
| `Sources/TextToSpeech/Player.swift` | The reading session (parts ahead, pause, jump, speed) and the floating player |
| `Sources/TextToSpeech/Playback.swift` | Plays the MP3 as it arrives: AudioFileStream, AVAudioConverter, AVAudioPlayerNode with time-pitch |
| `Sources/TextToSpeech/Voice.swift` | The two voices: Fish (`/v1/tts/stream/with-timestamp`, SSE, the person's key) and Phonon (`ptts` 0.6.0 per part of up to 150 words, `VoiceEngine.parts`; WAV trimmed and brought to -16 LUFS by `Wave`, as the CCM Stack voice plays it), and reading the selection (⌘C with a sentinel, clipboard put back) |
| `Sources/TextToSpeech/Secrets.swift` | The Fish key and the Hugging Face token in the login keychain (a file in TTS_DATA_DIR for end-to-end runs) |
| `Sources/TextToSpeech/Settings.swift` | Settings (UserDefaults) and the one-time import of the 0.x `config.json` |
| `Sources/TextToSpeech/Screens.swift` | The window's panes |
| `Sources/TextToSpeech/MacShell.swift`, `Theme.swift`, `Components.swift`, `Controls.swift` | The house frame and controls, the same as Cleaner and Speech to Text |
| `Resources/` | App icon, Montserrat, Tabler and menu bar icons as template PDFs, `en.lproj` and `pt-BR.lproj` |
| `scripts/build.sh`, `dist.sh`, `check.sh`, `assets.mjs` | Build and sign (fetches `ptts` pinned by version and SHA-256, signs it before the app); bump, notarize and install; end-to-end check; regenerate the icon PDFs |
| `scripts/fixtures/` | 0.x `reading.js` answers, frozen, that `check.sh` compares the Swift port with |
| `scripts/release/` | `.dmg`, publishing to blob.ciromaciel.click, the one-line installer; used by `.github/workflows/release.yml` |

## Before you say it works

```bash
scripts/build.sh
scripts/check.sh
```

`check.sh` compares the reading logic with the frozen answers, then, for each voice with a credential (`TTS_HF_TOKEN`, `TTS_FISH_KEY`, or the ones saved on the Mac), runs a copy of the app under another identifier with `TTS_DATA_DIR` in a temporary folder and reads a short text out loud; last, with no key, a reading must not start. The hooks (`TTS_E2E_TRIGGER`, `TTS_DATA_DIR`, `TTS_ENGINE`, `--reading <cases.json>`) drive any other check; never run one against the person's own data folder or keychain.

## Rules that must hold

- With Davi the text never leaves the Mac; the only network call is the model download from Hugging Face with the person's token, pinned to one revision so it loads from the cache afterwards. With Rafael the text goes only to `api.fish.audio`, part by part, with the person's key. No other network call.
- Keys live only in the login keychain (`Secrets.swift`), never in UserDefaults, logs or the repository. The app ships no key of its own.
- Phonon's Portuguese model is CC BY-NC 4.0: the app never ships or mirrors it; each person downloads it under the terms they accept on Hugging Face.
- The bundle identifier `click.ciromaciel.text-to-speech` and the executable name `text-to-speech` never change, and builds are signed with the same identity: macOS ties Accessibility to them, and the 0.x login item points to the executable.
- The version lives in `VERSION`. Publishing is the release workflow, run by hand, or `scripts/dist.sh` and the release scripts locally.
- Code, comments and file names are in English.
- Every user-facing string exists in English and Brazilian Portuguese: `Resources/en.lproj` and `Resources/pt-BR.lproj`, always the same keys in both. Every on-screen string goes through `L(...)`.
- The window follows the house frame (Cleaner's): logotype, grouped menu, status line, version line. Icons only from Tabler, as template PDFs made by `scripts/assets.mjs`.
